using Toybox.AntPlus;
using Toybox.System;
using Toybox.Attention;
using Toybox.Position;

// Forward-facing Varia radar obstacle detection for rowing.
// On-water validated: no false positives from waves or canal walls.
//
// Classification uses GPS boat speed + radar relative speed:
//   STATIONARY: buoy, dock, bridge (relative_speed ~ boat_speed)
//   ONCOMING:   boat heading toward us (relative_speed > boat_speed)
//   OVERTAKING: we're passing slower object (relative_speed < boat_speed)
//
// Threat level from hybrid TTC (time-to-collision) + absolute range.
// 3-hit persistence filter before confirming targets.

class RadarMonitor extends AntPlus.BikeRadarListener {

    var bikeRadar = null;

    // Classification constants
    enum { CLS_UNKNOWN, CLS_STATIONARY, CLS_ONCOMING, CLS_OVERTAKING, CLS_MOVING_AWAY }
    const SPEED_TOL = 0.5;  // m/s tolerance for classification

    // Published state (read by RowingView for display)
    var targetCount = 0;
    var closestRange = 0;      // meters
    var closestSpeed = 0.0;    // m/s relative (closing) speed
    var closestTTC = 0.0;      // seconds to collision
    var closestClass = 0;      // CLS_* enum
    var threatLevel = 0;       // 0=clear, 1=caution, 2=warning, 3=danger

    // Persistence: require 3 consecutive scans before confirming
    const CONFIRM_HITS = 3;
    const DROP_MISSES = 3;
    const ASSOC_GATE = 15.0;   // meters: max range difference for association

    // Track slots (simple fixed array, max 8 like Varia)
    var trackRange = new [8];
    var trackSpeed = new [8];
    var trackHits = new [8];
    var trackMisses = new [8];
    var trackClass = new [8];
    var trackCount = 0;

    // Alert state
    var prevThreatLevel = 0;
    var lastAlertTime = 0;
    const ALERT_COOLDOWN_MS = 3000;
    const DANGER_REPEAT_MS = 2000;

    function initialize() {
        BikeRadarListener.initialize();
        bikeRadar = new AntPlus.BikeRadar(self);
        resetTracks();
    }

    function resetTracks() {
        for (var i = 0; i < 8; i++) {
            trackRange[i] = 0;
            trackSpeed[i] = 0.0;
            trackHits[i] = 0;
            trackMisses[i] = 0;
            trackClass[i] = CLS_UNKNOWN;
        }
        trackCount = 0;
    }

    // Get boat speed from GPS
    function getBoatSpeed() {
        var posInfo = Position.getInfo();
        if (posInfo != null && posInfo.speed != null) {
            return posInfo.speed;
        }
        return 0.0;
    }

    // Classify target using boat speed + radar relative speed
    function classifyTarget(relativeSpeed) {
        var boatSpeed = getBoatSpeed();
        var inferred = relativeSpeed - boatSpeed;

        if (relativeSpeed <= 0) {
            return CLS_MOVING_AWAY;
        } else if (inferred.abs() < SPEED_TOL) {
            return CLS_STATIONARY;
        } else if (inferred > SPEED_TOL) {
            return CLS_ONCOMING;
        } else {
            return CLS_OVERTAKING;
        }
    }

    // Compute TTC (seconds). Returns 999 if not approaching.
    function computeTTC(range, relativeSpeed) {
        if (relativeSpeed <= 0.1 || range <= 0) {
            return 999.0;
        }
        return range.toFloat() / relativeSpeed;
    }

    // Compute threat level from TTC + range + classification.
    // Oncoming objects get earlier alerts (higher closing speed = less reaction time).
    function computeThreat(range, relativeSpeed, ttc, cls) {
        // DANGER: immediate evasive action
        if (range <= 15) { return 3; }
        if (ttc < 4.0 && relativeSpeed > 1.0) { return 3; }
        if (cls == CLS_ONCOMING && ttc < 6.0) { return 3; }

        // WARNING: prepare to act
        if (range <= 40) { return 2; }
        if (ttc < 10.0 && relativeSpeed > 1.0) { return 2; }
        if (cls == CLS_ONCOMING && ttc < 18.0) { return 2; }

        // CAUTION: awareness
        if (range <= 80) { return 1; }
        if (ttc < 20.0) { return 1; }
        if (cls == CLS_ONCOMING && range <= 120) { return 1; }

        return 0;
    }

    // Callback from BikeRadarListener (~1-4 Hz)
    function onBikeRadarUpdate(data) {
        if (data == null || data.size() == 0) {
            // No targets: increment all track misses
            for (var i = 0; i < trackCount; i++) {
                trackMisses[i]++;
            }
            pruneTracks();
            updatePublishedState();
            return;
        }

        // Extract valid detections
        var detRange = new [8];
        var detSpeed = new [8];
        var detCount = 0;
        for (var i = 0; i < data.size() && i < 8; i++) {
            var r = data[i].range;
            if (r > 3 && r < 255) {  // ignore < 3m (bow spray) and empty slots
                detRange[detCount] = r.toNumber();
                detSpeed[detCount] = data[i].speed;
                detCount++;
            }
        }

        // Associate detections with existing tracks (nearest-neighbor)
        var usedDet = new [8];
        var usedTrk = new [8];
        for (var i = 0; i < 8; i++) { usedDet[i] = false; usedTrk[i] = false; }

        for (var ti = 0; ti < trackCount; ti++) {
            var bestDi = -1;
            var bestDist = ASSOC_GATE;
            // Predict where track should be
            var predicted = trackRange[ti] - trackSpeed[ti] * 1.0; // ~1s between updates
            for (var di = 0; di < detCount; di++) {
                if (usedDet[di]) { continue; }
                var dist = (detRange[di] - predicted).abs();
                if (dist < bestDist) {
                    bestDist = dist;
                    bestDi = di;
                }
            }
            if (bestDi >= 0) {
                // Update track
                trackRange[ti] = detRange[bestDi];
                trackSpeed[ti] = detSpeed[bestDi];
                trackHits[ti]++;
                trackMisses[ti] = 0;
                trackClass[ti] = classifyTarget(detSpeed[bestDi]);
                usedDet[bestDi] = true;
                usedTrk[ti] = true;
            } else {
                // Track missed this scan
                trackMisses[ti]++;
                // Coast: predict position
                trackRange[ti] = predicted > 0 ? predicted : 0;
            }
        }

        // Create new tracks from unassociated detections
        for (var di = 0; di < detCount; di++) {
            if (usedDet[di]) { continue; }
            if (trackCount < 8) {
                trackRange[trackCount] = detRange[di];
                trackSpeed[trackCount] = detSpeed[di];
                trackHits[trackCount] = 1;
                trackMisses[trackCount] = 0;
                trackClass[trackCount] = classifyTarget(detSpeed[di]);
                trackCount++;
            }
        }

        pruneTracks();
        updatePublishedState();
    }

