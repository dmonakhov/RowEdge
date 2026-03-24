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
    // High-frequency forward accel: 25 samples/sec packed as 13 SINT32 fields
    // Each SINT32 = 2x sint16 packed: low=sample[2k], high=sample[2k+1]
    var hfreqFields = null; // array of 13 FitField, or null if disabled
    // Rowing metrics log (per-stroke values, written each second)
    var rmForceRatio = null;
    var rmDeltaV = null;
    var rmDriveTime = null;
    var rmRecovTime = null;
    var rmCatchDur = null;
    var rmCatchSlope = null;
    var rmPeakAccel = null;
    var rmAccelAvg = null;
    var rmAccelMax = null;

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

            var app = Application.getApp();
            var hfreq = app.featureConfig.isEnabled(FeatureConfig.FEAT_HFREQ_ACCEL);

            if (hfreq) {
                // High-frequency mode: 25 fwd_accel samples/sec packed as 13 SINT32
                // Each SINT32 = 2x sint16: low 16 bits = sample[2k], high = sample[2k+1]
                // Uses 13 fields + 2 base = 15 total (max 16 allowed)
                hfreqFields = new [13];
                for (var k = 0; k < 13; k++) {
                    hfreqFields[k] = session.createField(
                        "hf_" + k, 2 + k,
                        FitContributor.DATA_TYPE_SINT32,
                        {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG2"}
                    );
                }
            } else if (app.featureConfig.isEnabled(FeatureConfig.FEAT_ACCEL_LOG)) {
                // Low-frequency mode: 1Hz summary stats (10 fields)
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
            } else if (app.featureConfig.isEnabled(FeatureConfig.FEAT_ROWING_LOG)) {
                // Rowing metrics: 9 fields, per-stroke values written each second
                // 2 base + 9 = 11 fields, 41 bytes
                rmForceRatio = session.createField(
                    "force_ratio", 2, FitContributor.DATA_TYPE_FLOAT,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => ""});
                rmDeltaV = session.createField(
                    "delta_v", 3, FitContributor.DATA_TYPE_FLOAT,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m/s"});
                rmDriveTime = session.createField(
                    "drive_time", 4, FitContributor.DATA_TYPE_FLOAT,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"});
                rmRecovTime = session.createField(
                    "recov_time", 5, FitContributor.DATA_TYPE_FLOAT,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"});
                rmCatchDur = session.createField(
                    "catch_dur", 6, FitContributor.DATA_TYPE_FLOAT,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"});
                rmCatchSlope = session.createField(
                    "catch_slope", 7, FitContributor.DATA_TYPE_FLOAT,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG/s"});
                rmPeakAccel = session.createField(
                    "peak_accel", 8, FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"});
                rmAccelAvg = session.createField(
                    "accel_avg", 9, FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"});
                rmAccelMax = session.createField(
                    "accel_max", 10, FitContributor.DATA_TYPE_SINT16,
                    {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mG"});
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

    // Write 25 packed high-frequency samples (13 SINT32 values)
    function setHfreqData(packed) {
        if (hfreqFields != null) {
            for (var k = 0; k < 13; k++) {
                hfreqFields[k].setData(packed[k]);
            }
        }
    }

    // Write rowing metrics from StrokeDetector (called each second,
    // values persist from last stroke detection)
    function setRowingMetrics(det, accelAvg, accelMax) {
        if (rmForceRatio != null) { rmForceRatio.setData(det.strokeForceRatio); }
        if (rmDeltaV != null) { rmDeltaV.setData(det.strokeDeltaV); }
        if (rmDriveTime != null) { rmDriveTime.setData(det.strokeDriveTime); }
        if (rmRecovTime != null) { rmRecovTime.setData(det.strokeRecovTime); }
        if (rmCatchDur != null) { rmCatchDur.setData(det.strokeCatchDur); }
        if (rmCatchSlope != null) { rmCatchSlope.setData(det.strokeCatchSlope); }
        if (rmPeakAccel != null) { rmPeakAccel.setData(det.strokePeak.toNumber()); }
        if (rmAccelAvg != null) { rmAccelAvg.setData(accelAvg.toNumber()); }
        if (rmAccelMax != null) { rmAccelMax.setData(accelMax.toNumber()); }
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
