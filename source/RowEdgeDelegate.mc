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

    // onSelect() fires from KEY_ENTER (right-upper on 540) and tap (touch devices).
    // During recording: do nothing (prevent accidental settings on touch).
    // Idle/paused: open settings.
    function onSelect() {
        if (view.state == RowingView.STATE_SUMMARY) {
            view.dismissSummary();
            WatchUi.requestUpdate();
            return true;
        }
        if (view.state == RowingView.STATE_RECORDING) {
            return true;  // consume, no action during recording
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
        // DOWN / swipe-up = zoom out (more fields)
        var app = Application.getApp();
        app.fieldConfig.zoomOut();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() {
        // UP / swipe-down = zoom in (fewer fields)
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
// Threshold picker: scroll wheel with NumberFactory (touch-friendly)
//

class NumberFactory extends WatchUi.PickerFactory {
    var start;
    var stop;
    var step;

    function initialize(s, e, inc) {
        PickerFactory.initialize();
        start = s;
        stop = e;
        step = inc;
    }

    function getIndex(value) {
        return (value - start) / step;
    }

    function getDrawable(index, selected) {
        var val = start + (index * step);
        return new WatchUi.Text({
            :text => val.format("%d"),
            :color => Graphics.COLOR_WHITE,
            :font => Graphics.FONT_NUMBER_MILD,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });
    }

    function getValue(index) {
        return start + (index * step);
    }

    function getSize() {
        return (stop - start) / step + 1;
    }
}

class ThresholdPicker extends WatchUi.Picker {
    function initialize() {
        var app = Application.getApp();
        var current = app.strokeDetector.catchThreshold.toNumber();
        var factory = new NumberFactory(10, 1500, 10);
        var title = new WatchUi.Text({
            :text => "Threshold (mG)",
            :color => Graphics.COLOR_WHITE,
            :font => Graphics.FONT_SMALL,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_BOTTOM
        });
        Picker.initialize({
            :title => title,
            :pattern => [factory],
            :defaults => [factory.getIndex(current)]
        });
    }
}

class ThresholdPickerDelegate extends WatchUi.PickerDelegate {
    function initialize() {
        PickerDelegate.initialize();
    }

    function onAccept(values) {
        var val = values[0];
        var app = Application.getApp();
        app.strokeDetector.catchThreshold = val.toFloat();
        Application.Storage.setValue("catchThreshold", val);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onCancel() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
