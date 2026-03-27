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

    // Real on-water demo data: 520 samples (20.8s), 7 strokes
    // 5 stroke types sorted by intensity: gentle -> steady -> strong -> power
    //   -> steady -> light -> gentle (builds up and fades like a real piece)
    // From 2026-03-27-09-00-34.fit, representative strokes per cluster:
    //   gentle: peak=290, catch=-274 | light: peak=303, catch=-678
    //   steady: peak=339, catch=-617 | strong: peak=376, catch=-728
    //   power:  peak=433, catch=-751
    var strokeData = [
        -45, 5, -14, 28, -50, 16, -72, -13, -68, -28, -19, 0, -30, -27, -118,
        -69, -35, -38, -6, -16, -28, -27, -3, -17, -18, 133, 159, 134, 103, 66,
        72, 89, 29, 65, 76, 84, 82, 85, 84, 119, 48, -37, -78, -33, -71,
        -116, -162, -218, -274, -222, 115, 104, 139, 107, 80, 79, 97, 22, 58, 90,
        145, 176, 163, 156, 152, 152, 188, 229, 229, 229, 211, 244, 240, 290, 265,
        -35, 25, -5, -24, 2, -20, -56, -48, -45, 0, 55, 14, -20, -28, -34,
        -22, 31, -130, -61, -25, -41, -19, 21, -17, 55, 94, 109, 108, 91, 46,
        103, 82, 59, 54, 81, 89, 91, 35, 8, -34, 6, -30, -14, -185, -300,
        -307, -397, -617, -475, 53, 0, 24, 41, 28, 66, 117, 126, 140, 137, 150,
        211, 202, 241, 279, 213, 267, 300, 312, 326, 339, 288, 285, 214, 249, 4,
        35, 34, -13, 9, -102, -140, 63, 0, 29, -28, -57, -16, -13, -11, 40,
        -65, -76, -25, -35, 28, -52, -29, 27, 4, -6, 55, 68, 83, 78, 115,
        132, 110, 85, 70, 78, 24, 3, -4, -16, -53, -54, -146, -161, -256, -370,
        -433, -524, -513, -728, -295, 72, 64, 66, 75, 124, 184, 213, 259, 269, 249,
        283, 199, 170, 207, 228, 240, 301, 344, 313, 376, 362, 269, 68, 63, -109,
        19, 17, -36, -90, -99, -7, 11, 61, 5, 0, 27, 27, 19, -62, -32,
        -28, -46, -23, 4, -7, -12, -23, 11, -20, 118, 97, 125, 51, 60, 92,
        30, 45, 41, 30, 68, 6, -14, -15, -44, -51, -192, -180, -327, -546, -501,
        -751, -737, -385, -665, 207, 170, 239, 258, 279, 270, 286, 336, 42, 121, 304,
        432, 433, 298, 289, 284, 289, 251, 264, 243, 118, 74, -35, 25, -5, -24,
        2, -20, -56, -48, -45, 0, 55, 14, -20, -28, -34, -22, 31, -130, -61,
        -25, -41, -19, 21, -17, 55, 94, 109, 108, 91, 46, 103, 82, 59, 54,
        81, 89, 91, 35, 8, -34, 6, -30, -14, -185, -300, -307, -397, -617, -475,
        53, 0, 24, 41, 28, 66, 117, 126, 140, 137, 150, 211, 202, 241, 279,
        213, 267, 300, 312, 326, 339, 288, 285, 214, 249, 4, 86, 85, 64, 26,
        -13, -41, 29, -9, -37, -13, -27, -47, -23, 6, -36, -50, -14, -24, -14,
        -11, 7, 31, 22, 32, -86, 14, -30, 17, -29, -21, 8, -54, 120, 116,
        89, 88, 102, 21, 25, 9, 1, -28, -123, -211, -280, -361, -544, -516, -461,
        -462, -569, -524, -678, -581, -450, -522, -394, 142, 164, 205, 216, 192, 222, 231,
        262, 256, 253, 303, 284, 294, 260, 260, 210, 209, -45, 5, -14, 28, -50,
        16, -72, -13, -68, -28, -19, 0, -30, -27, -118, -69, -35, -38, -6, -16,
        -28, -27, -3, -17, -18, 133, 159, 134, 103, 66, 72, 89, 29, 65, 76,
        84, 82, 85, 84, 119, 48, -37, -78, -33, -71, -116, -162, -218, -274, -222,
        115, 104, 139, 107, 80, 79, 97, 22, 58, 90, 145, 176, 163, 156, 152,
        152, 188, 229, 229, 229, 211, 244, 240, 290, 265
    ];

    function initialize() {
        lat = START_LAT;
        lon = START_LON;
    }

    // Called every 1 second from RowingView.onTimer when demo mode is active.
    // Feeds IMU data into StrokeDetector and returns simulation state.
    function tick(detector) {
        elapsed++;

        // Distance with speed variation (matches RowingView speed oscillation)
        var spdVar = Math.sin(elapsed * 0.025) * 1.5;
        totalDistance += 3.5 + spdVar;
        var courseDist = totalDistance;
        // Wrap GPS position every 2000m (teleport to start)
        while (courseDist >= COURSE_LEN) {
            courseDist -= COURSE_LEN;
        }
        var frac = courseDist / COURSE_LEN;
        lat = START_LAT + frac * (FINISH_LAT - START_LAT);
        lon = START_LON + frac * (FINISH_LON - START_LON);

        // Heart rate: wide oscillation across zones (100-160 bpm)
        var sinVal = Math.sin(elapsed * 0.04);
        var noise = (Math.rand() % 5) - 2;
        hr = 130 + (30 * sinVal).toNumber() + noise;  // 100-160 bpm

        // Feed 25 IMU samples into StrokeDetector (1 second of data)
        feedImuSamples(detector, 25);

        // Simulate radar: approaching obstacle every ~50s cycle
        Application.getApp().radarMonitor.injectDemoTarget(elapsed);
    }

    // Feed N samples from continuous stroke data into the detector.
    // Loops through 20s of real on-water data with +/-3% jitter.
    function feedImuSamples(detector, count) {
        var pLen = strokeData.size();

        for (var i = 0; i < count; i++) {
            var raw = strokeData[samplePos % pLen];

            // Add +/-3% jitter to avoid exact repetition on loop
            var jitter = (Math.rand() % 7) - 3;
            var sample = raw + (raw * jitter / 100);

            detector.processDemoSample(sample.toNumber());

            samplePos++;
            if (samplePos >= pLen) {
                samplePos = 0;
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
