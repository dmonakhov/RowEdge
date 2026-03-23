using Toybox.ActivityRecording;
using Toybox.FitContributor;
using Toybox.Activity;
using Toybox.Application;

class RowingSession {

    var session = null;
    var strokeRateField = null;
    var dpsField = null;
    // Raw axes (1-second means)
    var rawXfield = null;
    var rawYfield = null;
    var rawZfield = null;
    // Linear accel magnitude stats
    var linMagMinField = null;
    var linMagMaxField = null;
    var linMagMeanField = null;
    var linMagEmaField = null;
    // Forward acceleration (signed: positive=drive, negative=recovery)
    var fwdAccelMeanField = null;
    var fwdAccelMinField = null;
    var fwdAccelMaxField = null;

    function initialize() {
    }

    function start() {
        if (session == null) {
            session = ActivityRecording.createSession({
                :sport => Activity.SPORT_ROWING,
                :subSport => Activity.SUB_SPORT_GENERIC,
                :name => "Outdoor Row"
            });

            strokeRateField = session.createField(
                "stroke_rate", 0,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "spm"}
            );

            dpsField = session.createField(
                "distance_per_stroke", 1,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m"}
            );

            // Accel fields only when Accel Logging is enabled
            var app = Application.getApp();
            if (app.featureConfig.isEnabled(FeatureConfig.FEAT_ACCEL_LOG)) {
                rawXfield = session.createField(
                    "accel_raw_x", 2,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                rawYfield = session.createField(
                    "accel_raw_y", 3,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                rawZfield = session.createField(
                    "accel_raw_z", 4,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                linMagMinField = session.createField(
                    "lin_mag_min", 5,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                linMagMaxField = session.createField(
                    "lin_mag_max", 6,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                linMagMeanField = session.createField(
                    "lin_mag_mean", 7,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                linMagEmaField = session.createField(
                    "lin_mag_ema", 8,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                fwdAccelMeanField = session.createField(
                    "fwd_accel_mean", 9,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                fwdAccelMinField = session.createField(
                    "fwd_accel_min", 10,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
                fwdAccelMaxField = session.createField(
                    "fwd_accel_max", 11,
                    FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"}
                );
            }

            session.start();
        }
    }

    function stop() {
        if (session != null && session.isRecording()) {
            session.stop();
        }
    }

    function resume() {
        if (session != null && !session.isRecording()) {
            session.start();
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

    // stats: [rawX, rawY, rawZ, linMagMin, linMagMax, linMagMean, ema,
    //         fwdAccelMean, fwdAccelMin, fwdAccelMax]
    function setAccelStats(stats) {
        if (rawXfield != null) { rawXfield.setData(stats[0].toNumber()); }
        if (rawYfield != null) { rawYfield.setData(stats[1].toNumber()); }
        if (rawZfield != null) { rawZfield.setData(stats[2].toNumber()); }
        if (linMagMinField != null) { linMagMinField.setData(stats[3].toNumber()); }
        if (linMagMaxField != null) { linMagMaxField.setData(stats[4].toNumber()); }
        if (linMagMeanField != null) { linMagMeanField.setData(stats[5].toNumber()); }
        if (linMagEmaField != null) { linMagEmaField.setData(stats[6].toNumber()); }
        if (fwdAccelMeanField != null) { fwdAccelMeanField.setData(stats[7].toNumber()); }
        if (fwdAccelMinField != null) { fwdAccelMinField.setData(stats[8].toNumber()); }
        if (fwdAccelMaxField != null) { fwdAccelMaxField.setData(stats[9].toNumber()); }
    }
}
