if (!exists("interactive")) interactive = 0
if (interactive) { set terminal qt size 1400,1000 font 'sans,11' persist
} else { set terminal pngcairo size 1400,1000 font 'sans,11'
  set output '3strokes_comparison.png'
}

set multiplot layout 3,2 title '3-Stroke Windows with Phase Boundaries'

set title 'gentle: peak=287, catch=-128, split=2:48'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
set arrow from first 75,graph 0 to first 75,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 149,graph 0 to first 149,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 126,graph 0 to first 126,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 148,graph 0 to first 148,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 126,graph 0 to first 126,graph 1 nohead lc rgb '#f00' dt 3
set label 'PREV' at first 37.5,229.60000000000002 center font ',8' tc rgb '#888'
set label 'MAIN' at first 112.0,229.60000000000002 center font ',9' tc rgb '#000'
set label 'NEXT' at first 275.0,229.60000000000002 center font ',8' tc rgb '#888'
set label 'catch' at first 126,-102.4 center font ',8' tc rgb '#f00'
set label 'drive' at first 137.0,143.5 center font ',8' tc rgb '#0a0'
plot 'gentle_3stroke.tsv' u 1:2 w lines lw 1.5 lc rgb '#2196F3' t 'gentle', \
     'gentle_3stroke.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#2196F3' fs transparent solid 0.15 not, \
     'gentle_3stroke.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.08 not
unset arrow
unset label

set title 'light: peak=309, catch=-391, split=2:51'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
set arrow from first 75,graph 0 to first 75,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 150,graph 0 to first 150,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 126,graph 0 to first 126,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 149,graph 0 to first 149,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 124,graph 0 to first 124,graph 1 nohead lc rgb '#f00' dt 3
set label 'PREV' at first 37.5,247.20000000000002 center font ',8' tc rgb '#888'
set label 'MAIN' at first 112.5,247.20000000000002 center font ',9' tc rgb '#000'
set label 'NEXT' at first 188.5,247.20000000000002 center font ',8' tc rgb '#888'
set label 'catch' at first 124,-312.8 center font ',8' tc rgb '#f00'
set label 'drive' at first 137.5,154.5 center font ',8' tc rgb '#0a0'
plot 'light_3stroke.tsv' u 1:2 w lines lw 1.5 lc rgb '#4CAF50' t 'light', \
     'light_3stroke.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.15 not, \
     'light_3stroke.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.08 not
unset arrow
unset label

set title 'steady: peak=327, catch=-123, split=2:38'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
set arrow from first 75,graph 0 to first 75,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 151,graph 0 to first 151,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 126,graph 0 to first 126,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 143,graph 0 to first 143,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 96,graph 0 to first 96,graph 1 nohead lc rgb '#f00' dt 3
set label 'PREV' at first 37.5,261.6 center font ',8' tc rgb '#888'
set label 'MAIN' at first 113.0,261.6 center font ',9' tc rgb '#000'
set label 'NEXT' at first 188.0,261.6 center font ',8' tc rgb '#888'
set label 'catch' at first 96,-98.4 center font ',8' tc rgb '#f00'
set label 'drive' at first 134.5,163.5 center font ',8' tc rgb '#0a0'
plot 'steady_3stroke.tsv' u 1:2 w lines lw 1.5 lc rgb '#FF9800' t 'steady', \
     'steady_3stroke.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#FF9800' fs transparent solid 0.15 not, \
     'steady_3stroke.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.08 not
unset arrow
unset label

set title 'strong: peak=372, catch=-153, split=2:37'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
set arrow from first 201,graph 0 to first 201,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 278,graph 0 to first 278,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 250,graph 0 to first 250,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 277,graph 0 to first 277,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 250,graph 0 to first 250,graph 1 nohead lc rgb '#f00' dt 3
set label 'PREV' at first 100.5,297.6 center font ',8' tc rgb '#888'
set label 'MAIN' at first 239.5,297.6 center font ',9' tc rgb '#000'
set label 'NEXT' at first 312.0,297.6 center font ',8' tc rgb '#888'
set label 'catch' at first 250,-122.4 center font ',8' tc rgb '#f00'
set label 'drive' at first 263.5,186.0 center font ',8' tc rgb '#0a0'
plot 'strong_3stroke.tsv' u 1:2 w lines lw 1.5 lc rgb '#F44336' t 'strong', \
     'strong_3stroke.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.15 not, \
     'strong_3stroke.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.08 not
unset arrow
unset label

set title 'power: peak=435, catch=-760, split=2:47'
set xlabel 'Sample (25Hz)'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
set arrow from first 388,graph 0 to first 388,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 469,graph 0 to first 469,graph 1 nohead lc rgb '#000' lw 2
set arrow from first 448,graph 0 to first 448,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 453,graph 0 to first 453,graph 1 nohead lc rgb '#0a0' dt 3
set arrow from first 443,graph 0 to first 443,graph 1 nohead lc rgb '#f00' dt 3
set label 'PREV' at first 194.0,348.0 center font ',8' tc rgb '#888'
set label 'MAIN' at first 428.5,348.0 center font ',9' tc rgb '#000'
set label 'NEXT' at first 547.0,348.0 center font ',8' tc rgb '#888'
set label 'catch' at first 443,-608.0 center font ',8' tc rgb '#f00'
set label 'drive' at first 450.5,217.5 center font ',8' tc rgb '#0a0'
plot 'power_3stroke.tsv' u 1:2 w lines lw 1.5 lc rgb '#9C27B0' t 'power', \
     'power_3stroke.tsv' u 1:($2>0?$2:1/0) w filledcurves y=0 lc rgb '#9C27B0' fs transparent solid 0.15 not, \
     'power_3stroke.tsv' u 1:($2<0?$2:1/0) w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.08 not
unset arrow
unset label

set title 'Main Strokes Aligned (at drive peak)'
set xlabel 'Samples relative to peak'
set ylabel 'mG'
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
set arrow from first 0,graph 0 to first 0,graph 1 nohead lc rgb '#000' dt 3
plot 'gentle_3stroke.tsv' u ($1>=75 && $1<=149 ? $1-148 : 1/0):2 w lines lw 2 lc rgb '#2196F3' t 'gentle', \
     'light_3stroke.tsv' u ($1>=75 && $1<=150 ? $1-149 : 1/0):2 w lines lw 2 lc rgb '#4CAF50' t 'light', \
     'steady_3stroke.tsv' u ($1>=75 && $1<=151 ? $1-143 : 1/0):2 w lines lw 2 lc rgb '#FF9800' t 'steady', \
     'strong_3stroke.tsv' u ($1>=201 && $1<=278 ? $1-273 : 1/0):2 w lines lw 2 lc rgb '#F44336' t 'strong', \
     'power_3stroke.tsv' u ($1>=388 && $1<=469 ? $1-453 : 1/0):2 w lines lw 2 lc rgb '#9C27B0' t 'power'
unset arrow

unset multiplot
