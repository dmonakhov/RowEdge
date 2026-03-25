using Toybox.AntPlus;
using Toybox.System;
using Toybox.Attention;

// Varia radar integration for obstacle detection.
// Forward-facing mount on bow -- detects approaching objects while rowing.
// Validated on water: no false positives from wave reflections.
//
// Uses raw range/speed data for rowing-specific alert logic
// (ignores firmware threat classification designed for cycling).

class RadarMonitor extends AntPlus.BikeRadarListener {

    var bikeRadar = null;

    // Current state
    var targetCount = 0;
    var closestRange = 0;      // meters to closest target
    var closestSpeed = 0.0;    // m/s approach speed of closest
    var threatLevel = 0;       // 0=clear, 1=caution, 2=warning, 3=danger

    // Alert thresholds (meters)
    const RANGE_DANGER = 15;   // immediate danger
    const RANGE_WARNING = 40;  // warning zone
    const RANGE_CAUTION = 80;  // first detection alert

    // Debounce: don't re-alert for same threat within N seconds
    var lastAlertTime = 0;
    const ALERT_COOLDOWN_MS = 3000;

    // Track previous state for transition alerts
    var prevThreatLevel = 0;

    function initialize() {
        BikeRadarListener.initialize();
        bikeRadar = new AntPlus.BikeRadar(self);
    }

    // Callback from BikeRadarListener -- fired on each radar update (~1-4 Hz)
    function onBikeRadarUpdate(data) {
        if (data == null || data.size() == 0) {
            targetCount = 0;
            closestRange = 0;
            closestSpeed = 0.0;
            threatLevel = 0;
            return;
        }

        // Find closest target with non-zero range
        var minRange = 999;
        var minSpeed = 0.0;
        var count = 0;

        for (var i = 0; i < data.size(); i++) {
            var range = data[i].range;
            if (range > 0 && range < 255) {
                count++;
                if (range < minRange) {
                    minRange = range;
                    minSpeed = data[i].speed;
                }
            }
        }

        targetCount = count;
        if (count > 0) {
            closestRange = minRange.toNumber();
            closestSpeed = minSpeed;
        } else {
            closestRange = 0;
            closestSpeed = 0.0;
        }

        // Compute rowing-specific threat level from raw range
        prevThreatLevel = threatLevel;
        if (closestRange > 0 && closestRange <= RANGE_DANGER) {
            threatLevel = 3;
        } else if (closestRange > 0 && closestRange <= RANGE_WARNING) {
            threatLevel = 2;
        } else if (closestRange > 0 && closestRange <= RANGE_CAUTION) {
            threatLevel = 1;
        } else {
            threatLevel = 0;
        }

        // Alert on threat escalation
        if (threatLevel > prevThreatLevel && threatLevel >= 2) {
            var now = System.getTimer();
            if (now - lastAlertTime > ALERT_COOLDOWN_MS) {
                playAlert(threatLevel);
                lastAlertTime = now;
            }
        }
    }

    function playAlert(level) {
        if (Attention has :playTone) {
            if (level >= 3) {
                Attention.playTone(Attention.TONE_ALERT_HI);
            } else {
                Attention.playTone(Attention.TONE_ALERT_LO);
            }
        }
        if (Attention has :vibrate) {
            var intensity = (level >= 3) ? 100 : 50;
            var duration = (level >= 3) ? 500 : 200;
            Attention.vibrate([new Attention.VibeProfile(intensity, duration)]);
        }
    }

    function isConnected() {
        return (targetCount > 0 || bikeRadar != null);
    }
}
