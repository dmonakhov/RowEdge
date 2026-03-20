using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Position;
using Toybox.System;
using Toybox.Timer;
using Toybox.Activity;

class RowingView extends WatchUi.View {

    enum {
        STATE_IDLE,
        STATE_RECORDING,
        STATE_STOPPED
    }

    var state = STATE_IDLE;

    // Displayed metrics
    var splitTime = 0.0;    // seconds per 500m
    var speed = 0.0;        // m/s
    var distance = 0.0;     // meters
    var elapsedTime = 0;    // seconds
    var strokeRate = 0.0;   // spm
    var strokeCount = 0;
    var dps = 0.0;          // distance per stroke
    var heartRate = 0;

    // Lap tracking
    var lapDistance = 0.0;
    var lapStrokes = 0;
    var lapStartDist = 0.0;
    var lapStartStrokes = 0;

    // Split smoothing
    var speedBuf = new [5];
    var speedBufIdx = 0;
    var speedBufCount = 0;

    // Update timer
    var updateTimer = null;

    function initialize() {
        View.initialize();
        for (var i = 0; i < speedBuf.size(); i++) {
            speedBuf[i] = 0.0;
        }
    }

    function onShow() {
        // Start position listener for GPS
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));

        // 1 Hz display update timer
        updateTimer = new Timer.Timer();
        updateTimer.start(method(:onTimer), 1000, true);
    }

    function onHide() {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        if (updateTimer != null) {
            updateTimer.stop();
            updateTimer = null;
        }
    }

    function setState(newState) {
        state = newState;
    }

    function onPosition(info as Position.Info) as Void {
        if (info.speed != null) {
            speed = info.speed;
            addSpeedSample(speed);
        }
    }

    function addSpeedSample(spd) {
        speedBuf[speedBufIdx] = spd;
        speedBufIdx = (speedBufIdx + 1) % speedBuf.size();
        if (speedBufCount < speedBuf.size()) {
            speedBufCount++;
        }
    }

    function getSmoothedSpeed() {
        if (speedBufCount == 0) { return 0.0; }
        var sum = 0.0;
        for (var i = 0; i < speedBufCount; i++) {
            sum += speedBuf[i];
        }
        return sum / speedBufCount;
    }

    function onTimer() as Void {
        if (state == STATE_RECORDING) {
            updateMetrics();
        }
        WatchUi.requestUpdate();
    }

    function updateMetrics() {
        var app = Application.getApp();
        var detector = app.strokeDetector;
        var session = app.rowingSession;

        // Stroke data from detector
        strokeRate = detector.strokeRate;
        strokeCount = detector.strokeCount;

        // GPS data from activity info
        var actInfo = Activity.getActivityInfo();
        if (actInfo != null) {
            if (actInfo.elapsedDistance != null) {
                distance = actInfo.elapsedDistance;
            }
            if (actInfo.timerTime != null) {
                elapsedTime = actInfo.timerTime / 1000; // ms -> s
            }
            if (actInfo.currentHeartRate != null) {
                heartRate = actInfo.currentHeartRate;
            }
        }

        // Split time from smoothed GPS speed
        var smoothSpeed = getSmoothedSpeed();
        if (smoothSpeed > 0.3) {
            splitTime = 500.0 / smoothSpeed;
        } else {
            splitTime = 0.0; // too slow / stopped
        }

        // Distance per stroke
        lapDistance = distance - lapStartDist;
        lapStrokes = strokeCount - lapStartStrokes;
        if (lapStrokes > 0) {
            dps = lapDistance / lapStrokes;
        }

        // Write custom fields to FIT
        if (session != null) {
            session.setStrokeRate(strokeRate.toNumber());
            session.setDPS(dps);
        }
    }

    function onLap() {
        lapStartDist = distance;
        lapStartStrokes = strokeCount;
    }

    function reset() {
        splitTime = 0.0;
        speed = 0.0;
        distance = 0.0;
        elapsedTime = 0;
        strokeRate = 0.0;
        strokeCount = 0;
        dps = 0.0;
        heartRate = 0;
        lapDistance = 0.0;
        lapStrokes = 0;
        lapStartDist = 0.0;
        lapStartStrokes = 0;
        speedBufIdx = 0;
        speedBufCount = 0;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        if (state == STATE_IDLE) {
            drawIdleScreen(dc, w, h);
        } else {
            drawDataScreen(dc, w, h);
        }
    }

    function drawIdleScreen(dc, w, h) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 3, Graphics.FONT_LARGE, "RowEdge",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, "Press START",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawDataScreen(dc, w, h) {
        // Layout: 3 rows x 2 columns
        // Row 1: Split | SPM
        // Row 2: Distance | Time
        // Row 3: DPS | HR

        var rowH = h / 3;
        var colW = w / 2;
        var lblColor = Graphics.COLOR_LT_GRAY;
        var valColor = Graphics.COLOR_WHITE;
        var numFont = Graphics.FONT_NUMBER_MILD;
        var lblFont = Graphics.FONT_XTINY;

        // Row dividers
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, rowH, w, rowH);
        dc.drawLine(0, rowH * 2, w, rowH * 2);
        dc.drawLine(colW, 0, colW, h);

        // -- Row 1 Left: Split time --
        drawCell(dc, 0, 0, colW, rowH,
                 "SPLIT/500m", formatSplit(splitTime),
                 lblFont, numFont, lblColor, valColor);

        // -- Row 1 Right: Stroke rate --
        var spmStr = strokeRate > 0 ? strokeRate.format("%.0f") : "--";
        drawCell(dc, colW, 0, colW, rowH,
                 "SPM", spmStr,
                 lblFont, numFont, lblColor, valColor);

        // -- Row 2 Left: Distance --
        drawCell(dc, 0, rowH, colW, rowH,
                 "DISTANCE", formatDistance(distance),
                 lblFont, numFont, lblColor, valColor);

        // -- Row 2 Right: Time --
        drawCell(dc, colW, rowH, colW, rowH,
                 "TIME", formatTime(elapsedTime),
                 lblFont, numFont, lblColor, valColor);

        // -- Row 3 Left: DPS --
        var dpsStr = dps > 0 ? dps.format("%.1f") + "m" : "--";
        drawCell(dc, 0, rowH * 2, colW, rowH,
                 "DPS", dpsStr,
                 lblFont, Graphics.FONT_MEDIUM, lblColor, valColor);

        // -- Row 3 Right: HR or Strokes --
        var hrStr;
        var hrLabel;
        if (heartRate > 0) {
            hrStr = heartRate.format("%d");
            hrLabel = "HR";
        } else {
            hrStr = strokeCount.format("%d");
            hrLabel = "STROKES";
        }
        drawCell(dc, colW, rowH * 2, colW, rowH,
                 hrLabel, hrStr,
                 lblFont, Graphics.FONT_MEDIUM, lblColor, valColor);

        // Recording indicator
        if (state == STATE_RECORDING) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(8, 8, 4);
        } else if (state == STATE_STOPPED) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 0, Graphics.FONT_XTINY, "STOPPED",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawCell(dc, x, y, w, h, label, value, lblFont, valFont, lblColor, valColor) {
        var cx = x + w / 2;
        var lblH = dc.getFontHeight(lblFont);

        dc.setColor(lblColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 2, lblFont, label, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(valColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y + lblH + 2, valFont, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Format speed (m/s) as split time (mm:ss per 500m)
    function formatSplit(seconds) {
        if (seconds <= 0 || seconds > 600) { return "--:--"; }
        var mins = (seconds / 60).toNumber();
        var secs = (seconds % 60).toNumber();
        return mins.format("%d") + ":" + secs.format("%02d");
    }

    function formatDistance(meters) {
        if (meters < 1000) {
            return meters.toNumber().format("%d") + "m";
        }
        return (meters / 1000.0).format("%.2f") + "k";
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
