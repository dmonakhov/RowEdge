using Toybox.Sensor;
using Toybox.Math;
using Toybox.System;
using Toybox.Application;

// Orientation-independent stroke detection from accelerometer.
//
// Two-phase operation:
//   1. CALIBRATION (2s): Boat stationary, averages accel to find gravity vector
//   2. DETECTION: Subtracts calibrated gravity, uses magnitude for stroke peaks
//
// Signal flow (detection phase):
//   raw x,y,z -> subtract calibrated gravity -> linear accel -> magnitude
//   -> EMA smoothing -> peak detection (above threshold) -> stroke

class StrokeDetector {

    // Calibration state
    var calibrating = false;
    var calibrated = false;
    var calSumX = 0.0;
    var calSumY = 0.0;
    var calSumZ = 0.0;
    var calCount = 0;
    const CAL_DURATION_MS = 2000; // 2 seconds
    var calStartTime = 0;

    // Stroke detection state
    var strokeCount = 0;
    var strokeRate = 0.0;
    var lastStrokeTime = 0;

    // Circular buffer of last N stroke timestamps for SPM calculation
    const SPM_WINDOW = 6;  // average over last 6 strokes
    var strokeTimes = new [10];
    var strokeTimesIdx = 0;
    var strokeTimesCount = 0;

    // Gravity vector (set by calibration or slow EMA fallback)
    var gravX = 0.0;
    var gravY = 0.0;
    var gravZ = 1000.0;
    const GRAV_ALPHA = 0.005; // very slow drift correction after calibration

    // Boat forward unit vector in Y-Z plane (computed from gravity after calibration).
    // X axis is perpendicular to boat movement, so forward = cross(X_unit, gravity)
    // normalized and projected to Y-Z plane: F = normalize(0, -gz, gy)
    var fwdY = 0.0;
    var fwdZ = 0.0;

    // Signal processing on linear acceleration magnitude
    var emaValue = 0.0;
    var prevEma = 0.0;
    var wasPeak = false;
    var running = false;

    // Tuning: adjustable at runtime via menu
    var catchThreshold = 200.0;

    // Fixed constants
    const EMA_ALPHA = 0.15;
    const MIN_STROKE_INTERVAL = 1700; // ms, max 35 spm
    const MAX_STROKE_INTERVAL = 15000; // ms, min 4 spm

    // 1-second statistics for FIT recording
    var rawXsum = 0.0;
    var rawYsum = 0.0;
    var rawZsum = 0.0;
    var linMagMin = 0.0;
    var linMagMax = 0.0;
    var linMagSum = 0.0;
    var emaSnapshot = 0.0;
    var sampleCount = 0;

    // Forward acceleration stats (signed: positive=drive, negative=recovery)
    var fwdAccelSum = 0.0;
    var fwdAccelMin = 0.0;
    var fwdAccelMax = 0.0;

    // High-frequency forward accel buffer (25 samples/sec, written to FIT)
    const HFREQ_BUF_SIZE = 25;
    var hfreqBuf = new [25];
    var hfreqCount = 0;

    // Demo sample counter (for accurate stroke interval in demo mode)
    var demoSampleCount = 0;
    var demoLastStrokeSample = 0;

    // Ring buffer for stroke curve display (4 seconds at 25Hz, covers >=15 SPM)
    const CURVE_BUF_SIZE = 100;
    var curveBuf = new [100];
    var curveBufIdx = 0;
    var curveBufCount = 0;

    // Last stroke snapshot for display
    var strokeCurve = null;      // array of fwd_accel samples for last stroke
    var strokeCurveLen = 0;
    var strokeDriveTime = 0.0;   // seconds
    var strokeRecovTime = 0.0;   // seconds
    var strokePeak = 0.0;        // mG
    var strokeForceRatio = 0.0;  // avg/peak (0-1)
    var strokeDeltaV = 0.0;      // m/s, impulse
    var strokeCatchDur = 0.0;    // seconds, time from min accel to zero-crossing
    var strokeCatchSlope = 0.0;  // mG/s, rate of accel increase at catch
    // Display range within strokeCurve: catch + drive + recovery start
    var strokeDispStart = 0;
    var strokeDispEnd = 0;

    function initialize() {
        for (var i = 0; i < strokeTimes.size(); i++) {
            strokeTimes[i] = 0;
        }
        var saved = Application.Storage.getValue("catchThreshold");
        if (saved != null) {
            catchThreshold = saved.toFloat();
            if (catchThreshold < 0) {
                catchThreshold = -catchThreshold;
                Application.Storage.setValue("catchThreshold", catchThreshold.toNumber());
            }
        }
    }

