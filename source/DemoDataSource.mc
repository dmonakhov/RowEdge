using Toybox.Math;

// Realistic data simulation for demo mode.
// Replays recorded IMU stroke patterns through the real StrokeDetector
// pipeline, computes GPS position on Dorney Lake, simulates HR.
//
// TODO: Replace IMU samples with on-water recording data once available.

class DemoDataSource {

    // Dorney Lake (Eton Dorney, 2012 Olympics) -- straight 2000m course
    const START_LAT = 51.4998;
    const START_LON = -0.6768;
    const FINISH_LAT = 51.4888;
    const FINISH_LON = -0.6526;
    const COURSE_LEN = 2000.0;

    // Simulation parameters
    const TARGET_SPLIT = 110.0;   // 1:50 /500m
    const SPEED = 4.545;          // 500/110 m/s
    const BASE_HR = 130;
    const HR_AMP = 5;
    const SPM_TARGET = 20;        // strokes per minute

    // State
    var elapsed = 0;          // seconds since start
    var totalDistance = 0.0;  // meters, never resets
    var lat = 0.0;
    var lon = 0.0;
    var hr = 130;

    // IMU replay: stroke pattern index, sample position within pattern
    var patternIdx = 0;
    var samplePos = 0;

    // Synthetic stroke patterns (25Hz, 78 samples = 3.12s at ~19.2 SPM)
    // Generated from real on-water activity 2026-03-23-08-21-04.fit statistics:
    //   SPM=19.2, lin_mag_max P50=438, drive~0.7s, recovery~2.4s
    // Stroke shape: catch dip -> bell-shaped drive (peak~400mG, FR~0.6)
    //               -> release -> recovery glide with body-mass oscillation
    // EMA peak ~270 mG, crosses threshold=200 reliably.
    // TODO: Replace with real 25Hz on-water recording once available.
    var patternA = [
        -99, -166, -238, -278, -260, -196, -123, -71, 192, 241,
        291, 338, 378, 406, 419, 396, 377, 346, 305, 258,
        211, 165, 124, 90, 62, 42, 50, 22, -5, -32,
        -50, -48, -46, -45, -44, -43, -43, -44, -45, -46,
        -48, -50, -53, -56, -60, -63, -67, -70, -74, -77,
        -79, -82, -83, -84, -85, -84, -83, -82, -79, -77,
        -74, -70, -67, -63, -60, -56, -53, -50, -48, -46,
        -45, -44, -43, -43, -44, -45, -46, -48
    ];

    // Pattern B: same physics, +/-10% random variation
    var patternB = [
        -109, -175, -230, -293, -271, -180, -125, -66, 182, 247,
        303, 353, 360, 445, 390, 368, 377, 356, 337, 238,
        227, 161, 112, 88, 61, 47, 54, 24, -5, -39,
        -54, -49, -39, -44, -52, -48, -41, -44, -46, -37,
        -41, -51, -51, -53, -60, -66, -73, -78, -72, -76,
        -76, -75, -91, -92, -88, -86, -72, -85, -86, -87,
        -79, -74, -63, -68, -62, -48, -55, -55, -51, -45,
        -54, -34, -49, -33, -50, -38, -52, -46
    ];

    function initialize() {
        lat = START_LAT;
        lon = START_LON;
    }

    // Called every 1 second from RowingView.onTimer when demo mode is active.
    // Feeds IMU data into StrokeDetector and returns simulation state.
    function tick(detector) {
        elapsed++;

        // Distance and GPS position
        totalDistance += SPEED;
        var courseDist = totalDistance;
        // Wrap GPS position every 2000m (teleport to start)
        while (courseDist >= COURSE_LEN) {
            courseDist -= COURSE_LEN;
        }
        var frac = courseDist / COURSE_LEN;
        lat = START_LAT + frac * (FINISH_LAT - START_LAT);
        lon = START_LON + frac * (FINISH_LON - START_LON);

        // Heart rate: slow oscillation with noise
        var sinVal = Math.sin(elapsed * 0.05);
        var noise = (Math.rand() % 5) - 2;  // -2 to +2
        hr = BASE_HR + (HR_AMP * sinVal).toNumber() + noise;

        // Feed 25 IMU samples into StrokeDetector (1 second of data)
        feedImuSamples(detector, 25);
    }

    // Feed N samples from the current pattern into the detector.
    // Applies +/-5% random jitter to avoid exact repetition.
    function feedImuSamples(detector, count) {
        var pattern = (patternIdx % 2 == 0) ? patternA : patternB;
        var pLen = pattern.size();

        for (var i = 0; i < count; i++) {
            var raw = pattern[samplePos % pLen];

            // Add +/-5% jitter
            var jitter = (Math.rand() % 11) - 5;  // -5 to +5 percent
            var sample = raw + (raw * jitter / 100);

            // Feed as forward acceleration directly into the detector's
            // processing pipeline (same path as real sensor data)
            detector.processDemoSample(sample.toNumber());

            samplePos++;
            if (samplePos >= pLen) {
                samplePos = 0;
                patternIdx++;
            }
        }
    }

    function reset() {
        elapsed = 0;
        totalDistance = 0.0;
        lat = START_LAT;
        lon = START_LON;
        hr = BASE_HR;
        patternIdx = 0;
        samplePos = 0;
    }
}
