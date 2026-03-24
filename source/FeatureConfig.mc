using Toybox.Application;

// Feature flags manager. Toggle features on/off from Settings menu.
class FeatureConfig {

    enum {
        FEAT_AUTO_PAUSE,
        FEAT_DEMO_MODE,
        FEAT_ACCEL_LOG,
        FEAT_HFREQ_ACCEL,
        FEAT_CURVE_METRICS,
        FEAT_ROWING_LOG,
        FEAT_COUNT
    }

    var enabled;

    function initialize() {
        enabled = new [FEAT_COUNT];
        load();
    }

    function load() {
        enabled[FEAT_AUTO_PAUSE] = loadBool("feat_autoPause", true);
        enabled[FEAT_DEMO_MODE] = loadBool("feat_demoMode", false);
        enabled[FEAT_ACCEL_LOG] = loadBool("feat_accelLog", false);
        enabled[FEAT_HFREQ_ACCEL] = loadBool("feat_hfreqAccel", false);
        enabled[FEAT_CURVE_METRICS] = loadBool("feat_curveMetrics", true);
        enabled[FEAT_ROWING_LOG] = loadBool("feat_rowingLog", true);
    }

    function loadBool(key, defaultVal) {
        var v = Application.Storage.getValue(key);
        return (v != null) ? v : defaultVal;
    }

    function isEnabled(featId) {
        return enabled[featId];
    }

    function toggle(featId) {
        enabled[featId] = !enabled[featId];
        var keys = ["feat_autoPause", "feat_demoMode", "feat_accelLog", "feat_hfreqAccel",
                    "feat_curveMetrics", "feat_rowingLog"];
        Application.Storage.setValue(keys[featId], enabled[featId]);
    }

    static function getLabel(featId) {
        switch (featId) {
            case FEAT_AUTO_PAUSE: return "Auto Pause";
            case FEAT_DEMO_MODE: return "Demo Mode";
            case FEAT_ACCEL_LOG: return "Accel Logging";
            case FEAT_HFREQ_ACCEL: return "HF Accel (25Hz)";
            case FEAT_CURVE_METRICS: return "Curve Metrics";
            case FEAT_ROWING_LOG: return "Rowing Metrics Log";
            default: return "?";
        }
    }
}
