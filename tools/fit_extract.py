#!/usr/bin/env python3
"""Extract rowing data from RowEdge FIT files into TSV + gnuplot scripts.

Usage:
    python3 tools/fit_extract.py activities/2026-03-23-08-21-04.fit

Creates <basename>/ directory with:
    gps.tsv          - lat, lon, speed, distance, heart_rate
    accel.tsv        - raw x/y/z, lin_mag min/max/mean/ema
    strokes.tsv      - stroke_rate, distance_per_stroke
    summary.txt      - session summary
    plot_gps.gp      - gnuplot: GPS track + speed
    plot_accel.gp    - gnuplot: acceleration data
    plot_strokes.gp  - gnuplot: stroke rate + DPS
    plot_all.sh       - run all gnuplot scripts
"""

import sys
import os
import math
import fitparse

def semicircles_to_deg(sc):
    """Convert Garmin semicircles to degrees."""
    return sc * (180.0 / 2**31)

def extract(fit_path):
    base = os.path.splitext(os.path.basename(fit_path))[0]
    outdir = os.path.join(os.path.dirname(fit_path), base)
    os.makedirs(outdir, exist_ok=True)

    f = fitparse.FitFile(fit_path)

    gps_rows = []
    accel_rows = []
    stroke_rows = []
    session_info = {}

    t0 = None
    for msg in f.get_messages():
        if msg.name == 'session':
            for field in msg.fields:
                session_info[field.name] = field.value

        if msg.name != 'record':
            continue

        d = {}
        for field in msg.fields:
            d[field.name] = field.value

        ts = d.get('timestamp')
        if ts is None:
            continue
        if t0 is None:
            t0 = ts
        elapsed = (ts - t0).total_seconds()

        # GPS data
        lat = d.get('position_lat')
        lon = d.get('position_long')
        lat_deg = semicircles_to_deg(lat) if lat is not None else None
        lon_deg = semicircles_to_deg(lon) if lon is not None else None
        speed = d.get('enhanced_speed')  # m/s
        dist = d.get('distance')  # m
        hr = d.get('heart_rate')
        temp = d.get('temperature')

        # Split /500m from speed
        split500 = None
        if speed is not None and speed > 0.1:
            split500 = 500.0 / speed  # seconds per 500m

        gps_rows.append((elapsed, lat_deg, lon_deg, speed, dist, hr, temp, split500))

        # Accel data (developer fields)
        ax = d.get('accel_raw_x')
        ay = d.get('accel_raw_y')
        az = d.get('accel_raw_z')
        lmin = d.get('lin_mag_min')
        lmax = d.get('lin_mag_max')
        lmean = d.get('lin_mag_mean')
        lema = d.get('lin_mag_ema')
        accel_rows.append((elapsed, ax, ay, az, lmin, lmax, lmean, lema))

        # Stroke data
        spm = d.get('stroke_rate')
        dps = d.get('distance_per_stroke')
        stroke_rows.append((elapsed, spm, dps))

    # Write TSV files
    def w(name, header, rows):
        path = os.path.join(outdir, name)
        with open(path, 'w') as fh:
            fh.write('# ' + '\t'.join(header) + '\n')
            for row in rows:
                fh.write('\t'.join(str(v) if v is not None else 'NaN' for v in row) + '\n')
        print(f"  {name}: {len(rows)} rows")

    print(f"Output: {outdir}/")
    w('gps.tsv',
      ['elapsed_s', 'lat_deg', 'lon_deg', 'speed_ms', 'distance_m', 'heart_rate', 'temp_C', 'split500_s'],
      gps_rows)
    w('accel.tsv',
      ['elapsed_s', 'raw_x_mG', 'raw_y_mG', 'raw_z_mG', 'lin_mag_min', 'lin_mag_max', 'lin_mag_mean', 'lin_mag_ema'],
      accel_rows)
    w('strokes.tsv',
      ['elapsed_s', 'stroke_rate_spm', 'distance_per_stroke_m'],
      stroke_rows)

    # Summary
    spath = os.path.join(outdir, 'summary.txt')
    with open(spath, 'w') as fh:
        fh.write(f"FIT file: {fit_path}\n")
        fh.write(f"Records: {len(gps_rows)}\n")
        sport = session_info.get('sport', '?')
        fh.write(f"Sport: {sport}\n")
        dur = session_info.get('total_timer_time', 0)
        fh.write(f"Duration: {int(dur//60)}m {int(dur%60)}s\n")
        dist = session_info.get('total_distance', 0)
        fh.write(f"Distance: {dist:.0f} m ({dist/1000:.2f} km)\n")
        avg_spd = session_info.get('enhanced_avg_speed')
        if avg_spd and avg_spd > 0:
            fh.write(f"Avg speed: {avg_spd:.3f} m/s ({500/avg_spd:.0f} /500m)\n")
        max_spd = session_info.get('enhanced_max_speed')
        if max_spd and max_spd > 0:
            fh.write(f"Max speed: {max_spd:.3f} m/s ({500/max_spd:.0f} /500m)\n")
        fh.write(f"Avg HR: {session_info.get('avg_heart_rate', '?')} bpm\n")
        fh.write(f"Max HR: {session_info.get('max_heart_rate', '?')} bpm\n")
        fh.write(f"Calories: {session_info.get('total_calories', '?')} kcal\n")
        fh.write(f"Avg temp: {session_info.get('avg_temperature', '?')} C\n")

        # Accel statistics
        valid_accel = [(r[5], r[6], r[7]) for r in accel_rows
                       if r[5] is not None and r[6] is not None]
        if valid_accel:
            maxes = [a[0] for a in valid_accel]
            means = [a[1] for a in valid_accel]
            emas = [a[2] for a in valid_accel if a[2] is not None]
            fh.write(f"\nAccelerometer (lin_mag, {len(valid_accel)} samples):\n")
            fh.write(f"  lin_mag_max: min={min(maxes)} max={max(maxes)} avg={sum(maxes)/len(maxes):.0f} mG\n")
            fh.write(f"  lin_mag_mean: min={min(means)} max={max(means)} avg={sum(means)/len(means):.0f} mG\n")
            if emas:
                fh.write(f"  lin_mag_ema: min={min(emas)} max={max(emas)} avg={sum(emas)/len(emas):.0f} mG\n")

        # Stroke statistics
        valid_spm = [r[1] for r in stroke_rows if r[1] is not None and r[1] > 0]
        valid_dps = [r[2] for r in stroke_rows if r[2] is not None and r[2] > 0]
        if valid_spm:
            fh.write(f"\nStroke rate ({len(valid_spm)} valid samples):\n")
            fh.write(f"  min={min(valid_spm)} max={max(valid_spm)} avg={sum(valid_spm)/len(valid_spm):.1f} spm\n")
        if valid_dps:
            fh.write(f"Distance per stroke ({len(valid_dps)} valid samples):\n")
            fh.write(f"  min={min(valid_dps):.1f} max={max(valid_dps):.1f} avg={sum(valid_dps)/len(valid_dps):.1f} m\n")

    print(f"  summary.txt")

    # Gnuplot scripts
    write_gps_plot(outdir)
    write_accel_plot(outdir)
    write_strokes_plot(outdir)
    write_plot_all(outdir)

