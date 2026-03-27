if (!exists("interactive")) interactive = 0
if (interactive) {
  set terminal qt size 1200,1600 font "sans,11" persist
} else {
  set terminal pngcairo size 1200,1600 font "sans,11"
  set output "display_prototype.png"
}

set multiplot layout 5,2 title "Left: symmetric Y (current) | Right: 70/30 asymmetric with clip"

set title 'gentle -- symmetric' font ',10'
set xrange [124:154]
set yrange [-134:301]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 124,0 to 154,0 nohead lc rgb '#ccc' dt 2
plot 'gentle_3stroke.tsv' u ($1>=124&&$1<=154&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'gentle_3stroke.tsv' u ($1>=124&&$1<=154&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'gentle_3stroke.tsv' u ($1>=124&&$1<=154?$1:1/0):2 w lines lw 2 lc rgb '#1565C0' not
unset arrow

set title 'gentle -- 70/30' font ',10'
set xrange [124:154]
set yrange [-129:301]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 124,0 to 154,0 nohead lc rgb '#ccc' dt 2
set label 1 '62%' at 139.0,210 center font ',14' tc rgb '#000'
set label 2 '0.14' at 153,-64 right font ',11' tc rgb '#333'
plot 'gentle_3stroke.tsv' u ($1>=124&&$1<=154&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'gentle_3stroke.tsv' u ($1>=124&&$1<=154&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'gentle_3stroke.tsv' u ($1>=124&&$1<=154?$1:1/0):($2<-129?-129:$2) w lines lw 2 lc rgb '#1565C0' not
unset arrow
unset label 1
unset label 2
unset label 3

set title 'light -- symmetric' font ',10'
set xrange [122:155]
set yrange [-410:324]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 122,0 to 155,0 nohead lc rgb '#ccc' dt 2
plot 'light_3stroke.tsv' u ($1>=122&&$1<=155&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'light_3stroke.tsv' u ($1>=122&&$1<=155&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'light_3stroke.tsv' u ($1>=122&&$1<=155?$1:1/0):2 w lines lw 2 lc rgb '#1565C0' not
unset arrow

set title 'light -- 70/30 CLIP 2.8x' font ',10'
set xrange [122:155]
set yrange [-139:324]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 122,0 to 155,0 nohead lc rgb '#ccc' dt 2
set label 1 '62%' at 138.5,227 center font ',14' tc rgb '#000'
set label 2 '0.14' at 154,-69 right font ',11' tc rgb '#333'
set label 3 'clip' at 123,-125 left font ',7' tc rgb '#FF6F00'
plot 'light_3stroke.tsv' u ($1>=122&&$1<=155&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'light_3stroke.tsv' u ($1>=122&&$1<=155&&$2<0&&$2>=-139?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'light_3stroke.tsv' u ($1>=122&&$1<=155&&$2<-139?$1:1/0):(-139) w filledcurves y=0 lc rgb '#FF6F00' fs transparent solid 0.5 not, 'light_3stroke.tsv' u ($1>=122&&$1<=155?$1:1/0):($2<-139?-139:$2) w lines lw 2 lc rgb '#1565C0' not
unset arrow
unset label 1
unset label 2
unset label 3

set title 'steady -- symmetric' font ',10'
set xrange [94:157]
set yrange [-129:343]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 94,0 to 157,0 nohead lc rgb '#ccc' dt 2
plot 'steady_3stroke.tsv' u ($1>=94&&$1<=157&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'steady_3stroke.tsv' u ($1>=94&&$1<=157&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'steady_3stroke.tsv' u ($1>=94&&$1<=157?$1:1/0):2 w lines lw 2 lc rgb '#1565C0' not
unset arrow

set title 'steady -- 70/30' font ',10'
set xrange [94:157]
set yrange [-147:343]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 94,0 to 157,0 nohead lc rgb '#ccc' dt 2
set label 1 '62%' at 125.5,240 center font ',14' tc rgb '#000'
set label 2 '0.14' at 156,-73 right font ',11' tc rgb '#333'
plot 'steady_3stroke.tsv' u ($1>=94&&$1<=157&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'steady_3stroke.tsv' u ($1>=94&&$1<=157&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'steady_3stroke.tsv' u ($1>=94&&$1<=157?$1:1/0):($2<-147?-147:$2) w lines lw 2 lc rgb '#1565C0' not
unset arrow
unset label 1
unset label 2
unset label 3

set title 'strong -- symmetric' font ',10'
set xrange [248:282]
set yrange [-160:390]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 248,0 to 282,0 nohead lc rgb '#ccc' dt 2
plot 'strong_3stroke.tsv' u ($1>=248&&$1<=282&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'strong_3stroke.tsv' u ($1>=248&&$1<=282&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'strong_3stroke.tsv' u ($1>=248&&$1<=282?$1:1/0):2 w lines lw 2 lc rgb '#1565C0' not
unset arrow

set title 'strong -- 70/30' font ',10'
set xrange [248:282]
set yrange [-167:390]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 248,0 to 282,0 nohead lc rgb '#ccc' dt 2
set label 1 '62%' at 265.0,273 center font ',14' tc rgb '#000'
set label 2 '0.14' at 281,-83 right font ',11' tc rgb '#333'
plot 'strong_3stroke.tsv' u ($1>=248&&$1<=282&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'strong_3stroke.tsv' u ($1>=248&&$1<=282&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'strong_3stroke.tsv' u ($1>=248&&$1<=282?$1:1/0):($2<-167?-167:$2) w lines lw 2 lc rgb '#1565C0' not
unset arrow
unset label 1
unset label 2
unset label 3

set title 'power -- symmetric' font ',10'
set xrange [441:474]
set yrange [-798:456]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 441,0 to 474,0 nohead lc rgb '#ccc' dt 2
plot 'power_3stroke.tsv' u ($1>=441&&$1<=474&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'power_3stroke.tsv' u ($1>=441&&$1<=474&&$2<0?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'power_3stroke.tsv' u ($1>=441&&$1<=474?$1:1/0):2 w lines lw 2 lc rgb '#1565C0' not
unset arrow

set title 'power -- 70/30 CLIP 3.9x' font ',10'
set xrange [441:474]
set yrange [-195:456]
set border 0
unset xtics
unset ytics
unset xlabel
unset ylabel
set arrow from 441,0 to 474,0 nohead lc rgb '#ccc' dt 2
set label 1 '62%' at 457.5,319 center font ',14' tc rgb '#000'
set label 2 '0.14' at 473,-97 right font ',11' tc rgb '#333'
set label 3 'clip' at 442,-176 left font ',7' tc rgb '#FF6F00'
plot 'power_3stroke.tsv' u ($1>=441&&$1<=474&&$2>0?$1:1/0):2 w filledcurves y=0 lc rgb '#4CAF50' fs transparent solid 0.3 not, 'power_3stroke.tsv' u ($1>=441&&$1<=474&&$2<0&&$2>=-195?$1:1/0):2 w filledcurves y=0 lc rgb '#F44336' fs transparent solid 0.2 not, 'power_3stroke.tsv' u ($1>=441&&$1<=474&&$2<-195?$1:1/0):(-195) w filledcurves y=0 lc rgb '#FF6F00' fs transparent solid 0.5 not, 'power_3stroke.tsv' u ($1>=441&&$1<=474?$1:1/0):($2<-195?-195:$2) w lines lw 2 lc rgb '#1565C0' not
unset arrow
unset label 1
unset label 2
unset label 3

unset multiplot
