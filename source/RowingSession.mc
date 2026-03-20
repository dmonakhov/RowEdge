using Toybox.ActivityRecording;
using Toybox.FitContributor;
using Toybox.Activity;

class RowingSession {

    var session = null;
    var strokeRateField = null;
    var dpsField = null;
    var accelMinField = null;
    var accelMaxField = null;
    var accelMeanField = null;
    var accelEmaField = null;

    function initialize() {
    }

    function start() {
        if (session == null) {
            session = ActivityRecording.createSession({
                :sport => Activity.SPORT_ROWING,
                :subSport => Activity.SUB_SPORT_GENERIC,
                :name => "Outdoor Row"
            });

            // Custom FIT fields for rowing-specific data
            strokeRateField = session.createField(
                "stroke_rate",
                0,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD,
                 :units => "spm"}
            );

            dpsField = session.createField(
                "distance_per_stroke",
                1,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_RECORD,
                 :units => "m"}
            );

            // Raw accelerometer data for offline threshold analysis
            accelMinField = session.createField(
                "accel_y_min",
                2,
                FitContributor.DATA_TYPE_SINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD,
                 :units => "mG"}
            );

            accelMaxField = session.createField(
                "accel_y_max",
                3,
                FitContributor.DATA_TYPE_SINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD,
                 :units => "mG"}
            );

            accelMeanField = session.createField(
                "accel_y_mean",
                4,
                FitContributor.DATA_TYPE_SINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD,
                 :units => "mG"}
            );

            accelEmaField = session.createField(
                "accel_y_ema",
                5,
                FitContributor.DATA_TYPE_SINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD,
                 :units => "mG"}
            );

            session.start();
        }
    }

    function stop() {
        if (session != null && session.isRecording()) {
            session.stop();
        }
    }

    function save() {
        if (session != null) {
            session.save();
            session = null;
        }
    }

    function discard() {
        if (session != null) {
            session.discard();
            session = null;
        }
    }

    function addLap() {
        if (session != null && session.isRecording()) {
            session.addLap();
        }
    }

    function isRecording() {
        return (session != null && session.isRecording());
    }

    function setStrokeRate(spm) {
        if (strokeRateField != null) {
            strokeRateField.setData(spm);
        }
    }

    function setDPS(dps) {
        if (dpsField != null) {
            dpsField.setData(dps);
        }
    }

    // Write 1-second accel statistics: [min, max, mean, ema]
    function setAccelStats(stats) {
        if (accelMinField != null) {
            accelMinField.setData(stats[0].toNumber());
        }
        if (accelMaxField != null) {
            accelMaxField.setData(stats[1].toNumber());
        }
        if (accelMeanField != null) {
            accelMeanField.setData(stats[2].toNumber());
        }
        if (accelEmaField != null) {
            accelEmaField.setData(stats[3].toNumber());
        }
    }
}