def write_gps_plot(outdir):
    path = os.path.join(outdir, 'plot_gps.gp')
    with open(path, 'w') as f:
        f.write("""# GPS track and speed
# Interactive: gnuplot -e "interactive=1" plot_gps.gp

if (!exists("interactive")) interactive = 0

if (interactive) {
    set terminal qt size 1200,1600 font "sans,11" persist
} else {
    set terminal pngcairo size 1200,1600 font "sans,11"
    set output 'gps.png'
}
set multiplot layout 4,1

# Track
set title "GPS Track"
set xlabel "Longitude"
set ylabel "Latitude"
set size ratio -1
plot 'gps.tsv' using 3:2 with lines lw 1.5 lc rgb '#1565c0' notitle
unset size

# Speed
set title "Speed (m/s)"
set xlabel "Time (min)"
set ylabel "m/s"
plot 'gps.tsv' using ($1/60):4 with lines lw 1 lc rgb '#e65100' title 'speed'

# Split /500m
set title "Split /500m"
set xlabel "Time (min)"
set ylabel "seconds /500m"
set yrange [60:400]
plot 'gps.tsv' using ($1/60):($8 < 500 ? $8 : NaN) with lines lw 1 lc rgb '#2e7d32' title 'split'
set yrange [*:*]

# Heart rate
set title "Heart Rate"
set xlabel "Time (min)"
set ylabel "bpm"
plot 'gps.tsv' using ($1/60):6 with lines lw 1 lc rgb '#c62828' title 'HR'

unset multiplot
""")
    print(f"  plot_gps.gp")

