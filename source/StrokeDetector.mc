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

            // Track statistics for FIT recording
            rawXsum += rx;
            rawYsum += ry;
            rawZsum += rz;
            linMagSum += mag;
            if (sampleCount == 0) {
                linMagMin = mag;
                linMagMax = mag;
            } else {
                if (mag < linMagMin) { linMagMin = mag; }
                if (mag > linMagMax) { linMagMax = mag; }
            }
            sampleCount++;

            // EMA on magnitude
            emaValue = EMA_ALPHA * mag + (1.0 - EMA_ALPHA) * emaValue;

            // Stroke detection
            var isPeak = (emaValue > catchThreshold);

            if (wasPeak && !isPeak) {
                var interval = now - lastStrokeTime;

                if (lastStrokeTime > 0 &&
                    interval >= MIN_STROKE_INTERVAL &&
                    interval <= MAX_STROKE_INTERVAL) {
                    strokeCount++;
                    recordStrokeTime(now);
                    lastStrokeTime = now;
                } else if (lastStrokeTime == 0 ||
                           interval > MAX_STROKE_INTERVAL) {
                    strokeCount++;
                    recordStrokeTime(now);
                    lastStrokeTime = now;
                }
            }

            wasPeak = isPeak;
            prevEma = emaValue;
        }
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
            calibrating = false;
            calibrated = true;
        }
    }

    function refreshStrokeRate() {
        strokeRate = computeStrokeRate(System.getTimer());
    }

    function getAccelStats() {
        var xm = 0.0;
        var ym = 0.0;
        var zm = 0.0;
        var lmean = 0.0;
        if (sampleCount > 0) {
            var sc = sampleCount.toFloat();
            xm = rawXsum / sc;
            ym = rawYsum / sc;
            zm = rawZsum / sc;
            lmean = linMagSum / sc;
        }
        emaSnapshot = emaValue;
        var stats = [xm, ym, zm, linMagMin, linMagMax, lmean, emaSnapshot];
        rawXsum = 0.0;
        rawYsum = 0.0;
        rawZsum = 0.0;
        linMagMin = 0.0;
        linMagMax = 0.0;
        linMagSum = 0.0;
        sampleCount = 0;
        return stats;
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