    // Start accelerometer in calibration mode
    function startCalibration() {
        calibrating = true;
        calibrated = false;
        calSumX = 0.0;
        calSumY = 0.0;
        calSumZ = 0.0;
        calCount = 0;
        calStartTime = System.getTimer();
        startAccel();
    }

    // Start accelerometer in detection mode (skip calibration)
    function start() {
        if (!calibrating) {
            startAccel();
        }
    }

    function startAccel() {
        if (!running) {
            running = true;
            var maxRate = Sensor.getMaxSampleRate();
            var options = {
                :period => 1,
                :sampleRate => maxRate,
                :enableAccelerometer => true
            };
            try {
                Sensor.registerSensorDataListener(method(:onSensorData), options);
            } catch (e) {
                System.println("Accel init failed");
                running = false;
            }
        }
    }

    function stop() {
        if (running) {
            running = false;
            try {
                Sensor.unregisterSensorDataListener();
            } catch (e) {
            }
        }
    }

    function reset() {
        strokeCount = 0;
        strokeRate = 0.0;
        lastStrokeTime = 0;
        strokeTimesIdx = 0;
        strokeTimesCount = 0;
        emaValue = 0.0;
        prevEma = 0.0;
        wasPeak = false;
        calibrating = false;
        calibrated = false;
        gravX = 0.0;
        gravY = 0.0;
        gravZ = 1000.0;
        fwdY = 0.0;
        fwdZ = 0.0;
        demoSampleCount = 0;
        demoLastStrokeSample = 0;
    }

    // Returns true when calibration is complete
    function isCalibrationDone() {
        return calibrated;
    }

    function onSensorData(sensorData as Sensor.SensorData) as Void {
        if (!running) { return; }

        var accelData = sensorData.accelerometerData;
        if (accelData == null) { return; }

        var xData = accelData.x;
        var yData = accelData.y;
        var zData = accelData.z;
        if (xData == null || yData == null || zData == null) { return; }

        var now = System.getTimer();
        var n = xData.size();
        if (yData.size() < n) { n = yData.size(); }
        if (zData.size() < n) { n = zData.size(); }

        if (calibrating) {
            processCalibration(xData, yData, zData, n, now);
            return;
        }

        for (var i = 0; i < n; i++) {
            var rx = xData[i].toFloat();
            var ry = yData[i].toFloat();
            var rz = zData[i].toFloat();

            // Slow drift correction on gravity (keeps it accurate over time)
            gravX = GRAV_ALPHA * rx + (1.0 - GRAV_ALPHA) * gravX;
            gravY = GRAV_ALPHA * ry + (1.0 - GRAV_ALPHA) * gravY;
            gravZ = GRAV_ALPHA * rz + (1.0 - GRAV_ALPHA) * gravZ;

            // Linear acceleration = raw - gravity
            var lx = rx - gravX;
            var ly = ry - gravY;
            var lz = rz - gravZ;

            // Magnitude of linear acceleration
            var mag = Math.sqrt(lx * lx + ly * ly + lz * lz);

            // Forward acceleration: dot(linear_accel, forward_vector)
            // Positive = drive (accelerating forward), negative = drag/recovery
            var fwdAccel = ly * fwdY + lz * fwdZ;

            // Buffer for high-frequency FIT recording
            if (hfreqCount < HFREQ_BUF_SIZE) {
                hfreqBuf[hfreqCount] = fwdAccel.toNumber();
                hfreqCount++;
            }

            // Ring buffer for stroke curve display
            curveBuf[curveBufIdx] = fwdAccel.toNumber();
            curveBufIdx = (curveBufIdx + 1) % CURVE_BUF_SIZE;
            if (curveBufCount < CURVE_BUF_SIZE) { curveBufCount++; }

            // Track statistics for FIT recording
            rawXsum += rx;
            rawYsum += ry;
            rawZsum += rz;
            linMagSum += mag;
            fwdAccelSum += fwdAccel;
            if (sampleCount == 0) {
                linMagMin = mag;
                linMagMax = mag;
                fwdAccelMin = fwdAccel;
                fwdAccelMax = fwdAccel;
            } else {
                if (mag < linMagMin) { linMagMin = mag; }
                if (mag > linMagMax) { linMagMax = mag; }
                if (fwdAccel < fwdAccelMin) { fwdAccelMin = fwdAccel; }
                if (fwdAccel > fwdAccelMax) { fwdAccelMax = fwdAccel; }
            }
            sampleCount++;

            // EMA on forward acceleration for stroke detection.
            // Use fwdAccel (signed) instead of magnitude -- isolates rowing
            // motion from lateral sway and vertical bounce.
            // Before calibration completes (fwdY=fwdZ=0), fall back to magnitude.
            var detectionSignal = (fwdY != 0.0 || fwdZ != 0.0) ? fwdAccel : mag;
            emaValue = EMA_ALPHA * detectionSignal + (1.0 - EMA_ALPHA) * emaValue;

            // Stroke detection: drive phase produces positive forward accel peak
            var isPeak = (emaValue > catchThreshold);

            if (wasPeak && !isPeak) {
                var interval = now - lastStrokeTime;

                if (lastStrokeTime > 0 &&
                    interval >= MIN_STROKE_INTERVAL &&
                    interval <= MAX_STROKE_INTERVAL) {
                    strokeCount++;
                    snapshotStrokeCurve(interval);
                    recordStrokeTime(now);
                    lastStrokeTime = now;
                } else if (lastStrokeTime == 0 ||
                           interval > MAX_STROKE_INTERVAL) {
                    strokeCount++;
                    snapshotStrokeCurve(interval);
                    recordStrokeTime(now);
                    lastStrokeTime = now;
                }
            }

            wasPeak = isPeak;
            prevEma = emaValue;
        }
    }

