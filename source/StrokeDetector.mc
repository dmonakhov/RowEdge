using Toybox.Sensor;
using Toybox.Math;
using Toybox.System;

// Detects rowing strokes from accelerometer data.
// Algorithm: smoothed peak detection on forward acceleration axis.
//
// The Edge is mounted on the boat. During rowing:
//   Drive phase  -> boat accelerates forward (positive accel)
//   Recovery     -> boat decelerates (negative accel)
//   Catch point  -> sharp negative-to-positive transition
//
// We detect catch points as negative peaks (local minima) in the
// smoothed forward acceleration signal.

class StrokeDetector {

    // Stroke detection state
    var strokeCount = 0;
    var strokeRate = 0.0;      // strokes per minute
    var lastStrokeTime = 0;    // ms timestamp of last detected stroke

    // Smoothing buffer for inter-stroke intervals (for stable SPM)
    var intervalBuf = new [8];
    var intervalIdx = 0;
    var intervalCount = 0;

    // Signal processing state
    var emaValue = 0.0;        // exponential moving average of forward accel
    var prevEma = 0.0;         // previous EMA value (for slope detection)
    var wasNegative = false;   // was signal below threshold on prev sample?
    var running = false;

    // Tuning constants
    const EMA_ALPHA = 0.15;           // smoothing factor (lower = more smooth)
    const MIN_STROKE_INTERVAL = 1200; // ms, max ~50 spm
    const MAX_STROKE_INTERVAL = 6000; // ms, min ~10 spm
    const CATCH_THRESHOLD = -80.0;    // milliG, minimum dip to count as stroke

    function initialize() {
        for (var i = 0; i < intervalBuf.size(); i++) {
            intervalBuf[i] = 0;
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
                // ignore
            }
        }
    }

    function reset() {
        strokeCount = 0;
        strokeRate = 0.0;
        lastStrokeTime = 0;
        intervalIdx = 0;
        intervalCount = 0;
        emaValue = 0.0;
        prevEma = 0.0;
        wasNegative = false;
    }

    function onSensorData(sensorData as Sensor.SensorData) as Void {
        if (!running) { return; }

        var accelData = sensorData.accelerometerData;
        if (accelData == null) { return; }

        // Use Y axis as forward direction (along boat length)
        // Edge mounted horizontally on stem: Y = forward/backward
        // Adjust if mounting orientation differs
        var yData = accelData.y;
        if (yData == null) { return; }

        var timestamps = accelData.timestamp;
        var now = System.getTimer(); // ms monotonic clock

        for (var i = 0; i < yData.size(); i++) {
            var sample = yData[i].toFloat();
            var sampleTime;
            if (timestamps != null && i < timestamps.size()) {
                sampleTime = timestamps[i];
            } else {
                sampleTime = now;
            }

            // Exponential moving average
            emaValue = EMA_ALPHA * sample + (1.0 - EMA_ALPHA) * emaValue;

            // Detect negative-to-positive zero crossing after a dip below threshold
            // This corresponds to the "catch" point
            var isNegative = (emaValue < CATCH_THRESHOLD);

            if (wasNegative && !isNegative) {
                // Rising edge: potential stroke
                var interval = sampleTime - lastStrokeTime;

                if (lastStrokeTime > 0 &&
                    interval >= MIN_STROKE_INTERVAL &&
                    interval <= MAX_STROKE_INTERVAL) {
                    // Valid stroke detected
                    strokeCount++;
                    recordInterval(interval);
                    strokeRate = computeStrokeRate();
                    lastStrokeTime = sampleTime;
                } else if (lastStrokeTime == 0 ||
                           interval > MAX_STROKE_INTERVAL) {
                    // First stroke or gap too long -- restart
                    strokeCount++;
                    lastStrokeTime = sampleTime;
                }
                // If interval < MIN_STROKE_INTERVAL, ignore (noise)
            }

            wasNegative = isNegative;
            prevEma = emaValue;
        }
    }

    function recordInterval(interval) {
        intervalBuf[intervalIdx] = interval;
        intervalIdx = (intervalIdx + 1) % intervalBuf.size();
        if (intervalCount < intervalBuf.size()) {
            intervalCount++;
        }
    }

    function computeStrokeRate() {
        if (intervalCount == 0) { return 0.0; }
        var sum = 0;
        for (var i = 0; i < intervalCount; i++) {
            sum += intervalBuf[i];
        }
        var avgInterval = sum.toFloat() / intervalCount; // ms
        if (avgInterval <= 0) { return 0.0; }
        return 60000.0 / avgInterval; // convert to strokes per minute
    }
}
