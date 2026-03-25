using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application;

// Main settings menu: MENU -> [Data Fields, Threshold, Zoom Level]
class MainMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Settings"});
        addItem(new WatchUi.MenuItem("Data Fields", "Configure order", :dataFields, null));
        addItem(new WatchUi.MenuItem("Threshold", "Stroke detection", :threshold, null));

        var app = Application.getApp();
        var cfg = app.fieldConfig;
        var ds = System.getDeviceSettings();
        var fc = (ds.screenHeight > 400) ? cfg.getVisibleCountTall() : cfg.getVisibleCount();
        addItem(new WatchUi.MenuItem("Zoom Level", "z" + cfg.zoomLevel + " (" + fc + " fields)", :zoom, null));
        addItem(new WatchUi.MenuItem("Features", "Auto-pause, demo...", :features, null));
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :dataFields) {
            WatchUi.pushView(
                new FieldListMenu(),
                new FieldListMenuDelegate(),
                WatchUi.SLIDE_LEFT
            );
        } else if (id == :threshold) {
            WatchUi.pushView(
                new ThresholdPicker(),
                new ThresholdPickerDelegate(),
                WatchUi.SLIDE_LEFT
            );
        } else if (id == :zoom) {
            WatchUi.pushView(
                new ZoomMenu(),
                new ZoomMenuDelegate(),
                WatchUi.SLIDE_LEFT
            );
        } else if (id == :features) {
            WatchUi.pushView(
                new FeatureToggleMenu(),
                new FeatureToggleDelegate(),
                WatchUi.SLIDE_LEFT
            );
        }
    }
}

// Field list menu: shows ordered fields, select one to edit/move/remove
class FieldListMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Data Fields"});
        rebuildItems();
    }

    function rebuildItems() {
        // Clear existing
        while (getItem(0) != null) {
            deleteItem(0);
        }

        var app = Application.getApp();
        var cfg = app.fieldConfig;
        for (var i = 0; i < cfg.fields.size(); i++) {
            var fid = cfg.fields[i];
            var pos = (i + 1).format("%d");
            var visCount = cfg.getVisibleCount();
            addItem(new WatchUi.MenuItem(
                pos + ". " + FieldConfig.getMenuLabel(fid),
                i < visCount ? "visible" : "hidden",
                i,  // use index as item ID
                null
            ));
        }
        // Add field option
        addItem(new WatchUi.MenuItem("+ Add Field", null, :addField, null));
    }
}

class FieldListMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var id = item.getId();
        if (id == :addField) {
            WatchUi.pushView(
                new AddFieldMenu(),
                new AddFieldMenuDelegate(),
                WatchUi.SLIDE_LEFT
            );
        } else {
            // id is field index -- show edit menu for this field
            WatchUi.pushView(
                new FieldEditMenu(id),
                new FieldEditMenuDelegate(id),
                WatchUi.SLIDE_LEFT
            );
        }
    }
}

// Edit a single field: Move Up, Move Down, Remove
class FieldEditMenu extends WatchUi.Menu2 {
    function initialize(index) {
        var app = Application.getApp();
        var fid = app.fieldConfig.fields[index];
        Menu2.initialize({:title => FieldConfig.getMenuLabel(fid)});

        if (index > 0) {
            addItem(new WatchUi.MenuItem("Move to Top", null, :moveTop, null));
            addItem(new WatchUi.MenuItem("Move Up", null, :moveUp, null));
        }
        if (index < app.fieldConfig.fields.size() - 1) {
            addItem(new WatchUi.MenuItem("Move Down", null, :moveDown, null));
        }
        if (app.fieldConfig.fields.size() > 2) {
            addItem(new WatchUi.MenuItem("Remove", null, :remove, null));
        }
    }
}

class FieldEditMenuDelegate extends WatchUi.Menu2InputDelegate {
    var fieldIndex;

    function initialize(index) {
        Menu2InputDelegate.initialize();
        fieldIndex = index;
    }

    function onSelect(item) {
        var app = Application.getApp();
        var cfg = app.fieldConfig;
        var id = item.getId();

        if (id == :moveTop) {
            cfg.moveTop(fieldIndex);
        } else if (id == :moveUp) {
            cfg.moveUp(fieldIndex);
        } else if (id == :moveDown) {
            cfg.moveDown(fieldIndex);
        } else if (id == :remove) {
            cfg.removeField(fieldIndex);
        }

        // Pop back to field list and rebuild
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.pushView(
            new FieldListMenu(),
            new FieldListMenuDelegate(),
            WatchUi.SLIDE_LEFT
        );
    }
}

// Add field menu: shows fields not yet in the list
class AddFieldMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Add Field"});
        var app = Application.getApp();
        var cfg = app.fieldConfig;

        for (var fid = 0; fid < FieldConfig.F_COUNT; fid++) {
            // Skip if already in list
            var found = false;
            for (var j = 0; j < cfg.fields.size(); j++) {
                if (cfg.fields[j] == fid) { found = true; break; }
            }
            if (!found) {
                addItem(new WatchUi.MenuItem(
                    FieldConfig.getMenuLabel(fid), null, fid, null
                ));
            }
        }
    }
}

class AddFieldMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var fid = item.getId();
        var app = Application.getApp();
        app.fieldConfig.addField(fid);

        // Pop back to field list and rebuild
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.pushView(
            new FieldListMenu(),
            new FieldListMenuDelegate(),
            WatchUi.SLIDE_LEFT
        );
    }
}

// Zoom level selection: Menu2 list (touch-friendly)
class ZoomMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Zoom Level"});
        var app = Application.getApp();
        var current = app.fieldConfig.zoomLevel;
        // Use tall counts on tall screens (detected via System.getDeviceSettings)
        var ds = System.getDeviceSettings();
        var tall = (ds.screenHeight > 400);
        var counts = tall ? FieldConfig.ZOOM_FIELD_COUNT_TALL : FieldConfig.ZOOM_FIELD_COUNT;
        for (var z = 1; z <= 7; z++) {
            var label = "z" + z + " - " + counts[z] + " fields";
            var sub = (z == current) ? "current" : null;
            addItem(new WatchUi.MenuItem(label, sub, z, null));
        }
    }
}

class ZoomMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var z = item.getId();
        var app = Application.getApp();
        var cfg = app.fieldConfig;
        cfg.zoomLevel = z;
        cfg.save();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// Feature toggle menu: enable/disable features
class FeatureToggleMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Features"});
        var app = Application.getApp();
        var fc = app.featureConfig;
        for (var i = 0; i < FeatureConfig.FEAT_COUNT; i++) {
            addItem(new WatchUi.ToggleMenuItem(
                FeatureConfig.getLabel(i),
                null,
                i,
                fc.isEnabled(i),
                null
            ));
        }
    }
}

class FeatureToggleDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var app = Application.getApp();
        app.featureConfig.toggle(item.getId());
    }
}
