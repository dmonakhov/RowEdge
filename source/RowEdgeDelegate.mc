using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Application;

// Edge 540 physical buttons (7 buttons, no touch):
//   Bottom-RIGHT: Start/Stop  -> KEY_START -> onKey()          -> start/pause/resume
//   Bottom-LEFT:  Lap         -> KEY_LAP   -> onKey()          -> lap / stop prompt
//   Right-upper:  Enter/OK    -> KEY_ENTER -> onSelect()       -> settings menu
//   Right-lower:  Back        -> KEY_ESC   -> onBack()         -> lap / stop prompt
//   Left-upper:   Up          -> KEY_UP    -> onPreviousPage() -> zoom in
//   Left-lower:   Down        -> KEY_DOWN  -> onNextPage()     -> zoom out
//   Up (hold):    Menu        -> KEY_MENU  -> onMenu()         -> settings menu
//
// Edge 840 (same 7 buttons + touch):
//   Same as 540, plus touch tap/swipe gestures
//
// Edge 1040/1050 (3 buttons + touch):
//   Bottom-RIGHT: Start/Stop  -> KEY_START -> onKey()          -> start/pause/resume
//   Bottom-LEFT:  Lap         -> KEY_LAP   -> onKey()          -> lap / stop prompt
//   Left-side:    Power       -> system only
//   Touch tap    -> onSelect() -> start/pause/resume (TODO: multi-device phase)
//   Swipe right  -> onBack()   -> lap / stop prompt
//   Swipe up/dn  -> onNextPage()/onPreviousPage() -> zoom

class RowEdgeDelegate extends WatchUi.BehaviorDelegate {

    var view;

    function initialize(rowingView) {
        BehaviorDelegate.initialize();
        view = rowingView;
    }

    // Route physical buttons to actions.
    // Bottom-edge Start/Stop and Lap fire KEY_START/KEY_LAP (not routed
    // by BehaviorDelegate). Right-upper Enter fires KEY_ENTER -> onSelect().
    // We intercept KEY_ENTER so only KEY_START controls the activity,
    // preventing accidental start from the side "Enter/Menu" button.
    // Touch tap on 840/1040/1050 goes directly to onSelect() (not via onKey).
    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START) {
            return handleStartStop();
        } else if (key == WatchUi.KEY_LAP) {
            return handleLap();
        }
        return false;
    }

    // onSelect() fires from KEY_ENTER (right-upper Enter/OK on 540) and
    // touch tap (840/1040/1050). Opens settings menu -- same as onMenu().
    function onSelect() {
        if (view.state == RowingView.STATE_SUMMARY) {
            view.dismissSummary();
            WatchUi.requestUpdate();
            return true;
        }
        return onMenu();
    }

    // Back button (right-lower on 540) / swipe right on touch
    function onBack() {
        return handleLap();
    }

    // Start / Pause / Resume activity
    function handleStartStop() {
        if (view.state == RowingView.STATE_SUMMARY) {
            view.dismissSummary();
            WatchUi.requestUpdate();
            return true;
        }

        var app = Application.getApp();
        var session = app.rowingSession;

        if (view.state == RowingView.STATE_IDLE) {
            if (app.featureConfig.isEnabled(FeatureConfig.FEAT_DEMO_MODE)) {
                view.setState(RowingView.STATE_RECORDING);
            } else {
                app.strokeDetector.startCalibration();
                view.setState(RowingView.STATE_CALIBRATING);
            }
        } else if (view.state == RowingView.STATE_RECORDING) {
            app.strokeDetector.stop();
            session.stop();
            view.setState(RowingView.STATE_PAUSED);
        } else if (view.state == RowingView.STATE_PAUSED) {
            session.resume();
            app.strokeDetector.start();
            view.autoPaused = false;
            view.autoPauseCooldown = 60;
            view.distHistIdx = 0;
            view.distHistCount = 0;
            view.setState(RowingView.STATE_RECORDING);
        }
        WatchUi.requestUpdate();
        return true;
    }

    // Lap (recording) / Save dialog (paused) / Exit (idle)
    function handleLap() {
        if (view.state == RowingView.STATE_SUMMARY) {
            view.dismissSummary();
            WatchUi.requestUpdate();
            return true;
        }

        var app = Application.getApp();

        if (view.state == RowingView.STATE_RECORDING) {
            app.rowingSession.addLap();
            view.onLap();
            WatchUi.requestUpdate();
            return true;
        } else if (view.state == RowingView.STATE_PAUSED) {
            WatchUi.pushView(
                new WatchUi.Confirmation("Save activity?"),
                new SaveConfirmDelegate(view),
                WatchUi.SLIDE_UP
            );
            return true;
        }
        // Idle -- exit app
        return false;
    }

    function onNextPage() {
        // DOWN = zoom out (more fields)
        var app = Application.getApp();
        app.fieldConfig.zoomOut();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() {
        // UP = zoom in (fewer fields)
        var app = Application.getApp();
        app.fieldConfig.zoomIn();
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() {
        WatchUi.pushView(
            new MainMenuView(),
            new MainMenuDelegate(),
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
            // Capture metrics into summary BEFORE reset, then save
            view.showSummary();
            app.rowingSession.save();
            app.rowingSession = new RowingSession();
            app.strokeDetector.reset();
        } else {
            // Discard
            app.rowingSession.discard();
            app.rowingSession = new RowingSession();
            app.strokeDetector.reset();
            view.reset();
            view.setState(RowingView.STATE_IDLE);
        }
        WatchUi.requestUpdate();
        return true;
    }

    // Edge 540: BACK button may pop Confirmation without calling onResponse.
    // Treat as discard.
    function onBack() {
        var app = Application.getApp();
        app.rowingSession.discard();
        app.rowingSession = new RowingSession();
        app.strokeDetector.reset();
        view.reset();
        view.setState(RowingView.STATE_IDLE);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
        return true;
    }
}

//
// Threshold adjustment: UP/DOWN +/-10, BACK exits
//

class ThresholdView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onShow() {
        if (self has :setControlBar) { setControlBar(null); }
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
        adjustThreshold(10);
        return true;
    }

    function onNextPage() {
        adjustThreshold(-10);
        return true;
    }

    function adjustThreshold(delta) {
        var app = Application.getApp();
        var detector = app.strokeDetector;
        var newVal = detector.catchThreshold + delta;
        if (newVal < 10) { newVal = 10; }
        if (newVal > 1500) { newVal = 1500; }
        detector.catchThreshold = newVal;
        Application.Storage.setValue("catchThreshold", newVal.toNumber());
        WatchUi.requestUpdate();
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
