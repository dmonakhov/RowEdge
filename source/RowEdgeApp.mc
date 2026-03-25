using Toybox.Application;
using Toybox.WatchUi;
using Toybox.System;

class RowEdgeApp extends Application.AppBase {

    var strokeDetector;
    var rowingSession;
    var fieldConfig;
    var featureConfig;
    var demoData;
    var radarMonitor;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        fieldConfig = new FieldConfig();
        featureConfig = new FeatureConfig();
        strokeDetector = new StrokeDetector();
        rowingSession = new RowingSession();
        demoData = new DemoDataSource();
        radarMonitor = new RadarMonitor();
    }

    function onStop(state) {
        if (strokeDetector != null) {
            strokeDetector.stop();
        }
        if (rowingSession != null && rowingSession.isRecording()) {
            rowingSession.stop();
            rowingSession.save();
        }
    }

    function getInitialView() {
        var view = new RowingView();
        var delegate = new RowEdgeDelegate(view);
        return [view, delegate];
    }
}