    // Process a single pre-computed forward acceleration sample (demo mode).
    // Feeds through the same EMA, stroke detection, ring buffer, and hfreq
    // pipeline as real sensor data, but skips gravity subtraction.
    function processDemoSample(fwdAccelMg) {
        var now = System.getTimer();
        var fwdAccel = fwdAccelMg.toFloat();
        var mag = fwdAccel > 0 ? fwdAccel : -fwdAccel;

        // High-frequency FIT buffer
        if (hfreqCount < HFREQ_BUF_SIZE) {
            hfreqBuf[hfreqCount] = fwdAccelMg;
            hfreqCount++;
        }

        // Ring buffer for stroke curve display
        curveBuf[curveBufIdx] = fwdAccelMg;
        curveBufIdx = (curveBufIdx + 1) % CURVE_BUF_SIZE;
        if (curveBufCount < CURVE_BUF_SIZE) { curveBufCount++; }

        // Stats
        fwdAccelSum += fwdAccel;
        linMagSum += mag;
        if (sampleCount == 0) {
            fwdAccelMin = fwdAccel;
            fwdAccelMax = fwdAccel;
            linMagMin = mag;
            linMagMax = mag;
        } else {
            if (fwdAccel < fwdAccelMin) { fwdAccelMin = fwdAccel; }
            if (fwdAccel > fwdAccelMax) { fwdAccelMax = fwdAccel; }
            if (mag < linMagMin) { linMagMin = mag; }
            if (mag > linMagMax) { linMagMax = mag; }
        }
        sampleCount++;
        demoSampleCount++;

        // EMA stroke detection (forward accel directly)
        emaValue = EMA_ALPHA * fwdAccel + (1.0 - EMA_ALPHA) * emaValue;
        var isPeak = (emaValue > catchThreshold);

        if (wasPeak && !isPeak) {
            // Use sample count for interval (accurate, unlike System.getTimer
            // which has 1s granularity when 25 samples share the same tick)
            var sampleInterval = demoSampleCount - demoLastStrokeSample;
            var intervalMs = sampleInterval * 40;  // 25Hz = 40ms per sample

            if (demoLastStrokeSample > 0 &&
                intervalMs >= MIN_STROKE_INTERVAL &&
                intervalMs <= MAX_STROKE_INTERVAL) {
                strokeCount++;
                snapshotStrokeCurve(intervalMs);
                recordStrokeTime(now);
                lastStrokeTime = now;
                demoLastStrokeSample = demoSampleCount;
            } else if (demoLastStrokeSample == 0 ||
                       intervalMs > MAX_STROKE_INTERVAL) {
                strokeCount++;
                snapshotStrokeCurve(intervalMs);
                recordStrokeTime(now);
                lastStrokeTime = now;
                demoLastStrokeSample = demoSampleCount;
            }
        }
        wasPeak = isPeak;
        prevEma = emaValue;
    }

