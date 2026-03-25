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
            speed = 4.545;  // constant for split display

            updateAvgSpeed();
            splitTime = avgSpeed > 0.3 ? 500.0 / avgSpeed : 0.0;

            lapDistance = distance - lapStartDist;
            lapStrokes = strokeCount - lapStartStrokes;
            if (lapStrokes > 0) { dps = lapDistance / lapStrokes; }
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
        // Draw home screen image (full screen, pre-sized for Edge 540)
        var img = WatchUi.loadResource(Rez.Drawables.HomeScreen);
        dc.drawBitmap(0, 0, img);

        // Overlay status info in blank area (y=46..123 in edge540.png)
        var app = Application.getApp();
        var thr = app.strokeDetector.catchThreshold;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 48, Graphics.FONT_MEDIUM,
                    "Thr: " + thr.format("%.0f") + " mG",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 78, Graphics.FONT_SMALL,
                    "START to row",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 100, Graphics.FONT_SMALL,
                    "MENU to configure",
                    Graphics.TEXT_JUSTIFY_CENTER);
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
        dc.drawText(w / 2, 4, Graphics.FONT_MEDIUM, "Activity Paused",
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
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + 5, Graphics.FONT_XTINY,
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
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, Graphics.FONT_XTINY,
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
        var visible = app.fieldConfig.getVisibleFields();
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
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - 4, cells[0][1] + 2, Graphics.FONT_SMALL,
                        "DEMO MODE", Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    // Compute cell rectangles [x, y, w, h] for N fields.
    // Wahoo-style zoom scheme (verified on WFCC1):
    //   z1: 1 field (full screen)
    //   z2: 2 fields (hero ~50% + 1 full-width row)
    //   z3: 3 fields (hero ~40% + 2 full-width rows ~30% each)
    //   z4: 5 fields (hero ~40% + 2x2 grid)
    //   z5: 7 fields (hero ~33% + 2x3 grid)
    //   z6: 9 fields (hero ~25% + 2x4 grid)
    //   z7: 11 fields (hero ~20% + 2x5 grid)
    function computeLayout(n, w, h) {
        var cells = new [n];
        if (n == 1) {
            cells[0] = [0, 0, w, h];
        } else if (n == 2) {
            var heroH = h / 2;
            cells[0] = [0, 0, w, heroH];
            cells[1] = [0, heroH, w, h - heroH];
        } else if (n == 3) {
            // Hero ~40% + 2 full-width rows ~30% each
            var heroH = h * 2 / 5;
            var rowH = (h - heroH) / 2;
            cells[0] = [0, 0, w, heroH];
            cells[1] = [0, heroH, w, rowH];
            cells[2] = [0, heroH + rowH, w, h - heroH - rowH];
        } else {
            // n >= 5: Hero + 2-column grid
            // Hero percentage: 5->40%, 7->33%, 9->25%, 11->20%
            var gridN = n - 1;
            var gridRows = (gridN + 1) / 2;
            // Total rows = 1 hero + gridRows. Hero gets ~2x a grid row height.
            var totalUnits = gridRows + 2; // hero = 2 units, each grid row = 1 unit
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
    }

    // Select font tier based on cell pixel dimensions.
    // A (80px): full-width hero, cell height >= 100px
    // B (55px): full-width non-hero, cell height 60-99px
    // C (38px): half-width, cell height >= 60px
    // D (26px): half-width, cell height < 60px
    function pickFont(cellW, cellH, screenW, screenH) {
        var fullWidth = (cellW > screenW * 3 / 4);

        if (fullWidth && cellH >= 100) {
            return fontA;  // 80px hero
        } else if (fullWidth) {
            return fontB;  // 55px full-width smaller rows
        } else if (cellH >= 60) {
            return fontC;  // 38px grid tall cells
        }
        return fontD;      // 26px grid small cells
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

        // Find Y range from display portion
        var yMin = 0;
        var yMax = 0;
        for (var i = dStart; i <= dEnd; i++) {
            var v = det.strokeCurve[i];
            if (v < yMin) { yMin = v; }
            if (v > yMax) { yMax = v; }
        }
        if (yMax < 10) { yMax = 10; }
        if (yMin > -10) { yMin = -10; }
        var yRange = yMax - yMin;

        // Zero line position
        var zeroY = gy + (yMax * gh / yRange).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(gx, zeroY, gx + gw, zeroY);

        // Draw filled areas + curve line
        var xScale = gw.toFloat() / (n - 1);
        var prevPx = gx;
        var prevPy = zeroY;

        for (var i = 0; i < n; i++) {
            var v = det.strokeCurve[dStart + i];
            var px = gx + (i * xScale).toNumber();
            var py = gy + ((yMax - v) * gh / yRange).toNumber();

            if (py < gy) { py = gy; }
            if (py > gy + gh) { py = gy + gh; }

            if (v > 0) {
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_GREEN);
                dc.fillRectangle(px, py, 2, zeroY - py);
            } else if (v < 0) {
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
                dc.fillRectangle(px, zeroY, 2, py - zeroY);
            }

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

            // FR: centered in positive area (overlaid on drive curve)
            var frY = gy + (yMax * gh / yRange * 4 / 10).toNumber();
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w / 2, frY, mFont,
                        (det.strokeForceRatio * 100).format("%.0f") + "%",
                        Graphics.TEXT_JUSTIFY_CENTER);

            // dV: right-aligned in negative area below zero line
            dc.drawText(x + w - 6, zeroY + 2, mFont,
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

        // Label: top-left corner
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 3, y + 1, lblFont, label, Graphics.TEXT_JUSTIFY_LEFT);

        // Value: centered in remaining space below label
        var valY = y + lblH + (h - lblH - valH) / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, valY, valFont, value, Graphics.TEXT_JUSTIFY_CENTER);
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
