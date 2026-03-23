using Toybox.Application;
using Toybox.System;
using Toybox.Activity;

// Data field registry and configuration.
// Fields stored as ordered array (priority order, index 0 = hero).
//
// Wahoo-style zoom levels:
//   z1: 1 field  (full screen)
//   z2: 2 fields (hero + 1 row)
//   z3: 3 fields (hero + 2 full-width rows)
//   z4: 5 fields (hero + 2x2 grid)
//   z5: 7 fields (hero + 2x3 grid)
//   z6: 9 fields (hero + 2x4 grid)
//   z7: 11 fields (hero + 2x5 grid)
// Field count per zoom: 1, 2, 3, 5, 7, 9, 11

class FieldConfig {

    // Field ID constants
    enum {
        F_SPLIT,      // Split /500m
        F_SPM,        // Stroke rate
        F_HR,         // Heart rate
        F_DISTANCE,   // Distance
        F_TIME,       // Elapsed time
        F_CLOCK,      // Time of day
        F_DPS,        // Meters per stroke
        F_STROKES,    // Stroke count
        F_SPEED,      // Speed m/s
        F_AVG_SPLIT,  // Average split
        F_CALORIES,   // Calories
        F_ACCEL_AVG,  // Avg accel (calibration)
        F_ACCEL_MAX,  // Max accel (calibration)
        F_ACCEL_CURVE, // Acceleration curve graph
        F_COUNT       // sentinel
    }

    // Ordered field list (priority order)
    var fields;

    // Zoom level 1-7 (maps to field count via zoomToFieldCount)
    var zoomLevel = 4;
    const ZOOM_MIN = 1;
    const ZOOM_MAX = 7;

    // Field counts per zoom level: z1=1, z2=2, z3=3, z4=5, z5=7, z6=9, z7=11
    static var ZOOM_FIELD_COUNT = [0, 1, 2, 3, 5, 7, 9, 11];

    static var DEFAULT_FIELDS = [
        F_SPLIT, F_HR, F_SPM, F_DISTANCE,
        F_TIME, F_CLOCK, F_DPS, F_STROKES,
        F_AVG_SPLIT, F_SPEED, F_ACCEL_AVG
    ];

    function initialize() {
        load();
    }

    function load() {
        var saved = Application.Storage.getValue("fieldOrder");
        if (saved != null && saved instanceof Array && saved.size() > 0) {
            fields = saved;
        } else {
            fields = DEFAULT_FIELDS.slice(0, null);
        }
        var savedZoom = Application.Storage.getValue("zoomLevel");
        if (savedZoom != null) {
            zoomLevel = savedZoom;
            if (zoomLevel < ZOOM_MIN) { zoomLevel = ZOOM_MIN; }
            if (zoomLevel > ZOOM_MAX) { zoomLevel = ZOOM_MAX; }
        } else {
            zoomLevel = 4; // default: 5 fields (hero + 2x2)
        }
    }

    function save() {
        Application.Storage.setValue("fieldOrder", fields);
        Application.Storage.setValue("zoomLevel", zoomLevel);
    }

    // Get number of visible fields for current zoom level
    function getVisibleCount() {
        var n = ZOOM_FIELD_COUNT[zoomLevel];
        if (n > fields.size()) { n = fields.size(); }
        return n;
    }

    // Get visible fields (first N based on zoom level)
    function getVisibleFields() {
        return fields.slice(0, getVisibleCount());
    }

    function moveUp(index) {
        if (index > 0 && index < fields.size()) {
            var tmp = fields[index - 1];
            fields[index - 1] = fields[index];
            fields[index] = tmp;
            save();
        }
    }

    function moveDown(index) {
        if (index >= 0 && index < fields.size() - 1) {
            var tmp = fields[index + 1];
            fields[index + 1] = fields[index];
            fields[index] = tmp;
            save();
        }
    }

    function addField(fieldId) {
        for (var i = 0; i < fields.size(); i++) {
            if (fields[i] == fieldId) { return; }
        }
        fields.add(fieldId);
        save();
    }

    function removeField(index) {
        if (index >= 0 && index < fields.size() && fields.size() > 1) {
            var newFields = new [fields.size() - 1];
            var j = 0;
            for (var i = 0; i < fields.size(); i++) {
                if (i != index) {
                    newFields[j] = fields[i];
                    j++;
                }
            }
            fields = newFields;
            save();
        }
    }

    function zoomIn() {
        if (zoomLevel > ZOOM_MIN) {
            zoomLevel--;
            save();
        }
    }

    function zoomOut() {
        if (zoomLevel < ZOOM_MAX) {
            // Don't zoom out beyond available fields
            var nextCount = ZOOM_FIELD_COUNT[zoomLevel + 1];
            if (nextCount <= fields.size()) {
                zoomLevel++;
                save();
            }
        }
    }

    // --- Field metadata ---

    static function getLabel(fieldId) {
        switch (fieldId) {
            case F_SPLIT:     return "SPLIT /500m";
            case F_SPM:       return "SPM";
            case F_HR:        return "HR";
            case F_DISTANCE:  return "DISTANCE";
            case F_TIME:      return "TIME";
            case F_CLOCK:     return "CLOCK";
            case F_DPS:       return "m/STROKE";
            case F_STROKES:   return "STROKES";
            case F_SPEED:     return "SPEED";
            case F_AVG_SPLIT: return "AVG SPLIT";
            case F_CALORIES:  return "CALORIES";
            case F_ACCEL_AVG: return "AVG ACCEL";
            case F_ACCEL_MAX: return "MAX ACCEL";
            case F_ACCEL_CURVE: return "ACCEL CURVE";
            default:          return "?";
        }
    }

    static function getMenuLabel(fieldId) {
        switch (fieldId) {
            case F_SPLIT:     return "Split /500m";
            case F_SPM:       return "Stroke Rate";
            case F_HR:        return "Heart Rate";
            case F_DISTANCE:  return "Distance";
            case F_TIME:      return "Elapsed Time";
            case F_CLOCK:     return "Time of Day";
            case F_DPS:       return "Meters/Stroke";
            case F_STROKES:   return "Stroke Count";
            case F_SPEED:     return "Speed";
            case F_AVG_SPLIT: return "Avg Split";
            case F_CALORIES:  return "Calories";
            case F_ACCEL_AVG: return "Avg Accel";
            case F_ACCEL_MAX: return "Max Accel";
            case F_ACCEL_CURVE: return "Accel Curve";
            default:          return "Unknown";
        }
    }
}
