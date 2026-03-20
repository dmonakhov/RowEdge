using Toybox.WatchUi;
using Toybox.System;
using Toybox.Application;

// Edge 540 buttons:
//   ENTER (select) = start/stop activity
//   BACK  = lap (during recording) or exit (when idle)
//   UP    = previous page
//   DOWN  = next page
//   MENU  = open settings menu (threshold adjust)

class RowEdgeDelegate extends WatchUi.BehaviorDelegate {

    var view;

    function initialize(rowingView) {
        BehaviorDelegate.initialize();
        view = rowingView;
    }

    function onSelect() {
        var app = Application.getApp();
        var session = app.rowingSession;

        if (!session.isRecording()) {
            session.start();
            app.strokeDetector.start();
            view.setState(RowingView.STATE_RECORDING);
        } else {
            app.strokeDetector.stop();
            session.stop();
            view.setState(RowingView.STATE_STOPPED);
            WatchUi.pushView(
                new WatchUi.Confirmation("Save activity?"),
                new SaveConfirmDelegate(view),
                WatchUi.SLIDE_UP
            );
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        var app = Application.getApp();
        var session = app.rowingSession;

        if (session.isRecording()) {
            session.addLap();
            view.onLap();
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onNextPage() {
        view.nextPage();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() {
        view.prevPage();
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() {
        WatchUi.pushView(
            new ThresholdView(),
            new ThresholdDelegate(),
            WatchUi.SLIDE_UP
        );
        return true;
    }
}

class SaveConfirmDelegate extends WatchUi.ConfirmationDelegate {

    var view;

    function initialize(rowingView) {
        ConfirmationDelegate.initialize();
        view = rowingView;
    }

    function onResponse(response) {
        var app = Application.getApp();
        if (response == WatchUi.CONFIRM_YES) {
            app.rowingSession.save();
        } else {
            app.rowingSession.discard();
        }
        app.rowingSession = new RowingSession();
        app.strokeDetector.reset();
        view.reset();
        view.setState(RowingView.STATE_IDLE);
        WatchUi.requestUpdate();
        return true;
    }
}

//
// In-app threshold adjustment screen
// UP/DOWN changes value, BACK exits
//

class ThresholdView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var app = Application.getApp();
        var thr = app.strokeDetector.catchThreshold;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 10, Graphics.FONT_SMALL, "Stroke Threshold",
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h / 2 - 30, Graphics.FONT_NUMBER_MILD,
                    thr.format("%.0f"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 30, Graphics.FONT_XTINY,
                    "milliG linear accel",
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h / 2 + 55, Graphics.FONT_XTINY,
                    "UP: +10  DOWN: -10",
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h / 2 + 75, Graphics.FONT_XTINY,
                    "BACK: done",
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, h - 40, Graphics.FONT_XTINY,
                    "Lower = more sensitive",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class ThresholdDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onPreviousPage() {
        adjustThreshold(10); // UP = higher = less sensitive
        return true;
    }

    function onNextPage() {
        adjustThreshold(-10); // DOWN = lower = more sensitive
        return true;
    }

    function adjustThreshold(delta) {
        var app = Application.getApp();
        var detector = app.strokeDetector;
        var newVal = detector.catchThreshold + delta;
        // Clamp to reasonable range: 10 to 500 milliG
        if (newVal < 10) { newVal = 10; }
        if (newVal > 500) { newVal = 500; }
        detector.catchThreshold = newVal;
        Application.Storage.setValue("catchThreshold", newVal.toNumber());
        WatchUi.requestUpdate();
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
