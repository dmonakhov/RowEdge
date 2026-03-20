using Toybox.ActivityRecording;
using Toybox.FitContributor;
using Toybox.Activity;

class RowingSession {

    var session = null;
    var strokeRateField = null;
    var dpsField = null;

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
}
