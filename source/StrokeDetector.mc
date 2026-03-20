using Toybox.Sensor;
using Toybox.Math;
using Toybox.System;
using Toybox.Application;

// Orientation-independent stroke detection from accelerometer.
//
// Problem: Edge is mounted at arbitrary angle on the boat, so we
// cannot assume which axis is "forward".
//
// Solution: Subtract gravity estimate (slow-moving average per axis)
// to get linear acceleration, then use its magnitude for detection.
// The magnitude peaks during drive phase regardless of mounting angle.
//
// Signal flow:
//   raw x,y,z -> subtract gravity_est -> linear accel -> magnitude
//   -> EMA smoothing -> peak detection (above threshold) -> stroke

class StrokeDetector {

    // Stroke detection state
    var strokeCount = 0;
    var strokeRate = 0.0;      // strokes per minute
    var lastStrokeTime = 0;    // ms timestamp of last detected stroke

    // 30-second sliding window of stroke timestamps (ms)
    const WINDOW_MS = 30000;
    var strokeTimes = new [20]; // max ~18 strokes in 30s (at 35spm high rate)
    var strokeTimesIdx = 0;
    var strokeTimesCount = 0;

    // Gravity estimation (slow EMA per axis, converges to gravity vector)
    var gravX = 0.0;
    var gravY = 0.0;
    var gravZ = 1000.0;  // assume ~1G downward initially
    const GRAV_ALPHA = 0.01; // very slow -- tracks gravity, not motion

    // Signal processing on linear acceleration magnitude
    var emaValue = 0.0;
    var prevEma = 0.0;
    var wasPeak = false;   // was signal above threshold on prev sample?
    var running = false;

    // Tuning: adjustable at runtime via menu
    // Now positive: magnitude threshold for detecting drive phase peak
    var catchThreshold = 900.0; // milliG linear accel magnitude

    // Fixed constants
    // Typical: 20 spm (3s/stroke), high: 35 spm (1.7s), absolute max: 60 spm (1s)
    const EMA_ALPHA = 0.15;
    const MIN_STROKE_INTERVAL = 1700; // ms, max 35 spm (high rate)
    const MAX_STROKE_INTERVAL = 6000; // ms, min 10 spm (very slow paddling)

    // 1-second statistics for FIT recording
    // Raw axes (mean per window for compact recording)
    var rawXsum = 0.0;
    var rawYsum = 0.0;
    var rawZsum = 0.0;
    // Linear accel magnitude stats
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
            // Migrate old negative values to positive
            if (catchThreshold < 0) {
                catchThreshold = -catchThreshold;
                Application.Storage.setValue("catchThreshold", catchThreshold.toNumber());
            }
        }
    }

    function start() {
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
        gravX = 0.0;
        gravY = 0.0;
        gravZ = 1000.0;
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

        for (var i = 0; i < n; i++) {
            var rx = xData[i].toFloat();
            var ry = yData[i].toFloat();
            var rz = zData[i].toFloat();

            // Update gravity estimate (slow EMA)
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

            // Stroke detection: detect peak (above threshold) then falling
            // A stroke = magnitude rises above threshold then falls below
            var isPeak = (emaValue > catchThreshold);

            if (wasPeak && !isPeak) {
                // Falling edge after peak = end of drive phase = stroke
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

    // Called once per second to refresh stroke rate even when no new strokes
    function refreshStrokeRate() {
        strokeRate = computeStrokeRate(System.getTimer());
    }

    // Called once per second to snapshot stats and reset window
    // Returns: [rawXmean, rawYmean, rawZmean, linMagMin, linMagMax, linMagMean, ema]
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
        // Reset window
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
        // Recompute rate from 30s window
        strokeRate = computeStrokeRate(ts);
    }

    // Count strokes within last 30 seconds, normalize to per-minute
    function computeStrokeRate(now) {
        if (strokeTimesCount == 0) { return 0.0; }
        var cutoff = now - WINDOW_MS;
        var count = 0;
        for (var i = 0; i < strokeTimesCount; i++) {
            if (strokeTimes[i] >= cutoff) {
                count++;
            }
        }
        if (count < 2) { return 0.0; }
        // strokes in 30s -> strokes per minute
        return count * 60000.0 / WINDOW_MS;
    }
}
