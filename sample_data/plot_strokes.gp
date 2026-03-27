if (!exists("interactive")) interactive = 0
if (interactive) { set terminal qt size 1200,900 font 'sans,11' persist
} else { set terminal pngcairo size 1200,900 font 'sans,11'
  set output 'strokes_comparison.png'
}

set multiplot layout 3,2 title 'Stroke Types -- On-Water 2026-03-27'

set title 'gentle: peak=287, catch=-128, split=2:48'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
plot 'gentle_peak287_catch-128.tsv' u 1:2 w lines lw 2 lc rgb '#2196F3' t 'gentle', \
     'gentle_peak287_catch-128.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#2196F3' fs transparent solid 0.2 not, \
     'gentle_peak287_catch-128.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.1 not
unset arrow

set title 'light: peak=309, catch=-391, split=2:51'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
plot 'light_peak309_catch-391.tsv' u 1:2 w lines lw 2 lc rgb '#4CAF50' t 'light', \
     'light_peak309_catch-391.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.2 not, \
     'light_peak309_catch-391.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.1 not
unset arrow

set title 'steady: peak=327, catch=-123, split=2:38'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
plot 'steady_peak327_catch-123.tsv' u 1:2 w lines lw 2 lc rgb '#FF9800' t 'steady', \
     'steady_peak327_catch-123.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#FF9800' fs transparent solid 0.2 not, \
     'steady_peak327_catch-123.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.1 not
unset arrow

set title 'strong: peak=372, catch=-153, split=2:37'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
plot 'strong_peak372_catch-153.tsv' u 1:2 w lines lw 2 lc rgb '#F44336' t 'strong', \
     'strong_peak372_catch-153.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, \
     'strong_peak372_catch-153.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.1 not
unset arrow

set title 'power: peak=435, catch=-760, split=2:47'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
plot 'power_peak435_catch-760.tsv' u 1:2 w lines lw 2 lc rgb '#9C27B0' t 'power', \
     'power_peak435_catch-760.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#9C27B0' fs transparent solid 0.2 not, \
     'power_peak435_catch-760.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.1 not
unset arrow

set title 'All Types Overlaid'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
plot 'gentle_peak287_catch-128.tsv' u 1:2 w lines lw 2 lc rgb '#2196F3' t 'gentle', \
     'light_peak309_catch-391.tsv' u 1:2 w lines lw 2 lc rgb '#4CAF50' t 'light', \
     'steady_peak327_catch-123.tsv' u 1:2 w lines lw 2 lc rgb '#FF9800' t 'steady', \
     'strong_peak372_catch-153.tsv' u 1:2 w lines lw 2 lc rgb '#F44336' t 'strong', \
     'power_peak435_catch-760.tsv' u 1:2 w lines lw 2 lc rgb '#9C27B0' t 'power'
unset arrow

unset multiplot
