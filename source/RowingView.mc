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
        STATE_PAUSED
    }

    var state = STATE_IDLE;
    var currentPage = 0;
    const NUM_PAGES = 4; // page0=4C, page1=4C, page2=5C, page3=calibration

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

    // Calibration screen data (from last getAccelStats call)
    var lastLinMagMean = 0.0;
    var lastLinMagMax = 0.0;

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
        // Hide system title/control bar to get full screen
        setControlBar(null);
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
        if (state == STATE_RECORDING || state == STATE_PAUSED) {
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
            var stats = detector.getAccelStats();
            session.setStrokeRate(strokeRate.toNumber());
            session.setDPS(dps);
            session.setAccelStats(stats);
            // stats: [xm, ym, zm, linMagMin, linMagMax, linMagMean, ema]
            lastLinMagMax = stats[4];
            lastLinMagMean = stats[5];
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
            drawPage4C_1(dc, w, h);
        } else if (currentPage == 1) {
            drawPage4C_2(dc, w, h);
        } else if (currentPage == 2) {
            drawPage5C(dc, w, h);
        } else {
            drawPageCalibration(dc, w, h);
        }
    }

    function drawIdleScreen(dc, w, h) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 20, Graphics.FONT_MEDIUM, "Press START",
                    Graphics.TEXT_JUSTIFY_CENTER);

        var app = Application.getApp();
        var thr = app.strokeDetector.catchThreshold;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 20, Graphics.FONT_SMALL,
                    "Thr: " + thr.format("%.0f") + " mG",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2 + 50, Graphics.FONT_XTINY,
                    "MENU to adjust",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Labels always FONT_XTINY. Values scale by cell height.
    // 4-C: 2 tall rows (h*2/5) + 1 short row split (h/5) -> NUMBER_HOT tall, NUMBER_MEDIUM short
    // 5-C: 1 short + 1 tall (h*2/5) + 1 short + 1 short split -> NUMBER_HOT tall, NUMBER_MEDIUM short
    // Calibration: 3 equal rows -> NUMBER_HOT

    // Page 1 (4-C): SPM | Split/500m | Distance + HR
    function drawPage4C_1(dc, w, h) {
        var tallH = h * 2 / 5;
        var shortH = h / 5;
        var lf = Graphics.FONT_XTINY;
        var bigVf = Graphics.FONT_NUMBER_THAI_HOT;
        var smVf = Graphics.FONT_NUMBER_HOT;
        drawStatusBar(dc, w);

        // Dividers
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, tallH, w, tallH);
        dc.drawLine(0, tallH * 2, w, tallH * 2);
        dc.drawLine(w / 2, tallH * 2, w / 2, h);

        var spmStr = strokeRate > 0 ? strokeRate.format("%.0f") : "--";
        drawCell(dc, 0, 0, w, tallH, "STROKE RATE", spmStr, lf, bigVf);
        drawCell(dc, 0, tallH, w, tallH, "SPLIT /500m", formatSplit(splitTime), lf, bigVf);
        drawCell(dc, 0, tallH * 2, w / 2, shortH, "DISTANCE", formatDistance(distance), lf, smVf);

        var hrStr = heartRate > 0 ? heartRate.format("%d") : "--";
        drawCell(dc, w / 2, tallH * 2, w / 2, shortH, "HR", hrStr, lf, smVf);

        drawPageIndicator(dc, w, h, 0);
    }

    // Page 2 (4-C): SPM | Distance | HR + Time
    function drawPage4C_2(dc, w, h) {
        var tallH = h * 2 / 5;
        var shortH = h / 5;
        var lf = Graphics.FONT_XTINY;
        var bigVf = Graphics.FONT_NUMBER_THAI_HOT;
        var smVf = Graphics.FONT_NUMBER_HOT;
        drawStatusBar(dc, w);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, tallH, w, tallH);
        dc.drawLine(0, tallH * 2, w, tallH * 2);
        dc.drawLine(w / 2, tallH * 2, w / 2, h);

        var spmStr = strokeRate > 0 ? strokeRate.format("%.0f") : "--";
        drawCell(dc, 0, 0, w, tallH, "STROKE RATE", spmStr, lf, bigVf);
        drawCell(dc, 0, tallH, w, tallH, "DISTANCE", formatDistance(distance), lf, bigVf);

        var hrStr = heartRate > 0 ? heartRate.format("%d") : "--";
        drawCell(dc, 0, tallH * 2, w / 2, shortH, "HR", hrStr, lf, smVf);

        var clockInfo = System.getClockTime();
        var timeStr = clockInfo.hour.format("%d") + ":" + clockInfo.min.format("%02d");
        drawCell(dc, w / 2, tallH * 2, w / 2, shortH, "TIME", timeStr, lf, smVf);

        drawPageIndicator(dc, w, h, 1);
    }

    // Page 3 (5-C): SPM | Split/500m | HR | Distance + Time
    function drawPage5C(dc, w, h) {
        // Row heights: short=h/5, tall=2*h/5
        var u = h / 5;
        var lf = Graphics.FONT_XTINY;
        var bigVf = Graphics.FONT_NUMBER_THAI_HOT;
        var smVf = Graphics.FONT_NUMBER_HOT;
        drawStatusBar(dc, w);

        // y positions: row0=0..u, row1=u..3u, row2=3u..4u, row3=4u..5u
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, u, w, u);
        dc.drawLine(0, u * 3, w, u * 3);
        dc.drawLine(0, u * 4, w, u * 4);
        dc.drawLine(w / 2, u * 4, w / 2, h);

        var spmStr = strokeRate > 0 ? strokeRate.format("%.0f") : "--";
        drawCell(dc, 0, 0, w, u, "STROKE RATE", spmStr, lf, smVf);
        drawCell(dc, 0, u, w, u * 2, "SPLIT /500m", formatSplit(splitTime), lf, bigVf);

        var hrStr = heartRate > 0 ? heartRate.format("%d") : "--";
        drawCell(dc, 0, u * 3, w, u, "HR", hrStr, lf, smVf);

        drawCell(dc, 0, u * 4, w / 2, u, "DISTANCE", formatDistance(distance), lf, smVf);

        var clockInfo = System.getClockTime();
        var timeStr = clockInfo.hour.format("%d") + ":" + clockInfo.min.format("%02d");
        drawCell(dc, w / 2, u * 4, w / 2, u, "TIME", timeStr, lf, smVf);

        drawPageIndicator(dc, w, h, 2);
    }

    // Page 4: Calibration -- 3 equal rows
    function drawPageCalibration(dc, w, h) {
        var rowH = h / 3;
        var lf = Graphics.FONT_XTINY;
        var vf = Graphics.FONT_NUMBER_HOT;
        drawStatusBar(dc, w);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, rowH, w, rowH);
        dc.drawLine(0, rowH * 2, w, rowH * 2);

        drawCell(dc, 0, 0, w, rowH, "STROKES", strokeCount.format("%d"), lf, vf);
        drawCell(dc, 0, rowH, w, rowH, "AVG ACCEL mG", lastLinMagMean.format("%.0f"), lf, vf);
        drawCell(dc, 0, rowH * 2, w, rowH, "MAX ACCEL mG", lastLinMagMax.format("%.0f"), lf, vf);

        drawPageIndicator(dc, w, h, 3);
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

    function drawPageIndicator(dc, w, h, page) {
        var dotY = h - 6;
        var totalW = NUM_PAGES * 10 - 4;
        var dotX = w - totalW - 4;
        for (var i = 0; i < NUM_PAGES; i++) {
            if (i == page) {
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            }
            dc.fillCircle(dotX + i * 10, dotY, 3);
        }
    }

    // Generic cell: label (XTINY) at top, value (large) centered below
    function drawCell(dc, x, y, w, h, label, value, lblFont, valFont) {
        var cx = x + w / 2;
        var lblH = dc.getFontHeight(lblFont);
        var valH = dc.getFontHeight(valFont);
        var totalH = lblH + valH;
        var topY = y + (h - totalH) / 2;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, topY, lblFont, label, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, topY + lblH, valFont, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //
    // Formatters
    //

    function formatSplit(seconds) {
        if (seconds <= 0 || seconds > 600) {
            return "1:52"; // TODO: test hack, remove when GPS works
        }
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
