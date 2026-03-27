if (!exists("interactive")) interactive = 0
if (interactive) { set terminal qt size 1400,1000 font "sans,11" persist
} else { set terminal pngcairo size 1400,1000 font "sans,11"
  set output "app_view_prototype.png"
}

set multiplot layout 3,2 title "App View (exact StrokeDetector logic) + 1s context"

set title 'gentle: app=30samp, catch=-128, peak=287, zero@+1' font ',9'
set xrange [99:179]
set yrange [-181:330]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set obj 10 rect from 99,-181 to 179,330 fc rgb '#e0e0e0' fs solid behind
set obj 11 rect from 124,-181 to 154,330 fc rgb '#ffffff' fs solid behind
set obj 12 rect from 124,-181 to 127,330 fc rgb '#ffebee' fs solid behind
set obj 13 rect from 127,-181 to 148,330 fc rgb '#e8f5e9' fs solid behind
set obj 14 rect from 148,-181 to 154,330 fc rgb '#fff9c4' fs solid behind
set arrow 1 from 99,0 to 179,0 nohead lc rgb '#aaa' dt 2
set arrow 2 from 124,-181 to 124,330 nohead lc rgb '#000' lw 2 dt 2
set arrow 3 from 154,-181 to 154,330 nohead lc rgb '#000' lw 2 dt 2
set arrow 4 from 149,-181 to 149,330 nohead lc rgb '#ff6f00' lw 1 dt 3
set label 1 '1s' at 111.5,297 center font ',7' tc rgb '#888'
set label 2 '1s' at 166.5,297 center font ',7' tc rgb '#888'
set label 3 'DRIVE' at 137.5,280 center font ',9' tc rgb '#2e7d32'
set label 4 'tail' at 151.0,280 center font ',7' tc rgb '#ff6f00'
set label 5 '62%' at 137.5,132 center font ',13' tc rgb '#000'
set label 6 'dV 0.14' at 153,-54 right font ',9' tc rgb '#333'
plot 'gentle_3stroke.tsv' u ($1>=99&&$1<=179?$1:1/0):2 w lines lw 1 lc rgb '#bbb' not, \
     'gentle_3stroke.tsv' u ($1>=124&&$1<=154?$1:1/0):2 w lines lw 2 lc rgb '#2196F3' not, \
     'gentle_3stroke.tsv' u ($1>=124&&$1<=154&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.25 not, \
     'gentle_3stroke.tsv' u ($1>=124&&$1<=154&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.15 not
unset for [i=10:14] obj i
unset for [i=1:4] arrow i
unset for [i=1:6] label i

set title 'light: app=33samp, catch=-391, peak=309, zero@+1' font ',9'
set xrange [97:180]
set yrange [-332:355]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set obj 10 rect from 97,-332 to 180,355 fc rgb '#e0e0e0' fs solid behind
set obj 11 rect from 122,-332 to 155,355 fc rgb '#ffffff' fs solid behind
set obj 12 rect from 122,-332 to 127,355 fc rgb '#ffebee' fs solid behind
set obj 13 rect from 127,-332 to 149,355 fc rgb '#e8f5e9' fs solid behind
set obj 14 rect from 149,-332 to 155,355 fc rgb '#fff9c4' fs solid behind
set arrow 1 from 97,0 to 180,0 nohead lc rgb '#aaa' dt 2
set arrow 2 from 122,-332 to 122,355 nohead lc rgb '#000' lw 2 dt 2
set arrow 3 from 155,-332 to 155,355 nohead lc rgb '#000' lw 2 dt 2
set arrow 4 from 150,-332 to 150,355 nohead lc rgb '#ff6f00' lw 1 dt 3
set label 1 '1s' at 109.5,319 center font ',7' tc rgb '#888'
set label 2 '1s' at 167.5,319 center font ',7' tc rgb '#888'
set label 3 'DRIVE' at 138.0,302 center font ',9' tc rgb '#2e7d32'
set label 4 'tail' at 152.0,302 center font ',7' tc rgb '#ff6f00'
set label 5 '62%' at 138.0,142 center font ',13' tc rgb '#000'
set label 6 'dV 0.14' at 154,-99 right font ',9' tc rgb '#333'
plot 'light_3stroke.tsv' u ($1>=97&&$1<=180?$1:1/0):2 w lines lw 1 lc rgb '#bbb' not, \
     'light_3stroke.tsv' u ($1>=122&&$1<=155?$1:1/0):2 w lines lw 2 lc rgb '#4CAF50' not, \
     'light_3stroke.tsv' u ($1>=122&&$1<=155&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.25 not, \
     'light_3stroke.tsv' u ($1>=122&&$1<=155&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.15 not
unset for [i=10:14] obj i
unset for [i=1:4] arrow i
unset for [i=1:6] label i

set title 'steady: app=63samp, catch=-123, peak=327, zero@+1' font ',9'
set xrange [69:182]
set yrange [-206:376]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set obj 10 rect from 69,-206 to 182,376 fc rgb '#e0e0e0' fs solid behind
set obj 11 rect from 94,-206 to 157,376 fc rgb '#ffffff' fs solid behind
set obj 12 rect from 94,-206 to 127,376 fc rgb '#ffebee' fs solid behind
set obj 13 rect from 127,-206 to 151,376 fc rgb '#e8f5e9' fs solid behind
set obj 14 rect from 151,-206 to 157,376 fc rgb '#fff9c4' fs solid behind
set arrow 1 from 69,0 to 182,0 nohead lc rgb '#aaa' dt 2
set arrow 2 from 94,-206 to 94,376 nohead lc rgb '#000' lw 2 dt 2
set arrow 3 from 157,-206 to 157,376 nohead lc rgb '#000' lw 2 dt 2
set arrow 4 from 152,-206 to 152,376 nohead lc rgb '#ff6f00' lw 1 dt 3
set label 1 '1s' at 81.5,338 center font ',7' tc rgb '#888'
set label 2 '1s' at 169.5,338 center font ',7' tc rgb '#888'
set label 3 'DRIVE' at 139.0,319 center font ',9' tc rgb '#2e7d32'
set label 4 'tail' at 154.0,319 center font ',7' tc rgb '#ff6f00'
set label 5 '62%' at 139.0,150 center font ',13' tc rgb '#000'
set label 6 'dV 0.14' at 156,-62 right font ',9' tc rgb '#333'
plot 'steady_3stroke.tsv' u ($1>=69&&$1<=182?$1:1/0):2 w lines lw 1 lc rgb '#bbb' not, \
     'steady_3stroke.tsv' u ($1>=94&&$1<=157?$1:1/0):2 w lines lw 2 lc rgb '#FF9800' not, \
     'steady_3stroke.tsv' u ($1>=94&&$1<=157&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.25 not, \
     'steady_3stroke.tsv' u ($1>=94&&$1<=157&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.15 not
unset for [i=10:14] obj i
unset for [i=1:4] arrow i
unset for [i=1:6] label i

set title 'strong: app=34samp, catch=-153, peak=372, zero@+1' font ',9'
set xrange [223:307]
set yrange [-235:427]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set obj 10 rect from 223,-235 to 307,427 fc rgb '#e0e0e0' fs solid behind
set obj 11 rect from 248,-235 to 282,427 fc rgb '#ffffff' fs solid behind
set obj 12 rect from 248,-235 to 251,427 fc rgb '#ffebee' fs solid behind
set obj 13 rect from 251,-235 to 276,427 fc rgb '#e8f5e9' fs solid behind
set obj 14 rect from 276,-235 to 282,427 fc rgb '#fff9c4' fs solid behind
set arrow 1 from 223,0 to 307,0 nohead lc rgb '#aaa' dt 2
set arrow 2 from 248,-235 to 248,427 nohead lc rgb '#000' lw 2 dt 2
set arrow 3 from 282,-235 to 282,427 nohead lc rgb '#000' lw 2 dt 2
set arrow 4 from 277,-235 to 277,427 nohead lc rgb '#ff6f00' lw 1 dt 3
set label 1 '1s' at 235.5,385 center font ',7' tc rgb '#888'
set label 2 '1s' at 294.5,385 center font ',7' tc rgb '#888'
set label 3 'DRIVE' at 263.5,363 center font ',9' tc rgb '#2e7d32'
set label 4 'tail' at 279.0,363 center font ',7' tc rgb '#ff6f00'
set label 5 '62%' at 263.5,171 center font ',13' tc rgb '#000'
set label 6 'dV 0.14' at 281,-70 right font ',9' tc rgb '#333'
plot 'strong_3stroke.tsv' u ($1>=223&&$1<=307?$1:1/0):2 w lines lw 1 lc rgb '#bbb' not, \
     'strong_3stroke.tsv' u ($1>=248&&$1<=282?$1:1/0):2 w lines lw 2 lc rgb '#F44336' not, \
     'strong_3stroke.tsv' u ($1>=248&&$1<=282&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.25 not, \
     'strong_3stroke.tsv' u ($1>=248&&$1<=282&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.15 not
unset for [i=10:14] obj i
unset for [i=1:4] arrow i
unset for [i=1:6] label i

set title 'power: app=33samp, catch=-760, peak=435, zero@+1' font ',9'
set xrange [416:499]
set yrange [-646:500]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set obj 10 rect from 416,-646 to 499,500 fc rgb '#e0e0e0' fs solid behind
set obj 11 rect from 441,-646 to 474,500 fc rgb '#ffffff' fs solid behind
set obj 12 rect from 441,-646 to 449,500 fc rgb '#ffebee' fs solid behind
set obj 13 rect from 449,-646 to 468,500 fc rgb '#e8f5e9' fs solid behind
set obj 14 rect from 468,-646 to 474,500 fc rgb '#fff9c4' fs solid behind
set arrow 1 from 416,0 to 499,0 nohead lc rgb '#aaa' dt 2
set arrow 2 from 441,-646 to 441,500 nohead lc rgb '#000' lw 2 dt 2
set arrow 3 from 474,-646 to 474,500 nohead lc rgb '#000' lw 2 dt 2
set arrow 4 from 469,-646 to 469,500 nohead lc rgb '#ff6f00' lw 1 dt 3
set label 1 '1s' at 428.5,450 center font ',7' tc rgb '#888'
set label 2 '1s' at 486.5,450 center font ',7' tc rgb '#888'
set label 3 'DRIVE' at 458.5,425 center font ',9' tc rgb '#2e7d32'
set label 4 'tail' at 471.0,425 center font ',7' tc rgb '#ff6f00'
set label 5 '62%' at 458.5,200 center font ',13' tc rgb '#000'
set label 6 'dV 0.14' at 473,-193 right font ',9' tc rgb '#333'
plot 'power_3stroke.tsv' u ($1>=416&&$1<=499?$1:1/0):2 w lines lw 1 lc rgb '#bbb' not, \
     'power_3stroke.tsv' u ($1>=441&&$1<=474?$1:1/0):2 w lines lw 2 lc rgb '#9C27B0' not, \
     'power_3stroke.tsv' u ($1>=441&&$1<=474&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.25 not, \
     'power_3stroke.tsv' u ($1>=441&&$1<=474&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.15 not
unset for [i=10:14] obj i
unset for [i=1:4] arrow i
unset for [i=1:6] label i

set title 'All Main Strokes Aligned at Peak'
set border
set xtics
set ytics
set xlabel 'Samples from peak'
set ylabel 'mG'
set xrange [-40:30]
set yrange [*:*]
set arrow from graph 0,first 0 to graph 1,first 0 nohead lc rgb '#888' dt 2
set arrow from first 0,graph 0 to first 0,graph 1 nohead lc rgb '#000' dt 3
plot 'gentle_3stroke.tsv' u ($1>=124&&$1<=154?$1-148:1/0):2 w lines lw 2 lc rgb '#2196F3' t 'gentle', \
     'light_3stroke.tsv' u ($1>=122&&$1<=155?$1-149:1/0):2 w lines lw 2 lc rgb '#4CAF50' t 'light', \
     'steady_3stroke.tsv' u ($1>=94&&$1<=157?$1-143:1/0):2 w lines lw 2 lc rgb '#FF9800' t 'steady', \
     'strong_3stroke.tsv' u ($1>=248&&$1<=282?$1-273:1/0):2 w lines lw 2 lc rgb '#F44336' t 'strong', \
     'power_3stroke.tsv' u ($1>=441&&$1<=474?$1-453:1/0):2 w lines lw 2 lc rgb '#9C27B0' t 'power'
unset arrow

unset multiplot