    // Remove stale tracks
    function pruneTracks() {
        var writeIdx = 0;
        for (var i = 0; i < trackCount; i++) {
            if (trackMisses[i] < DROP_MISSES) {
                if (writeIdx != i) {
                    trackRange[writeIdx] = trackRange[i];
                    trackSpeed[writeIdx] = trackSpeed[i];
                    trackHits[writeIdx] = trackHits[i];
                    trackMisses[writeIdx] = trackMisses[i];
                    trackClass[writeIdx] = trackClass[i];
                }
                writeIdx++;
            }
        }
        trackCount = writeIdx;
    }

    // Update published state from confirmed tracks
    function updatePublishedState() {
        var bestRange = 999;
        var bestSpeed = 0.0;
        var bestTTC = 999.0;
        var bestClass = CLS_UNKNOWN;
        var bestThreat = 0;
        var confirmed = 0;

        for (var i = 0; i < trackCount; i++) {
            if (trackHits[i] < CONFIRM_HITS) {
                continue;  // not yet confirmed
            }
            confirmed++;

            var r = trackRange[i];
            var s = trackSpeed[i];
            var ttc = computeTTC(r, s);
            var cls = trackClass[i];
            var threat = computeThreat(r, s, ttc, cls);

            if (threat > bestThreat || (threat == bestThreat && r < bestRange)) {
                bestRange = r;
                bestSpeed = s;
                bestTTC = ttc;
                bestClass = cls;
                bestThreat = threat;
            }
        }

        targetCount = confirmed;
        closestRange = (bestRange < 999) ? bestRange : 0;
        closestSpeed = bestSpeed;
        closestTTC = bestTTC;
        closestClass = bestClass;

        // Alert logic
        prevThreatLevel = threatLevel;
        threatLevel = bestThreat;

        var now = System.getTimer();
        if (threatLevel > prevThreatLevel && threatLevel >= 2) {
            // Escalation alert
            if (now - lastAlertTime > ALERT_COOLDOWN_MS) {
                playAlert(threatLevel);
                lastAlertTime = now;
            }
        } else if (threatLevel >= 3 && now - lastAlertTime > DANGER_REPEAT_MS) {
            // Repeat danger alerts
            playAlert(3);
            lastAlertTime = now;
        } else if (threatLevel == 0 && prevThreatLevel >= 3) {
            // Danger cleared: brief acknowledgment
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(30, 100)]);
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

    // Classification label for display
    function getClassLabel() {
        switch (closestClass) {
            case CLS_STATIONARY: return "STA";
            case CLS_ONCOMING: return "ONC";
            case CLS_OVERTAKING: return "OVT";
            case CLS_MOVING_AWAY: return "AWY";
            default: return "";
        }
    }

    // Demo mode: simulate approaching stationary buoy + oncoming boat
    function injectDemoTarget(elapsed) {
        var cycle = elapsed % 60;
        if (cycle < 35) {
            // Stationary buoy: range decreases at boat speed (~3.5 m/s)
            var range = 120 - (cycle * 3.5);
            if (range < 5) { range = 5; }
            targetCount = 1;
            closestRange = range.toNumber();
            closestSpeed = 3.5;
            closestClass = CLS_STATIONARY;
            closestTTC = computeTTC(closestRange, closestSpeed);
        } else if (cycle < 50) {
            // Oncoming boat: closes much faster (~8 m/s relative)
            var t = cycle - 35;
            var range = 100 - (t * 8);
            if (range < 5) { range = 5; }
            targetCount = 1;
            closestRange = range.toNumber();
            closestSpeed = 8.0;
            closestClass = CLS_ONCOMING;
            closestTTC = computeTTC(closestRange, closestSpeed);
        } else {
            // Clear
            targetCount = 0;
            closestRange = 0;
            closestSpeed = 0.0;
            closestClass = CLS_UNKNOWN;
            closestTTC = 999.0;
        }

        prevThreatLevel = threatLevel;
        threatLevel = (targetCount > 0) ?
            computeThreat(closestRange, closestSpeed, closestTTC, closestClass) : 0;

        var now = System.getTimer();
        if (threatLevel > prevThreatLevel && threatLevel >= 2) {
            if (now - lastAlertTime > ALERT_COOLDOWN_MS) {
                playAlert(threatLevel);
                lastAlertTime = now;
            }
        } else if (threatLevel >= 3 && now - lastAlertTime > DANGER_REPEAT_MS) {
            playAlert(3);
            lastAlertTime = now;
        }
    }
}
