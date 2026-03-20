using Toybox.WatchUi;
using Toybox.System;

// Edge 540 button mapping:
//   ENTER (select) = start/stop activity
//   BACK = lap (during recording) or exit (when stopped)
//   UP/DOWN = page scroll (future)

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
            // Start recording
            session.start();
            app.strokeDetector.start();
            view.setState(RowingView.STATE_RECORDING);
        } else {
            // Stop recording -- show save confirmation
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
            // Create a lap
            session.addLap();
            view.onLap();
            WatchUi.requestUpdate();
            return true;
        }
        // Not recording -- exit app
        return false;
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
        // Reset for next session
        app.rowingSession = new RowingSession();
        app.strokeDetector.reset();
        view.reset();
        view.setState(RowingView.STATE_IDLE);
        WatchUi.requestUpdate();
        return true;
    }
}