def write_accel_plot(outdir):
    path = os.path.join(outdir, 'plot_accel.gp')
    with open(path, 'w') as f:
        f.write("""# Accelerometer data
# Usage: gnuplot plot_accel.gp
# Zoom: gnuplot -e "t_start=5; t_end=8" plot_accel.gp
# Interactive: gnuplot -e "interactive=1" plot_accel.gp
# Interactive+zoom: gnuplot -e "interactive=1; t_start=5; t_end=8" plot_accel.gp

if (!exists("t_start")) t_start = 0
if (!exists("t_end")) t_end = 100
if (!exists("interactive")) interactive = 0

if (interactive) {
    set terminal qt size 1200,1600 font "sans,11" persist
} else {
    set terminal pngcairo size 1200,1600 font "sans,11"
    set output 'accel.png'
}
set multiplot layout 4,1
set xrange [t_start:t_end]

# Raw axes
set title sprintf("Raw Accelerometer (1s avg) [%.0f-%.0f min]", t_start, t_end)
set xlabel "Time (min)"
set ylabel "mG"
plot 'accel.tsv' using ($1/60):2 with lines lw 1 lc rgb '#c62828' title 'X', \\
     'accel.tsv' using ($1/60):3 with lines lw 1 lc rgb '#2e7d32' title 'Y', \\
     'accel.tsv' using ($1/60):4 with lines lw 1 lc rgb '#1565c0' title 'Z'

# Linear magnitude min/max envelope
set title "Linear Accel Magnitude (gravity subtracted)"
set xlabel "Time (min)"
set ylabel "mG"
plot 'accel.tsv' using ($1/60):5 with lines lw 0.5 lc rgb '#90caf9' title 'min', \\
     'accel.tsv' using ($1/60):6 with lines lw 0.5 lc rgb '#ef9a9a' title 'max', \\
     'accel.tsv' using ($1/60):7 with lines lw 1.5 lc rgb '#1565c0' title 'mean'

# EMA (what stroke detection uses)
set title "Linear Accel EMA (stroke detection signal)"
set xlabel "Time (min)"
set ylabel "mG"
set arrow from graph 0,first 200 to graph 1,first 200 nohead lc rgb '#888888' dt 2
set label "threshold=200" at graph 0.02,first 220 font ",9" tc rgb '#888888'
plot 'accel.tsv' using ($1/60):8 with lines lw 1.5 lc rgb '#e65100' title 'EMA'
unset arrow
unset label

# Magnitude range (max - min) per second
set title "Accel Range (max-min per second)"
set xlabel "Time (min)"
set ylabel "mG"
plot 'accel.tsv' using ($1/60):($6-$5) with lines lw 1 lc rgb '#7b1fa2' title 'range'

unset multiplot
""")
    print(f"  plot_accel.gp")

def write_strokes_plot(outdir):
    path = os.path.join(outdir, 'plot_strokes.gp')
    with open(path, 'w') as f:
        f.write("""# Stroke data
# Interactive: gnuplot -e "interactive=1" plot_strokes.gp

if (!exists("interactive")) interactive = 0

if (interactive) {
    set terminal qt size 1200,800 font "sans,11" persist
} else {
    set terminal pngcairo size 1200,800 font "sans,11"
    set output 'strokes.png'
}
set multiplot layout 2,1

# Stroke rate
set title "Stroke Rate"
set xlabel "Time (min)"
set ylabel "spm"
plot 'strokes.tsv' using ($1/60):($2 > 0 ? $2 : NaN) with linespoints pt 7 ps 0.3 lw 1 lc rgb '#1565c0' title 'SPM'

# Distance per stroke
set title "Distance Per Stroke"
set xlabel "Time (min)"
set ylabel "m/stroke"
plot 'strokes.tsv' using ($1/60):($3 > 0 ? $3 : NaN) with linespoints pt 7 ps 0.3 lw 1 lc rgb '#2e7d32' title 'DPS'

unset multiplot
""")
    print(f"  plot_strokes.gp")

def write_plot_all(outdir):
    path = os.path.join(outdir, 'plot_all.sh')
    with open(path, 'w') as f:
        f.write("""#!/bin/bash
# Usage: ./plot_all.sh              # PNG output
#        ./plot_all.sh -i           # interactive (qt window)
#        ./plot_all.sh -i -e "t_start=5; t_end=8"  # interactive + zoom
cd "$(dirname "$0")"
MODE=""
EXTRA=""
while [ $# -gt 0 ]; do
    case "$1" in
        -i|--interactive) MODE="interactive=1"; shift ;;
        -e) EXTRA="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done
VARS="${MODE:+$MODE; }${EXTRA}"
for gp in plot_*.gp; do
    echo "Plotting $gp ${VARS:+($VARS)}"
    if [ -n "$VARS" ]; then
        gnuplot -e "$VARS" "$gp"
    else
        gnuplot "$gp"
    fi
done
if [ -z "$MODE" ]; then
    echo "Done. Output: *.png"
    ls -la *.png
fi
""")
    os.chmod(path, 0o755)
    print(f"  plot_all.sh")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file.fit>")
        sys.exit(1)
    extract(sys.argv[1])
