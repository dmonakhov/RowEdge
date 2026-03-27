using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.System;
using Toybox.Timer;
using Toybox.Activity;
using Toybox.Attention;

class RowingView extends WatchUi.View {

    enum {
        STATE_IDLE,
        STATE_CALIBRATING,
        STATE_RECORDING,
        STATE_PAUSED,
        STATE_SUMMARY
    }

    var state = STATE_IDLE;

    // Displayed metrics (updated every second)
    var splitTime = 0.0;
    var speed = 0.0;
    var distance = 0.0;
    var elapsedTime = 0;
    var strokeRate = 0.0;
    var strokeCount = 0;
    var dps = 0.0;
    var heartRate = 0;

    // Sparkline history: one ring buffer per hero slot (hero + secondary hero)
    // Buffer is 70 samples but we only draw as many as fit the cell width
    const SPARK_SIZE = 70;
    var sparkBuf0 = new [70];    // hero field history
    var sparkBuf1 = new [70];    // secondary hero field history
    var sparkIdx = 0;
    var sparkCount = 0;
    var sparkFid0 = -1;          // field ID currently in hero slot
    var sparkFid1 = -1;          // field ID currently in secondary hero slot

    // Lap tracking
    var lapDistance = 0.0;
    var lapStrokes = 0;
    var lapStartDist = 0.0;
    var lapStartStrokes = 0;

    // Calibration screen data
    var lastLinMagMean = 0.0;
    var lastLinMagMax = 0.0;

    // Auto-pause state
    var autoPaused = false;
    var autoPauseCooldown = 0;     // seconds after resume before pause can re-trigger
    var autoPauseHoldoff = 0;      // seconds after pause before resume can trigger
    const AUTO_PAUSE_SPEED = 0.5;  // m/s
    const AUTO_RESUME_SPEED = 0.7; // m/s (hysteresis)
    const AUTO_PAUSE_COOLDOWN = 15;     // seconds grace after auto-resume
    const AUTO_PAUSE_COOLDOWN_MAX = 60; // seconds grace after activity start or manual resume
    const AUTO_PAUSE_HOLDOFF = 10;      // seconds minimum pause duration

    // Demo mode state
    var demoDistance = 0.0;
    var demoTime = 0;

    // Summary screen data (captured before reset)
    var summaryDist = 0.0;
    var summaryTime = 0;
    var summaryStrokes = 0;
    var summaryAvgSplit = 0.0;
    var summaryAvgHR = 0;
    var summaryTimer = null;

    // Speed from distance sliding window (proper physics: v = dx/dt)
    // Stores distance every second for last N seconds.
    // Speed = (dist[now] - dist[now-N]) / N, updated every second.
    const SPEED_WINDOW = 10; // seconds
    var distHistory = new [10];
    var distHistIdx = 0;
    var distHistCount = 0;
    var avgSpeed = 0.0;

    // Update timer
    var updateTimer = null;