    function processCalibration(xData, yData, zData, n, now) {
        // Accumulate raw samples to compute gravity vector
        for (var i = 0; i < n; i++) {
            calSumX += xData[i].toFloat();
            calSumY += yData[i].toFloat();
            calSumZ += zData[i].toFloat();
            calCount++;
        }

        // Check if calibration duration elapsed
        if (now - calStartTime >= CAL_DURATION_MS && calCount > 0) {
            // Set gravity from averaged static samples
            gravX = calSumX / calCount;
            gravY = calSumY / calCount;
            gravZ = calSumZ / calCount;
            computeForwardVector();
            calibrating = false;
            calibrated = true;
        }
    }

    // Compute boat forward unit vector from gravity.
    // Forward direction = perpendicular to gravity in Y-Z plane.
    // cross(X_unit, gravity) = (0, -gz, gy), then normalize.
    function computeForwardVector() {
        var fy = -gravZ;
        var fz = gravY;
        var mag = Math.sqrt(fy * fy + fz * fz);
        if (mag > 0.001) {
            fwdY = fy / mag;
            fwdZ = fz / mag;
        }
    }

    // Snapshot the ring buffer on stroke detection. Extract the last
    // stroke's worth of samples, compute drive/recovery metrics.
    function snapshotStrokeCurve(intervalMs) {
        // Number of samples for this stroke interval
        var nSamples = (intervalMs * 25 / 1000);  // 25Hz
        if (nSamples > curveBufCount) { nSamples = curveBufCount; }
        if (nSamples > CURVE_BUF_SIZE) { nSamples = CURVE_BUF_SIZE; }
        if (nSamples < 5) { return; }

        // Copy from ring buffer (oldest to newest)
        strokeCurve = new [nSamples];
        strokeCurveLen = nSamples;
        var startIdx = (curveBufIdx - nSamples + CURVE_BUF_SIZE) % CURVE_BUF_SIZE;
        for (var i = 0; i < nSamples; i++) {
            strokeCurve[i] = curveBuf[(startIdx + i) % CURVE_BUF_SIZE];
        }

        // Find peak and its index
        var dt = 0.04;  // 1/25Hz = 40ms
        var peak = 0.0;
        var peakIdx = 0;
        for (var i = 0; i < nSamples; i++) {
            var v = strokeCurve[i].toFloat();
            if (v > peak) { peak = v; peakIdx = i; }
        }

        // Find drive phase boundaries: scan outward from peak to find
        // zero-crossings. This identifies the contiguous positive region
        // around the peak, ignoring noise elsewhere.
        var driveStart = peakIdx;
        var driveEnd = peakIdx;
        // Scan backward from peak to find start of drive (last zero-crossing before peak)
        for (var i = peakIdx - 1; i >= 0; i--) {
            if (strokeCurve[i] <= 0) { break; }
            driveStart = i;
        }
        // Scan forward from peak to find end of drive (first zero-crossing after peak)
        for (var i = peakIdx + 1; i < nSamples; i++) {
            if (strokeCurve[i] <= 0) { break; }
            driveEnd = i;
        }

        var driveSamples = driveEnd - driveStart + 1;
        var recovSamples = nSamples - driveSamples;

        // Compute drive phase metrics
        var driveSum = 0.0;
        for (var i = driveStart; i <= driveEnd; i++) {
            driveSum += strokeCurve[i].toFloat();
        }

        strokePeak = peak;
        strokeDriveTime = driveSamples * dt;
        strokeRecovTime = recovSamples * dt;

        // Force ratio = mean(drive_accel) / peak
        if (peak > 0 && driveSamples > 0) {
            strokeForceRatio = (driveSum / driveSamples) / peak;
        } else {
            strokeForceRatio = 0.0;
        }

        // Delta-V = integral of fwd_accel over drive phase
        // Convert mG to m/s^2 (* 0.00981), multiply by dt
        strokeDeltaV = driveSum * dt * 0.00981;

        // Catch metrics: scan recovery phase before driveStart to find
        // minimum accel (deepest negative dip = catch impact).
        // Catch duration = time from min to driveStart (zero-crossing).
        // Catch slope = |min_accel| / catch_duration (mG/s).
        var minAccel = 0.0;
        var minIdx = driveStart;
        for (var i = 0; i < driveStart; i++) {
            var v = strokeCurve[i].toFloat();
            if (v < minAccel) { minAccel = v; minIdx = i; }
        }
        var catchSamples = driveStart - minIdx;
        if (catchSamples > 0 && minAccel < 0) {
            strokeCatchDur = catchSamples * dt;
            strokeCatchSlope = (-minAccel) / strokeCatchDur;
        } else {
            strokeCatchDur = 0.0;
            strokeCatchSlope = 0.0;
        }

        // Display range: catch + drive + small recovery tail
        // Start: 2 samples before catch dip for context
        // End: 5 samples past the true zero-crossing after drive
        strokeDispStart = minIdx > 2 ? minIdx - 2 : 0;
        // Find true zero-crossing after drive (first sample <= 0 after driveEnd)
        var zeroIdx = driveEnd + 1;
        while (zeroIdx < nSamples && strokeCurve[zeroIdx] > 0) {
            zeroIdx++;
        }
        strokeDispEnd = zeroIdx + 5;
        if (strokeDispEnd >= nSamples) { strokeDispEnd = nSamples - 1; }
    }

