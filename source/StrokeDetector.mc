using Toybox.Sensor;
using Toybox.Math;
using Toybox.System;
using Toybox.Application;

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
    var emaValue = 0.0;
    var prevEma = 0.0;
    var wasNegative = false;
    var running = false;

    // Tuning: adjustable at runtime via menu
    var catchThreshold = -80.0; // milliG, minimum dip to count as stroke

    // Fixed constants
    const EMA_ALPHA = 0.15;
    const MIN_STROKE_INTERVAL = 1200; // ms, max ~50 spm
    const MAX_STROKE_INTERVAL = 6000; // ms, min ~10 spm

    function initialize() {
        for (var i = 0; i < intervalBuf.size(); i++) {
            intervalBuf[i] = 0;
        }
        // Load persisted threshold
        var saved = Application.Storage.getValue("catchThreshold");
        if (saved != null) {
            catchThreshold = saved.toFloat();
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

        var yData = accelData.y;
        if (yData == null) { return; }

        var now = System.getTimer();

        for (var i = 0; i < yData.size(); i++) {
            var sample = yData[i].toFloat();

            // Exponential moving average
            emaValue = EMA_ALPHA * sample + (1.0 - EMA_ALPHA) * emaValue;

            // Detect negative-to-positive crossing after dip below threshold
            var isNegative = (emaValue < catchThreshold);

            if (wasNegative && !isNegative) {
                var interval = now - lastStrokeTime;

                if (lastStrokeTime > 0 &&
                    interval >= MIN_STROKE_INTERVAL &&
                    interval <= MAX_STROKE_INTERVAL) {
                    strokeCount++;
                    recordInterval(interval);
                    strokeRate = computeStrokeRate();
                    lastStrokeTime = now;
                } else if (lastStrokeTime == 0 ||
                           interval > MAX_STROKE_INTERVAL) {
                    strokeCount++;
                    lastStrokeTime = now;
                }
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
        var avgInterval = sum.toFloat() / intervalCount;
        if (avgInterval <= 0) { return 0.0; }
        return 60000.0 / avgInterval;
    }
}