    // Custom bitmap fonts (4 tiers, computed from Edge 540 246x322)
    // A=80px: hero z1-z6 (full-width, height >= 106px)
    // B=55px: hero z7, z3 rows (full-width, height 80-96px)
    // C=38px: grid z4-z5 (half-width, height 64-80px)
    // D=26px: grid z6-z7 (half-width, height 46-53px)
    var fontA = null;
    var fontB = null;
    var fontC = null;
    var fontD = null;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        if (self has :setControlBar) { setControlBar(null); }
        fontA = WatchUi.loadResource(Rez.Fonts.id_font_a);
        fontB = WatchUi.loadResource(Rez.Fonts.id_font_b);
        fontC = WatchUi.loadResource(Rez.Fonts.id_font_c);
        fontD = WatchUi.loadResource(Rez.Fonts.id_font_d);

        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        updateTimer = new Timer.Timer();
        updateTimer.start(method(:onTimer), 1000, true);
    }

    function onHide() {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        if (updateTimer != null) {
            updateTimer.stop();
            updateTimer = null;
        }
    }

    function setState(newState) { state = newState; }

    // Capture current metrics into summary fields, then switch to summary state
    function showSummary() {
        summaryDist = distance;
        summaryTime = elapsedTime;
        summaryStrokes = strokeCount;
        summaryAvgSplit = (distance > 0 && elapsedTime > 0) ?
                          500.0 * elapsedTime / distance : 0.0;
        var actInfo = Activity.getActivityInfo();
        summaryAvgHR = (actInfo != null && actInfo.averageHeartRate != null) ?
                       actInfo.averageHeartRate : 0;
        state = STATE_SUMMARY;
        summaryTimer = new Timer.Timer();
        summaryTimer.start(method(:onSummaryDismiss), 10000, false);
    }

    function onSummaryDismiss() as Void {
        dismissSummary();
    }

    function dismissSummary() {
        if (summaryTimer != null) {
            summaryTimer.stop();
            summaryTimer = null;
        }
        reset();
        state = STATE_IDLE;
        WatchUi.requestUpdate();
    }

    function onPosition(info as Position.Info) as Void {
        if (info.speed != null) {
            speed = info.speed;
        }
    }

    // Record current distance, compute speed from oldest sample in window.
    // Called every 1s from updateMetrics(). Updates avgSpeed every second.
    function updateAvgSpeed() {
        // Store current distance in circular buffer
        distHistory[distHistIdx] = distance;
        distHistIdx = (distHistIdx + 1) % SPEED_WINDOW;
        if (distHistCount < SPEED_WINDOW) { distHistCount++; }

        if (distHistCount < 2) {
            avgSpeed = 0.0;
            return;
        }

        // Oldest sample in the buffer
        var oldIdx = (distHistIdx - distHistCount + SPEED_WINDOW) % SPEED_WINDOW;
        var oldDist = distHistory[oldIdx];
        var dt = distHistCount - 1; // seconds between oldest and newest
        var delta = distance - oldDist;

        avgSpeed = (dt > 0) ? delta / dt : 0.0;
    }

    function onTimer() as Void {
        if (state == STATE_SUMMARY) {
            WatchUi.requestUpdate();
            return;
        }

        var app = Application.getApp();
        if (state == STATE_CALIBRATING) {
            if (app.strokeDetector.isCalibrationDone()) {
                app.rowingSession.start();
                state = STATE_RECORDING;
                autoPauseCooldown = AUTO_PAUSE_COOLDOWN_MAX;
            }
        } else if (state == STATE_RECORDING || state == STATE_PAUSED) {
            updateMetrics();
            checkAutoPause();
        }
        WatchUi.requestUpdate();
    }

    // Get current GPS speed by polling Position API directly.
    // Works regardless of FIT session state (unlike onPosition callback
    // which may stop in simulator when session is paused).
    function getGpsSpeed() {
        var posInfo = Position.getInfo();
        if (posInfo != null && posInfo.speed != null) {
            return posInfo.speed;
        }
        return 0.0;
    }

    function checkAutoPause() {
        var app = Application.getApp();
        if (!app.featureConfig.isEnabled(FeatureConfig.FEAT_AUTO_PAUSE) ||
            app.featureConfig.isEnabled(FeatureConfig.FEAT_DEMO_MODE)) {
            return;
        }

        if (state == STATE_RECORDING) {
            // Cooldown after resume: don't pause until distance buffer has real data
            if (autoPauseCooldown > 0) {
                autoPauseCooldown--;
                return;
            }
            if (avgSpeed < AUTO_PAUSE_SPEED) {
                app.strokeDetector.stop();
                app.rowingSession.stop();
                state = STATE_PAUSED;
                autoPaused = true;
                autoPauseHoldoff = AUTO_PAUSE_HOLDOFF;
                if (Attention has :playTone) {
                    Attention.playTone(Attention.TONE_LAP);
                }
            }
        } else if (state == STATE_PAUSED && autoPaused) {
            // Wait minimum pause duration before checking resume
            if (autoPauseHoldoff > 0) {
                autoPauseHoldoff--;
                return;
            }
            // Poll GPS directly for resume (FIT distance is frozen during pause)
            var gpsSpeed = getGpsSpeed();
            if (gpsSpeed > AUTO_RESUME_SPEED) {
                // Reset distance history so avgSpeed starts fresh after resume
                distHistIdx = 0;
                distHistCount = 0;
                autoPauseCooldown = AUTO_PAUSE_COOLDOWN;
                app.rowingSession.resume();
                app.strokeDetector.start();
                state = STATE_RECORDING;
                autoPaused = false;
                if (Attention has :playTone) {
                    Attention.playTone(Attention.TONE_LAP);
                }
            }
        }
    }

    function updateMetrics() {
        var app = Application.getApp();
        var detector = app.strokeDetector;
        var session = app.rowingSession;
        var isDemo = app.featureConfig.isEnabled(FeatureConfig.FEAT_DEMO_MODE);

        if (isDemo) {
            applyDemoData();
            return;
        }

        detector.refreshStrokeRate();
        strokeRate = detector.strokeRate;
        strokeCount = detector.strokeCount;

        var actInfo = Activity.getActivityInfo();
        if (actInfo != null) {
            if (actInfo.elapsedDistance != null) { distance = actInfo.elapsedDistance; }
            if (actInfo.timerTime != null) { elapsedTime = actInfo.timerTime / 1000; }
            if (actInfo.currentHeartRate != null) { heartRate = actInfo.currentHeartRate; }
        }

        // Only update distance-based speed while recording (FIT distance freezes during pause)
        if (state == STATE_RECORDING) {
            updateAvgSpeed();
        }
        splitTime = avgSpeed > 0.3 ? 500.0 / avgSpeed : 0.0;

        lapDistance = distance - lapStartDist;
        lapStrokes = strokeCount - lapStartStrokes;
        if (lapStrokes > 0) { dps = lapDistance / lapStrokes; }

        if (session != null) {
            var stats = detector.getAccelStats();
            session.setStrokeRate(strokeRate.toNumber());
            session.setDPS(dps);
            session.setAccelStats(stats);
            lastLinMagMax = stats[4];
            lastLinMagMean = stats[5];
            // High-frequency accel recording (25 samples/sec packed)
            if (app.featureConfig.isEnabled(FeatureConfig.FEAT_HFREQ_ACCEL)) {
                session.setHfreqData(detector.getHfreqPacked());
            }
            // Rowing metrics log
            if (app.featureConfig.isEnabled(FeatureConfig.FEAT_ROWING_LOG)) {
                session.setRowingMetrics(detector, lastLinMagMean, lastLinMagMax);
            }
            // Radar raw log
            if (app.featureConfig.isEnabled(FeatureConfig.FEAT_RADAR_LOG)) {
                session.setRadarData(app.radarMonitor, app.radarMonitor.bikeRadar);
            }
        }

        // Record sparkline history
        if (app.featureConfig.isEnabled(FeatureConfig.FEAT_SPARKLINES)) {
            var tall = (System.getDeviceSettings().screenHeight > 400);
            var visible = app.fieldConfig.getVisibleFieldsTall(tall);
            recordSparkline(visible);
        }
    }

    function applyDemoData() {
        var app = Application.getApp();
        var detector = app.strokeDetector;
        var demo = app.demoData;

        if (state == STATE_RECORDING) {
            // Feed realistic IMU data through the real stroke detection pipeline
            demo.tick(detector);

            // Read back metrics computed by the real pipeline
            detector.refreshStrokeRate();
            strokeRate = detector.strokeRate;
            strokeCount = detector.strokeCount;

            // Flush accel stats (same as real path) to update display vars
            var stats = detector.getAccelStats();
            lastLinMagMax = stats[4];
            lastLinMagMean = stats[5];

            // Use demo-computed GPS/distance/HR
            distance = demo.totalDistance;
            elapsedTime = demo.elapsed;
            heartRate = demo.hr;
            // Speed varies with noise across split zones for sparkline demo
            var spdVar = Math.sin(demo.elapsed * 0.025) * 1.5;
            var spdNoise = ((Math.rand() % 41) - 20) / 100.0;  // +/-0.2 m/s
            speed = 3.5 + spdVar + spdNoise;

            updateAvgSpeed();
            splitTime = avgSpeed > 0.3 ? 500.0 / avgSpeed : 0.0;

            lapDistance = distance - lapStartDist;
            lapStrokes = strokeCount - lapStartStrokes;
            if (lapStrokes > 0) { dps = lapDistance / lapStrokes; }

            // Record sparkline in demo mode too
            if (app.featureConfig.isEnabled(FeatureConfig.FEAT_SPARKLINES)) {
                var tall = (System.getDeviceSettings().screenHeight > 400);
                var visible = app.fieldConfig.getVisibleFieldsTall(tall);
                recordSparkline(visible);
            }
        }
    }

    function onLap() {
        lapStartDist = distance;
        lapStartStrokes = strokeCount;
    }

    function reset() {
        splitTime = 0.0; speed = 0.0; distance = 0.0;
        elapsedTime = 0; strokeRate = 0.0; strokeCount = 0;
        dps = 0.0; heartRate = 0;
        lapDistance = 0.0; lapStrokes = 0;
        lapStartDist = 0.0; lapStartStrokes = 0;
        distHistIdx = 0; distHistCount = 0; avgSpeed = 0.0;
        for (var i = 0; i < SPEED_WINDOW; i++) { distHistory[i] = 0.0; }
        autoPaused = false; autoPauseCooldown = 0; autoPauseHoldoff = 0;
        demoDistance = 0.0; demoTime = 0;
        sparkIdx = 0; sparkCount = 0; sparkFid0 = -1; sparkFid1 = -1;
        clearSparkBuf(sparkBuf0); clearSparkBuf(sparkBuf1);
        Application.getApp().demoData.reset();
    }

    //
    // Drawing
    //

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        if (state == STATE_IDLE) {
            drawIdleScreen(dc, w, h);
        } else if (state == STATE_CALIBRATING) {
            drawCalibratingScreen(dc, w, h);
        } else if (state == STATE_PAUSED) {
            drawPausedScreen(dc, w, h);
        } else if (state == STATE_SUMMARY) {
            drawSummaryScreen(dc, w, h);
        } else {
            drawDataScreen(dc, w, h);
        }
    }

    function drawIdleScreen(dc, w, h) {
        var img = WatchUi.loadResource(Rez.Drawables.HomeScreen);
        dc.drawBitmap(0, 0, img);

        // Text overlay in empty blue zone at top of screen
        var tall = (h > 400);
        var hintFont = tall ? Graphics.FONT_LARGE : Graphics.FONT_MEDIUM;
        var hintH = dc.getFontHeight(hintFont);

        var emptyH = tall ? (h * 48 / 100) : (h * 34 / 100);
        var blockH = hintH * 2 + 6;
        var textY = (emptyH - blockH) / 2;
        if (textY < 5) { textY = 5; }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, textY, hintFont,
                    "START to row",
                    Graphics.TEXT_JUSTIFY_CENTER);
        textY += hintH + 4;
        var configHint = tall ? "Tap to configure" : "MENU to configure";
        dc.drawText(w / 2, textY, hintFont,
                    configHint,
                    Graphics.TEXT_JUSTIFY_CENTER);
	dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_TRANSPARENT);
        textY += hintH + 4;
        dc.drawText(w / 2, textY, hintFont,
                    "Lap to exit",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Version in bottom-left corner
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(3, h - 18, Graphics.FONT_XTINY,
                    APP_VERSION, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function drawCalibratingScreen(dc, w, h) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 30, Graphics.FONT_MEDIUM, "Calibrating...",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 10, Graphics.FONT_SMALL, "Hold still",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawPausedScreen(dc, w, h) {
        var rowH = h / 6;
        var valX = w - 8;

        // Header
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
	dc.drawRectangle(0, 0, w, h);
	dc.drawRectangle(1, 1, w - 2, h - 2);
	dc.drawRectangle(2, 2, w - 4, h - 4);
	dc.drawRectangle(3, 3, w - 6, h - 6);

	dc.setColor(Graphics.COLOR_DK_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 15, Graphics.FONT_MEDIUM, "Activity Paused",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Data rows using fontC for values
        var y = rowH;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_SMALL, "Distance", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valX, y, fontC, formatDistance(distance), Graphics.TEXT_JUSTIFY_RIGHT);

        y += rowH;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_SMALL, "Total Time", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valX, y, fontC, formatTime(elapsedTime), Graphics.TEXT_JUSTIFY_RIGHT);

        y += rowH;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_SMALL, "AVG Split", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var avgSplit = (elapsedTime > 0 && distance > 0) ?
                       formatSplit(500.0 * elapsedTime / distance) : "--:--";
        dc.drawText(valX, y, fontC, avgSplit, Graphics.TEXT_JUSTIFY_RIGHT);

        y += rowH;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_SMALL, "Time of Day", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var ci = System.getClockTime();
        dc.drawText(valX, y, fontC,
                    ci.hour.format("%d") + ":" + ci.min.format("%02d"),
                    Graphics.TEXT_JUSTIFY_RIGHT);

        // Bottom hint
        y += rowH;
        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + 5, Graphics.FONT_MEDIUM,
                    "START: resume  BACK: stop",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawSummaryScreen(dc, w, h) {
        var rowH = h / 7;

        // Header
        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 4, Graphics.FONT_MEDIUM, "Activity Saved",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Data rows: label left, value right, both using fontC
        var y = rowH;
        var valX = w - 8;

        drawSummaryRow(dc, y, valX, "Distance", formatDistance(summaryDist));
        y += rowH;
        drawSummaryRow(dc, y, valX, "Total Time", formatTime(summaryTime));
        y += rowH;
        drawSummaryRow(dc, y, valX, "Strokes", summaryStrokes.format("%d"));
        y += rowH;
        drawSummaryRow(dc, y, valX, "AVG Split", formatSplit(summaryAvgSplit));
        y += rowH;
        drawSummaryRow(dc, y, valX, "AVG HR", summaryAvgHR > 0 ? summaryAvgHR.format("%d") : "--");

        // Bottom hint
        y += rowH;
        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, Graphics.FONT_SMALL,
                    "Press any button to dismiss",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawSummaryRow(dc, y, valX, label, value) {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(8, y, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valX, y, fontC, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // Dynamic data screen: renders visible fields from FieldConfig
    function drawDataScreen(dc, w, h) {
        drawStatusBar(dc, w);

        var app = Application.getApp();
        var tall = (h > 400);
        var visible = app.fieldConfig.getVisibleFieldsTall(tall);
        var n = visible.size();
        if (n == 0) { return; }

        // Layout: Garmin-style grid based on field count
        // Use grid layout tables matching standard Garmin patterns
        var cells = computeLayout(n, w, h);

        // Draw dividers
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < cells.size(); i++) {
            var cx = cells[i][0];
            var cy = cells[i][1];
            var cw = cells[i][2];
            var ch = cells[i][3];
            if (cx + cw < w) {
                dc.drawLine(cx + cw, cy, cx + cw, cy + ch);
            }
            if (cy + ch < h) {
                dc.drawLine(cx, cy + ch, cx + cw, cy + ch);
            }
        }

        // Label font by zoom level
        var z = app.fieldConfig.zoomLevel;
        var lf;
        if (z <= 3) {
            lf = Graphics.FONT_MEDIUM;
        } else if (z <= 6) {
            lf = Graphics.FONT_SMALL;
        } else {
            lf = Graphics.FONT_TINY;
        }
        // Draw sparklines FIRST (behind text) so metrics render on top
        if (app.featureConfig.isEnabled(FeatureConfig.FEAT_SPARKLINES) && sparkCount > 3) {
            var c0w = cells[0][2];
            var c0h = cells[0][3];
            if (c0w > w * 3 / 4 && c0h >= 60 && visible[0] != FieldConfig.F_ACCEL_CURVE) {
                drawSparkline(dc, cells[0][0], cells[0][1], c0w, c0h, visible[0], sparkBuf0);
            }
            if (n >= 2 && h > 400) {
                var c1w = cells[1][2];
                var c1h = cells[1][3];
                if (c1w > w * 3 / 4 && c1h >= 60 && visible[1] != FieldConfig.F_ACCEL_CURVE) {
                    drawSparkline(dc, cells[1][0], cells[1][1], c1w, c1h, visible[1], sparkBuf1);
                }
            }
        }

        for (var i = 0; i < n && i < cells.size(); i++) {
            var cx = cells[i][0];
            var cy = cells[i][1];
            var cw = cells[i][2];
            var ch = cells[i][3];
            var fid = visible[i];
            var vf = pickFont(cw, ch, w, h);
            if (fid == FieldConfig.F_ACCEL_CURVE) {
                drawAccelCurve(dc, cx, cy, cw, ch, lf);
            } else if (fid == FieldConfig.F_DISTANCE) {
                drawDistanceCell(dc, cx, cy, cw, ch, lf, vf);
            } else if (fid == FieldConfig.F_RADAR) {
                var rm = app.radarMonitor;
                var label = (rm.targetCount > 0) ?
                    "RADAR " + rm.getClassLabel() : "RADAR";
                var value = getFieldValue(fid);
                // Color background by threat level + classification
                // ONC (oncoming) = red tones, STA (stationary) = yellow tones
                if (rm.threatLevel >= 3) {
                    dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
                    dc.fillRectangle(cx, cy, cw, ch);
                } else if (rm.threatLevel >= 2) {
                    var warnColor = (rm.closestClass == RadarMonitor.CLS_ONCOMING) ?
                        Graphics.COLOR_RED : Graphics.COLOR_ORANGE;
                    dc.setColor(warnColor, warnColor);
                    dc.fillRectangle(cx, cy, cw, ch);
                } else if (rm.threatLevel >= 1) {
                    var cautColor = (rm.closestClass == RadarMonitor.CLS_ONCOMING) ?
                        Graphics.COLOR_ORANGE : Graphics.COLOR_GREEN;
                    dc.setColor(cautColor, cautColor);
                    dc.fillRectangle(cx, cy, cw, ch);
                }
                drawCell(dc, cx, cy, cw, ch, label, value, lf, vf);
            } else {
                var label = FieldConfig.getLabel(fid);
                var value = getFieldValue(fid);
                drawCell(dc, cx, cy, cw, ch, label, value, lf, vf);
            }
        }

        // Demo mode: yellow border + red label
        if (app.featureConfig.isEnabled(FeatureConfig.FEAT_DEMO_MODE)) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(0, 0, w, h);
            dc.drawRectangle(1, 1, w - 2, h - 2);
            //dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - 4, cells[0][1] + 2, Graphics.FONT_SMALL,
                        "DEMO MODE", Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    // Compute cell rectangles [x, y, w, h] for N fields.
    //
    // Standard layout (Edge 540/840, height <= 400):
    //   z1: 1 field (full screen)
    //   z2: 2 fields (hero + 1 row)
    //   z3: 3 fields (hero + 2 full-width rows)
    //   z4+: hero + 2-column grid
    //
    // Tall layout (Edge 1040/1050, height > 400):
    //   z1: 1 field (hero only)
    //   z2: 2 fields (hero + secondary hero, both full-width)
    //   z3: 3 fields (hero + secondary hero + 1 full-width row)
    //   z4+: hero + secondary hero + 2-column grid
    function computeLayout(n, w, h) {
        var tall = (h > 400);
        if (tall && n >= 2) {
            return computeLayoutTall(n, w, h);
        }
        return computeLayoutStandard(n, w, h);
    }

    function computeLayoutStandard(n, w, h) {
        var cells = new [n];
        if (n == 1) {
            cells[0] = [0, 0, w, h];
        } else if (n == 2) {
            var heroH = h / 2;
            cells[0] = [0, 0, w, heroH];
            cells[1] = [0, heroH, w, h - heroH];
        } else if (n == 3) {
            var heroH = h * 2 / 5;
            var rowH = (h - heroH) / 2;
            cells[0] = [0, 0, w, heroH];
            cells[1] = [0, heroH, w, rowH];
            cells[2] = [0, heroH + rowH, w, h - heroH - rowH];
        } else {
            // n >= 5: Hero + 2-column grid
            var gridN = n - 1;
            var gridRows = (gridN + 1) / 2;
            var totalUnits = gridRows + 2;
            var unitH = h / totalUnits;
            var heroH = unitH * 2;
            var rowH = unitH;
            var cw = w / 2;

            cells[0] = [0, 0, w, heroH];
            for (var i = 1; i < n; i++) {
                var gi = i - 1;
                var r = gi / 2;
                var c = gi % 2;
                var y = heroH + r * rowH;
                cells[i] = [cw * c, y, cw, rowH];
            }
        }
        return cells;
    }

    // Tall screen layout: hero + secondary hero (equal height) + grid.
    // Uses unit-based sizing like standard layout but with two 2-unit heroes.
    // hero = 2 units, secondary = 2 units, each grid row = 1 unit.
    // This maintains grid W/H ratio similar to Edge 540 standard layout.
    function computeLayoutTall(n, w, h) {
        var cells = new [n];
        if (n == 1) {
            cells[0] = [0, 0, w, h];
            return cells;
        }

        if (n == 2) {
            // Two equal full-width heroes
            var heroH = h / 2;
            cells[0] = [0, 0, w, heroH];
            cells[1] = [0, heroH, w, h - heroH];
            return cells;
        }

        if (n == 3) {
            // hero=2, sec=2, row=1 -> 5 units
            var unitH = h / 5;
            var heroH = unitH * 2;
            var secH = unitH * 2;
            cells[0] = [0, 0, w, heroH];
            cells[1] = [0, heroH, w, secH];
            cells[2] = [0, heroH + secH, w, h - heroH - secH];
            return cells;
        }

        // n >= 5: Hero + secondary hero + 2-column grid
        // hero=2 units, sec=2 units, each grid row=1 unit
        var gridN = n - 2;
        var gridRows = (gridN + 1) / 2;
        var totalUnits = 2 + 2 + gridRows;
        var unitH = h / totalUnits;
        var heroH = unitH * 2;
        var secH = unitH * 2;
        var rowH = unitH;
        var cw = w / 2;

        cells[0] = [0, 0, w, heroH];
        cells[1] = [0, heroH, w, secH];
        for (var i = 2; i < n; i++) {
            var gi = i - 2;
            var r = gi / 2;
            var c = gi % 2;
            var y = heroH + secH + r * rowH;
            cells[i] = [cw * c, y, cw, rowH];
        }
        return cells;
    }

    // Get formatted value string for a field ID
    function getFieldValue(fieldId) {
        switch (fieldId) {
            case FieldConfig.F_SPLIT:
                return formatSplit(splitTime);
            case FieldConfig.F_SPM:
                return strokeRate > 0 ? strokeRate.format("%.0f") : "--";
            case FieldConfig.F_HR:
                return heartRate > 0 ? heartRate.format("%d") : "--";
            case FieldConfig.F_DISTANCE:
                return formatDistance(distance);
            case FieldConfig.F_TIME:
                return formatTime(elapsedTime);
            case FieldConfig.F_CLOCK:
                var ci = System.getClockTime();
                return ci.hour.format("%d") + ":" + ci.min.format("%02d");
            case FieldConfig.F_DPS:
                return dps > 0 ? dps.format("%.1f") + "m" : "--";
            case FieldConfig.F_STROKES:
                return strokeCount.format("%d");
            case FieldConfig.F_SPEED:
                return speed > 0 ? speed.format("%.1f") : "--";
            case FieldConfig.F_AVG_SPLIT:
                if (elapsedTime > 0) {
                    var d = distance > 0.01 ? distance : 0.01;
                    return formatSplit(500.0 * elapsedTime / d);
                }
                return "--:--";
            case FieldConfig.F_CALORIES:
                return "--";
            case FieldConfig.F_ACCEL_AVG:
                return lastLinMagMean.format("%.0f");
            case FieldConfig.F_ACCEL_MAX:
                return lastLinMagMax.format("%.0f");
            case FieldConfig.F_FORCE_RATIO:
                var det_fr = Application.getApp().strokeDetector;
                return det_fr.strokeForceRatio > 0 ?
                       det_fr.strokeForceRatio.format("%.2f") : "--";
            case FieldConfig.F_DELTA_V:
                var det_dv = Application.getApp().strokeDetector;
                return det_dv.strokeDeltaV > 0 ?
                       det_dv.strokeDeltaV.format("%.3f") : "--";
            case FieldConfig.F_DRIVE_RECOV:
                var det_dr = Application.getApp().strokeDetector;
                if (det_dr.strokeDriveTime > 0 && det_dr.strokeRecovTime > 0) {
                    var ratio = det_dr.strokeRecovTime / det_dr.strokeDriveTime;
                    return "1:" + ratio.format("%.1f");
                }
                return "--";
            case FieldConfig.F_DRIVE_TIME:
                var det_dt = Application.getApp().strokeDetector;
                return det_dt.strokeDriveTime > 0 ?
                       det_dt.strokeDriveTime.format("%.2f") : "--";
            case FieldConfig.F_CATCH_DUR:
                var det_cd = Application.getApp().strokeDetector;
                return det_cd.strokeCatchDur > 0 ?
                       det_cd.strokeCatchDur.format("%.2f") : "--";
            case FieldConfig.F_CATCH_SLOPE:
                var det_cs = Application.getApp().strokeDetector;
                return det_cs.strokeCatchSlope > 0 ?
                       det_cs.strokeCatchSlope.format("%.0f") : "--";
            case FieldConfig.F_PEAK_ACCEL:
                var det_pa = Application.getApp().strokeDetector;
                return det_pa.strokePeak > 0 ?
                       det_pa.strokePeak.format("%.0f") : "--";
            case FieldConfig.F_RADAR:
                var radar = Application.getApp().radarMonitor;
                if (radar.targetCount > 0) {
                    return radar.closestRange.format("%d") + "m";
                }
                return "--";
            default:
                return "?";
        }
    }

    // Recording indicator
    function drawStatusBar(dc, w) {
        if (state == STATE_RECORDING) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(8, 8, 4);
        } else if (state == STATE_PAUSED) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 0, Graphics.FONT_XTINY, "PAUSED",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Radar threat indicator: colored bar on right edge
        var radar = Application.getApp().radarMonitor;
        if (radar.threatLevel > 0) {
            var h = dc.getHeight();
            var barW = 6;
            var color;
            if (radar.threatLevel >= 3) {
                color = Graphics.COLOR_RED;
            } else if (radar.threatLevel >= 2) {
                color = Graphics.COLOR_ORANGE;
            } else {
                color = Graphics.COLOR_GREEN;
            }
            dc.setColor(color, color);
            dc.fillRectangle(w - barW, 0, barW, h);

            // Show distance + TTC at top-right
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var radarText = radar.closestRange.format("%d") + "m";
            if (radar.closestTTC < 30) {
                radarText += " " + radar.closestTTC.format("%.0f") + "s";
            }
            dc.drawText(w - barW - 2, 0, Graphics.FONT_XTINY,
                        radarText, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    // Select font tier based on cell pixel dimensions.
    // A (80px): full-width hero, cell height >= 100px
    // B (55px): full-width non-hero, cell height 60-99px
    // C (38px): half-width, cell height >= 60px
    // D (26px): half-width, cell height < 60px
    function pickFont(cellW, cellH, screenW, screenH) {
        var fullWidth = (cellW > screenW * 3 / 4);

        if (fullWidth && cellH >= 100 && fontA != null) {
            return fontA;  // 80px hero
        } else if (fullWidth && fontB != null) {
            return fontB;  // 55px full-width smaller rows
        } else if (cellH >= 60 && fontC != null) {
            return fontC;  // 38px grid tall cells
        }
        // Fallback to system font if custom fonts not loaded
        return (fontD != null) ? fontD : Graphics.FONT_SMALL;
    }

    // Acceleration curve: catch + drive + recovery tail, full width.
    // Metrics (FR, D:R, dV) drawn in the negative area below zero line.
    function drawAccelCurve(dc, x, y, w, h, lblFont) {
        var app = Application.getApp();
        var det = app.strokeDetector;
        var lblH = dc.getFontHeight(lblFont);

        // Label top-left
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 3, y + 1, lblFont, "ACCEL", Graphics.TEXT_JUSTIFY_LEFT);

        if (det.strokeCurve == null || det.strokeCurveLen < 5) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, y + h / 2 - 10, Graphics.FONT_SMALL,
                        "--", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Graph area: full width
        var gx = x + 4;
        var gy = y + lblH + 2;
        var gw = w - 8;
        var gh = h - lblH - 4;
        if (gh < 20) { return; }

        // Display range from detector
        var dStart = det.strokeDispStart;
        var dEnd = det.strokeDispEnd;
        var n = dEnd - dStart + 1;
        if (n < 3) { n = det.strokeCurveLen; dStart = 0; dEnd = n - 1; }

        // Asymmetric Y-scaling: 70% positive (drive), 30% negative (catch).
        // Deep catches are clipped and shown with orange fill at bottom.
        var yMax = 0;
        var yMinReal = 0;
        for (var i = dStart; i <= dEnd; i++) {
            var v = det.strokeCurve[i];
            if (v < yMinReal) { yMinReal = v; }
            if (v > yMax) { yMax = v; }
        }
        if (yMax < 10) { yMax = 10; }

        // Negative budget = 30/70 of positive range
        var yMin = -(yMax * 30 / 70);
        if (yMin > -10) { yMin = -10; }
        var clipped = (yMinReal < yMin);
        var yRange = yMax - yMin;

        // Zero line at 70% from top
        var zeroY = gy + (yMax * gh / yRange).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(gx, zeroY, gx + gw, zeroY);

        // Bottom clip boundary line (if clipping)
        var clipY = gy + gh;  // bottom of graph
        if (clipped) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(gx, clipY - 1, gx + gw, clipY - 1);
        }

        // Draw filled areas + curve line
        var xScale = gw.toFloat() / (n - 1);
        var prevPx = gx;
        var prevPy = zeroY;

        for (var i = 0; i < n; i++) {
            var v = det.strokeCurve[dStart + i];
            var px = gx + (i * xScale).toNumber();

            // Clamp value to display range
            var vDisp = v;
            if (vDisp < yMin) { vDisp = yMin; }

            var py = gy + ((yMax - vDisp) * gh / yRange).toNumber();
            if (py < gy) { py = gy; }
            if (py > gy + gh) { py = gy + gh; }

            if (v > 0) {
                // Drive: green fill
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_GREEN);
                dc.fillRectangle(px, py, 2, zeroY - py);
            } else if (v < yMin && clipped) {
                // Clipped catch: orange fill, width proportional to depth.
                // Last clipped sample uses minimal width to not cross the blue curve line.
                var nextV = (i < n - 1) ? det.strokeCurve[dStart + i + 1] : 0;
                var isLastClipped = (nextV >= yMin);
                if (isLastClipped) {
                    dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_ORANGE);
                    dc.fillRectangle(px, zeroY, 1, clipY - zeroY);
                } else {
                    var ratio = v.toFloat() / yMinReal.toFloat();
                    var maxW = xScale > 2 ? xScale.toNumber() : 2;
                    var barW = 2 + ((maxW - 2) * ratio).toNumber();
                    if (barW < 2) { barW = 2; }
                    dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_ORANGE);
                    dc.fillRectangle(px, zeroY, barW, clipY - zeroY);
                }
            } else if (v < 0) {
                // Normal catch: red fill
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
                dc.fillRectangle(px, zeroY, 2, py - zeroY);
            }

            // Curve line (clamped to visible range)
            if (i > 0) {
                dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(prevPx, prevPy, px, py);
            }
            prevPx = px;
            prevPy = py;
        }

        // Overlay metrics if enabled
        if (app.featureConfig.isEnabled(FeatureConfig.FEAT_CURVE_METRICS)) {
            // Pick font: fontC for z1-z5, fontD for z6-z7
            var z = app.fieldConfig.zoomLevel;
            var mFont = (z <= 5) ? fontC : fontD;

            // FR: static position at 25% from top of graph area
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, gy + gh / 4, mFont,
                        (det.strokeForceRatio * 100).format("%.0f") + "%",
                        Graphics.TEXT_JUSTIFY_CENTER);

            // dV: just below zero line, nudged up 20% of font height for z4/z5
            var mFontH = dc.getFontHeight(mFont);
            dc.drawText(x + w - 6, zeroY + 2 - mFontH / 5, mFont,
                        det.strokeDeltaV.format("%.2f"),
                        Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    function drawDistanceCell(dc, x, y, w, h, lblFont, valFont) {
        var cx = x + w / 2;
        var lblH = dc.getFontHeight(lblFont);
        var valH = dc.getFontHeight(valFont);

        // Label: top-left corner
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 3, y + 1, lblFont, "DISTANCE", Graphics.TEXT_JUSTIFY_LEFT);

        // Value positioning
        var valY = y + lblH + (h - lblH - valH) / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);

        if (distance < 3000) {
            // Under 3km: "1234M"
            var numStr = distance.toNumber().format("%d");
            var valStr = numStr + "m";
            dc.drawText(cx, valY, valFont, valStr, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            // >= 3km: number + stacked K/M
            var km = distance / 1000.0;
            var numStr;
            if (km < 10) {
                numStr = km.format("%.2f");
            } else {
                numStr = km.format("%.1f");
            }

            var numDim = dc.getTextDimensions(numStr, valFont);
            var numW = numDim[0];
            var unitFont = Graphics.FONT_SMALL;
            var unitH = dc.getFontHeight(unitFont);

            // Draw number slightly left of center
            var numX = cx - 6;
            dc.drawText(numX, valY, valFont, numStr, Graphics.TEXT_JUSTIFY_CENTER);

            // Draw stacked "k" over "m" to the right of the number
            var suffixX = numX + numW / 2 + 2;
            var suffixY = valY + (valH - unitH * 2) / 2;
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(suffixX, suffixY, unitFont, "k", Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(suffixX, suffixY + unitH, unitFont, "m", Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // Generic cell: label at top, value centered below
    function drawCell(dc, x, y, w, h, label, value, lblFont, valFont) {
        var cx = x + w / 2;
        var lblH = dc.getFontHeight(lblFont);
        var valH = dc.getFontHeight(valFont);
        var fullWidth = (w > dc.getWidth() * 3 / 4);

        // Label: top-left corner
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 3, y + 1, lblFont, label, Graphics.TEXT_JUSTIFY_LEFT);

        var remaining = h - lblH;
        var valY;
        var zl = Application.getApp().fieldConfig.zoomLevel;
        if (fullWidth && zl >= 6) {
            var offset = dc.getHeight() * 3 / 100;
            valY = y + lblH - offset;
        } else if (fullWidth) {
            valY = y + lblH + (remaining - valH) / 4;
        } else {
            valY = y + lblH + (remaining - valH) / 2;
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, valY, valFont, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Get numeric value for sparkline recording. Returns integer (0 = no data).
    function getSparkValue(fid) {
        switch (fid) {
            case FieldConfig.F_SPLIT:
                return (splitTime > 0 && splitTime < 600) ? splitTime.toNumber() : 0;
            case FieldConfig.F_SPM:
                return strokeRate > 0 ? strokeRate.toNumber() : 0;
            case FieldConfig.F_HR:
                return heartRate > 0 ? heartRate : 0;
            case FieldConfig.F_SPEED:
                return speed > 0 ? (speed * 100).toNumber() : 0;  // cm/s
            case FieldConfig.F_DPS:
                return dps > 0 ? (dps * 10).toNumber() : 0;  // decimeters
            case FieldConfig.F_FORCE_RATIO:
                var det_fr = Application.getApp().strokeDetector;
                return det_fr.strokeForceRatio > 0 ?
                       (det_fr.strokeForceRatio * 100).toNumber() : 0;
            case FieldConfig.F_DELTA_V:
                var det_dv = Application.getApp().strokeDetector;
                return det_dv.strokeDeltaV > 0 ?
                       (det_dv.strokeDeltaV * 100).toNumber() : 0;
            case FieldConfig.F_DRIVE_RECOV:
                var det_dr = Application.getApp().strokeDetector;
                if (det_dr.strokeDriveTime > 0 && det_dr.strokeRecovTime > 0) {
                    return (det_dr.strokeRecovTime / det_dr.strokeDriveTime * 10).toNumber();
                }
                return 0;
            case FieldConfig.F_PEAK_ACCEL:
                var det_pa = Application.getApp().strokeDetector;
                return det_pa.strokePeak > 0 ? det_pa.strokePeak.toNumber() : 0;
            default:
                return 0;
        }
    }

    // Get zone color for a sparkline bar based on field type and value
    function getSparkColor(fid, val) {
        if (val <= 0) { return Graphics.COLOR_LT_GRAY; }

        if (fid == FieldConfig.F_SPLIT) {
            // Split/500m: lower is better. val = seconds
            // [>240=gray, >180=blue, >150=green, >120=orange, <=120=red]
            if (val > 240) { return Graphics.COLOR_LT_GRAY; }
            if (val > 180) { return Graphics.COLOR_BLUE; }
            if (val > 150) { return Graphics.COLOR_DK_GREEN; }
            if (val > 120) { return Graphics.COLOR_ORANGE; }
            return Graphics.COLOR_RED;
        } else if (fid == FieldConfig.F_SPM) {
            // SPM: [<14=gray, <18=blue, <22=green, <26=orange, >=26=red]
            if (val < 14) { return Graphics.COLOR_LT_GRAY; }
            if (val < 18) { return Graphics.COLOR_BLUE; }
            if (val < 22) { return Graphics.COLOR_DK_GREEN; }
            if (val < 26) { return Graphics.COLOR_ORANGE; }
            return Graphics.COLOR_RED;
        } else if (fid == FieldConfig.F_HR) {
            // HR zones: [<100=gray, <120=blue, <140=green, <160=orange, >=160=red]
            if (val < 100) { return Graphics.COLOR_LT_GRAY; }
            if (val < 120) { return Graphics.COLOR_BLUE; }
            if (val < 140) { return Graphics.COLOR_DK_GREEN; }
            if (val < 160) { return Graphics.COLOR_ORANGE; }
            return Graphics.COLOR_RED;
        } else if (fid == FieldConfig.F_DELTA_V) {
            // DeltaV * 100: [<50=gray, <100=blue, <150=green, <200=orange, >=200=red]
            if (val < 50) { return Graphics.COLOR_LT_GRAY; }
            if (val < 100) { return Graphics.COLOR_BLUE; }
            if (val < 150) { return Graphics.COLOR_DK_GREEN; }
            if (val < 200) { return Graphics.COLOR_ORANGE; }
            return Graphics.COLOR_RED;
        } else if (fid == FieldConfig.F_FORCE_RATIO) {
            // FR * 100: higher is better [<35=red, <45=orange, <55=green, <65=blue, >=65=gray]
            if (val < 35) { return Graphics.COLOR_RED; }
            if (val < 45) { return Graphics.COLOR_ORANGE; }
            if (val < 55) { return Graphics.COLOR_DK_GREEN; }
            if (val < 65) { return Graphics.COLOR_BLUE; }
            return Graphics.COLOR_LT_GRAY;
        }
        // Default: single color
        return Graphics.COLOR_BLUE;
    }

    // Record current values into sparkline buffers
    function recordSparkline(visible) {
        if (visible.size() < 1) { return; }

        // Check if field IDs changed -- reset buffer on change
        var fid0 = visible[0];
        var fid1 = (visible.size() > 1) ? visible[1] : -1;
        if (fid0 != sparkFid0) { clearSparkBuf(sparkBuf0); sparkFid0 = fid0; }
        if (fid1 != sparkFid1) { clearSparkBuf(sparkBuf1); sparkFid1 = fid1; }

        // Record values
        sparkBuf0[sparkIdx] = getSparkValue(fid0);
        if (fid1 >= 0) {
            sparkBuf1[sparkIdx] = getSparkValue(fid1);
        }
        sparkIdx = (sparkIdx + 1) % SPARK_SIZE;
        if (sparkCount < SPARK_SIZE) { sparkCount++; }
    }

    function clearSparkBuf(buf) {
        for (var i = 0; i < SPARK_SIZE; i++) { buf[i] = 0; }
        sparkCount = 0;
        sparkIdx = 0;
    }

    // Draw sparkline bar chart at bottom of a cell.
    // Bar width = max(w/60, 2). Draw only the newest N bars that fit the width.
    function drawSparkline(dc, x, y, w, h, fid, buf) {
        if (sparkCount < 3) { return; }

        // Sparkline area: bottom 30% of cell
        var sparkH = h * 3 / 10;
        var sparkY = y + h - sparkH;

        // Bar width: target w/60 but at least 2px
        var barW = w / 60;
        if (barW < 2) { barW = 2; }

        // How many bars actually fit the cell width
        var nBars = w / barW;
        if (nBars > SPARK_SIZE) { nBars = SPARK_SIZE; }
        if (nBars > sparkCount) { nBars = sparkCount; }

        // Find min/max from the bars we'll draw
        var vMin = 999999;
        var vMax = 0;
        for (var i = 0; i < nBars; i++) {
            var bufIdx = (sparkIdx - nBars + i + SPARK_SIZE) % SPARK_SIZE;
            var v = buf[bufIdx];
            if (v > 0) {
                if (v < vMin) { vMin = v; }
                if (v > vMax) { vMax = v; }
            }
        }
        if (vMax <= vMin) { return; }
        var vRange = vMax - vMin;

        // Draw newest N bars, right-aligned (newest = rightmost)
        var startX = x + w - nBars * barW;
        for (var i = 0; i < nBars; i++) {
            var bufIdx = (sparkIdx - nBars + i + SPARK_SIZE) % SPARK_SIZE;
            var v = buf[bufIdx];
            if (v <= 0) { continue; }

            var barX = startX + i * barW;
            var barH = ((v - vMin) * (sparkH - 2) / vRange).toNumber();
            if (barH < 1) { barH = 1; }
            var barY = sparkY + sparkH - barH;

            dc.setColor(getSparkColor(fid, v), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(barX, barY, barW, sparkH - (barY - sparkY));
        }
    }

    //
    // Formatters
    //

    function formatSplit(seconds) {
        if (seconds <= 0 || seconds > 600) { return "--:--"; }
        var totalSecs = seconds.toNumber();
        var mins = totalSecs / 60;
        var secs = totalSecs % 60;
        return mins.format("%d") + ":" + secs.format("%02d");
    }

    // Format distance to max 5 chars: "999m", "2345m", "3.4k", "12.1k", "999k"
    function formatDistance(meters) {
        if (meters < 3000) {
            return meters.toNumber().format("%d") + "m";
        }
        var km = meters / 1000.0;
        if (km < 100) {
            return km.format("%.1f") + "k";
        }
        return km.format("%.0f") + "k";
    }

    function formatTime(seconds) {
        var hrs = seconds / 3600;
        var mins = (seconds % 3600) / 60;
        var secs = seconds % 60;
        if (hrs > 0) {
            return hrs.format("%d") + ":" + mins.format("%02d") + ":" + secs.format("%02d");
        }
        return mins.format("%d") + ":" + secs.format("%02d");
    }
}