    function refreshStrokeRate() {
        strokeRate = computeStrokeRate(System.getTimer());
    }

    // Returns [rawXmean, rawYmean, rawZmean, linMagMin, linMagMax, linMagMean,
    //          ema, fwdAccelMean, fwdAccelMin, fwdAccelMax]
    function getAccelStats() {
        var xm = 0.0;
        var ym = 0.0;
        var zm = 0.0;
        var lmean = 0.0;
        var fmean = 0.0;
        if (sampleCount > 0) {
            var sc = sampleCount.toFloat();
            xm = rawXsum / sc;
            ym = rawYsum / sc;
            zm = rawZsum / sc;
            lmean = linMagSum / sc;
            fmean = fwdAccelSum / sc;
        }
        emaSnapshot = emaValue;
        var stats = [xm, ym, zm, linMagMin, linMagMax, lmean, emaSnapshot,
                     fmean, fwdAccelMin, fwdAccelMax];
        rawXsum = 0.0;
        rawYsum = 0.0;
        rawZsum = 0.0;
        linMagMin = 0.0;
        linMagMax = 0.0;
        linMagSum = 0.0;
        fwdAccelSum = 0.0;
        fwdAccelMin = 0.0;
        fwdAccelMax = 0.0;
        sampleCount = 0;
        return stats;
    }

    // Get high-frequency samples as array of packed SINT32 values.
    // Each SINT32 packs 2 sint16: low 16 bits = sample[2k], high 16 bits = sample[2k+1]
    // Returns array of 13 packed values (25 samples -> 12 pairs + 1 single).
    function getHfreqPacked() {
        var packed = new [13];
        for (var k = 0; k < 13; k++) {
            var idx = k * 2;
            var lo = (idx < hfreqCount) ? hfreqBuf[idx] : 0;
            var hi = (idx + 1 < hfreqCount) ? hfreqBuf[idx + 1] : 0;
            // Pack: low 16 bits = lo, high 16 bits = hi
            packed[k] = (lo & 0xFFFF) | ((hi & 0xFFFF) << 16);
        }
        hfreqCount = 0;
        return packed;
    }

    function recordStrokeTime(ts) {
        strokeTimes[strokeTimesIdx] = ts;
        strokeTimesIdx = (strokeTimesIdx + 1) % strokeTimes.size();
        if (strokeTimesCount < strokeTimes.size()) {
            strokeTimesCount++;
        }
        strokeRate = computeStrokeRate(ts);
    }

    function computeStrokeRate(now) {
        if (strokeTimesCount < 2) { return 0.0; }

        // Average interval from last N strokes
        var count = strokeTimesCount < SPM_WINDOW ? strokeTimesCount : SPM_WINDOW;
        var newestIdx = (strokeTimesIdx - 1 + strokeTimes.size()) % strokeTimes.size();
        var oldestIdx = (strokeTimesIdx - count + strokeTimes.size()) % strokeTimes.size();

        var newest = strokeTimes[newestIdx];
        var oldest = strokeTimes[oldestIdx];
        var span = newest - oldest;
        if (span <= 0) { return 0.0; }

        var avgInterval = span.toFloat() / (count - 1);

        // Estimate current stroke interval: time since last stroke,
        // but at least avgInterval (don't speed up the estimate)
        var sinceLast = (now - newest).toFloat();
        var lastInterval = sinceLast > avgInterval ? sinceLast : avgInterval;

        // If estimated interval exceeds max, no strokes happening
        if (lastInterval > MAX_STROKE_INTERVAL) { return 0.0; }

        // Normalized average: blend historical avg with current estimate
        var normInterval = (avgInterval * (count - 1) + lastInterval) / count;

        if (normInterval < MIN_STROKE_INTERVAL) { return 0.0; }
        return 60000.0 / normInterval;
    }
}
