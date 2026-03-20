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
    var currentPage = 0;
    const NUM_PAGES = 2;

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

    function setState(newState) {
        state = newState;
    }

    function nextPage() {
        currentPage = (currentPage + 1) % NUM_PAGES;
    }

    function prevPage() {
        currentPage = (currentPage - 1 + NUM_PAGES) % NUM_PAGES;
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

        strokeRate = detector.strokeRate;
        strokeCount = detector.strokeCount;

        var actInfo = Activity.getActivityInfo();
        if (actInfo != null) {
            if (actInfo.elapsedDistance != null) {
                distance = actInfo.elapsedDistance;
            }
            if (actInfo.timerTime != null) {
                elapsedTime = actInfo.timerTime / 1000;
            }
            if (actInfo.currentHeartRate != null) {
                heartRate = actInfo.currentHeartRate;
            }
        }

        var smoothSpeed = getSmoothedSpeed();
        if (smoothSpeed > 0.3) {
            splitTime = 500.0 / smoothSpeed;
        } else {
            splitTime = 0.0;
        }

        lapDistance = distance - lapStartDist;
        lapStrokes = strokeCount - lapStartStrokes;
        if (lapStrokes > 0) {
            dps = lapDistance / lapStrokes;
        }

        if (session != null) {
            session.setStrokeRate(strokeRate.toNumber());
            session.setDPS(dps);
            session.setAccelStats(detector.getAccelStats());
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

    //
    // Drawing
    //

    function onUpdate(dc) {
        // White background
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        if (state == STATE_IDLE) {
            drawIdleScreen(dc, w, h);
        } else if (currentPage == 0) {
            drawPage1(dc, w, h);
        } else {
            drawPage2(dc, w, h);
        }
    }

    function drawIdleScreen(dc, w, h) {
        // Minimal branding -- small text at top
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 2, Graphics.FONT_XTINY, "RowEdge",
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 20, Graphics.FONT_MEDIUM, "Press START",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Show current threshold setting
        var app = Application.getApp();
        var thr = app.strokeDetector.catchThreshold;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 20, Graphics.FONT_SMALL,
                    "Threshold: " + thr.format("%.0f"),
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 + 50, Graphics.FONT_XTINY,
                    "MENU to adjust",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Page 1: SPM | Split/500m | Distance | HR
    function drawPage1(dc, w, h) {
        var rowH = h / 4;
        drawStatusBar(dc, w);
        drawDividers(dc, w, h, 4);

        var spmStr = strokeRate > 0 ? strokeRate.format("%.0f") : "--";
        drawWideCell(dc, 0, 0, w, rowH,
                     "STROKE RATE (spm)", spmStr,
                     Graphics.FONT_XTINY, Graphics.FONT_NUMBER_MILD);

        drawWideCell(dc, 0, rowH, w, rowH,
                     "SPLIT / 500m", formatSplit(splitTime),
                     Graphics.FONT_XTINY, Graphics.FONT_NUMBER_MILD);

        drawWideCell(dc, 0, rowH * 2, w, rowH,
                     "DISTANCE", formatDistance(distance),
                     Graphics.FONT_XTINY, Graphics.FONT_NUMBER_MILD);

        var hrStr = heartRate > 0 ? heartRate.format("%d") : "--";
        drawWideCell(dc, 0, rowH * 3, w, rowH,
                     "HEART RATE (bpm)", hrStr,
                     Graphics.FONT_XTINY, Graphics.FONT_NUMBER_MILD);

        drawPageIndicator(dc, w, h, 0);
    }

    // Page 2: SPM | Distance | HR | Time of Day
    function drawPage2(dc, w, h) {
        var rowH = h / 4;
        drawStatusBar(dc, w);
        drawDividers(dc, w, h, 4);

        var spmStr = strokeRate > 0 ? strokeRate.format("%.0f") : "--";
        drawWideCell(dc, 0, 0, w, rowH,
                     "STROKE RATE (spm)", spmStr,
                     Graphics.FONT_XTINY, Graphics.FONT_NUMBER_MILD);

        drawWideCell(dc, 0, rowH, w, rowH,
                     "DISTANCE", formatDistance(distance),
                     Graphics.FONT_XTINY, Graphics.FONT_NUMBER_MILD);

        var hrStr = heartRate > 0 ? heartRate.format("%d") : "--";
        drawWideCell(dc, 0, rowH * 2, w, rowH,
                     "HEART RATE (bpm)", hrStr,
                     Graphics.FONT_XTINY, Graphics.FONT_NUMBER_MILD);

        var clockInfo = System.getClockTime();
        var timeStr = clockInfo.hour.format("%d") + ":" + clockInfo.min.format("%02d");
        drawWideCell(dc, 0, rowH * 3, w, rowH,
                     "TIME OF DAY", timeStr,
                     Graphics.FONT_XTINY, Graphics.FONT_NUMBER_MILD);

        drawPageIndicator(dc, w, h, 1);
    }

    // Small recording indicator + page dots
    function drawStatusBar(dc, w) {
        if (state == STATE_RECORDING) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(8, 8, 4);
        } else if (state == STATE_STOPPED) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 0, Graphics.FONT_XTINY, "STOPPED",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawDividers(dc, w, h, rows) {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        for (var i = 1; i < rows; i++) {
            var y = h * i / rows;
            dc.drawLine(0, y, w, y);
        }
    }

    function drawPageIndicator(dc, w, h, page) {
        // Two small dots at bottom-right
        var dotY = h - 6;
        var dotX = w - 16;
        for (var i = 0; i < NUM_PAGES; i++) {
            if (i == page) {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(dotX + i * 10, dotY, 3);
            } else {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(dotX + i * 10, dotY, 3);
            }
        }
    }

    // Full-width cell with label on left, value on right
    function drawWideCell(dc, x, y, w, h, label, value, lblFont, valFont) {
        var cy = y + h / 2;
        var lblH = dc.getFontHeight(lblFont);
        var valH = dc.getFontHeight(valFont);
        var totalH = lblH + valH;
        var topY = cy - totalH / 2;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, topY, lblFont, label, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, topY + lblH, valFont, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //
    // Formatters
    //

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
        return (meters / 1000.0).format("%.2f") + "km";
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
