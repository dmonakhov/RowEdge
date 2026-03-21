using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.System;
using Toybox.Timer;
using Toybox.Activity;

class RowingView extends WatchUi.View {

    enum {
        STATE_IDLE,
        STATE_CALIBRATING,
        STATE_RECORDING,
        STATE_PAUSED
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

    // Split smoothing
    var speedBuf = new [5];
    var speedBufIdx = 0;
    var speedBufCount = 0;

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
        for (var i = 0; i < speedBuf.size(); i++) {
            speedBuf[i] = 0.0;
        }
    }

    function onShow() {
        setControlBar(null);
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

    function onPosition(info as Position.Info) as Void {
        if (info.speed != null) {
            speed = info.speed;
            addSpeedSample(speed);
        }
    }

    function addSpeedSample(spd) {
        speedBuf[speedBufIdx] = spd;
        speedBufIdx = (speedBufIdx + 1) % speedBuf.size();
        if (speedBufCount < speedBuf.size()) { speedBufCount++; }
    }

    function getSmoothedSpeed() {
        if (speedBufCount == 0) { return 0.0; }
        var sum = 0.0;
        for (var i = 0; i < speedBufCount; i++) { sum += speedBuf[i]; }
        return sum / speedBufCount;
    }

    function onTimer() as Void {
        if (state == STATE_CALIBRATING) {
            var app = Application.getApp();
            if (app.strokeDetector.isCalibrationDone()) {
                app.rowingSession.start();
                state = STATE_RECORDING;
            }
        } else if (state == STATE_RECORDING || state == STATE_PAUSED) {
            updateMetrics();
        }
        WatchUi.requestUpdate();
    }

    function updateMetrics() {
        var app = Application.getApp();
        var detector = app.strokeDetector;
        var session = app.rowingSession;

        detector.refreshStrokeRate();
        strokeRate = detector.strokeRate;
        strokeCount = detector.strokeCount;

        var actInfo = Activity.getActivityInfo();
        if (actInfo != null) {
            if (actInfo.elapsedDistance != null) { distance = actInfo.elapsedDistance; }
            if (actInfo.timerTime != null) { elapsedTime = actInfo.timerTime / 1000; }
            if (actInfo.currentHeartRate != null) { heartRate = actInfo.currentHeartRate; }
        }

        var smoothSpeed = getSmoothedSpeed();
        splitTime = smoothSpeed > 0.3 ? 500.0 / smoothSpeed : 0.0;

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
        speedBufIdx = 0; speedBufCount = 0;
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
            var c = cells[i];
            // Right edge (vertical divider) if not full width
            if (c[0] + c[2] < w) {
                dc.drawLine(c[0] + c[2], c[1], c[0] + c[2], c[1] + c[3]);
            }
            // Bottom edge (horizontal divider) if not at screen bottom
            if (c[1] + c[3] < h) {
                dc.drawLine(c[0], c[1] + c[3], c[0] + c[2], c[1] + c[3]);
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
            var c = cells[i];
            var fid = visible[i];
            var vf = pickFont(c[2], c[3], w, h);
            if (fid == FieldConfig.F_DISTANCE) {
                drawDistanceCell(dc, c[0], c[1], c[2], c[3], lf, vf);
            } else {
                var label = FieldConfig.getLabel(fid);
                var value = getFieldValue(fid);
                drawCell(dc, c[0], c[1], c[2], c[3], label, value, lf, vf);
            }
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
                if (elapsedTime > 0 && distance > 0) {
                    return formatSplit(500.0 * elapsedTime / distance);
                }
                return "--:--";
            case FieldConfig.F_CALORIES:
                return "--";
            case FieldConfig.F_ACCEL_AVG:
                return lastLinMagMean.format("%.0f");
            case FieldConfig.F_ACCEL_MAX:
                return lastLinMagMax.format("%.0f");
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

    // Distance cell: number + stacked "k" over "m" suffix when >= 3km
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
