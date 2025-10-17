set terminal postscript enhanced eps color "Times" 18

set style line 11 dt 2 lw 2 lc rgbcolor "black"        pt 4 ps 1
set style line 21 dt 4 lw 1 lc rgbcolor "blue"         pt 6 ps 1

set format x "%1g"
set format y "%1.1e"

set key width 0

set grid  xtics lw 1 dt 4 lc rgbcolor "gray"
set grid  ytics lw 1 dt 4 lc rgbcolor "gray"
set grid mxtics lw 1 dt 4 lc rgbcolor "gray"
set grid mytics lw 1 dt 4 lc rgbcolor "gray"

set title "california, 120 days"
set xlabel "Days" font "Times,20"

set output "NumInfections_ca_noair.Lassen.eps"
set ylabel "Number of Infections" font "Times,16"
set key top right
set xrange [0:120]
plot \
'../baselines/ca.noair.b_development.blueos_3_ppc64le_ib_p9/output.dat' u 1:3 w l ls 11 t "Baseline", \
'../tests/ca.noair.b_development.blueos_3_ppc64le_ib_p9/output.dat' u 1:3 w p ls 21 t "Current", \

set output "NumDeaths_ca_noair.Lassen.eps"
set ylabel "Number of Deaths" font "Times,16"
set key top left
set xrange [0:120]
plot \
'../baselines/ca.noair.b_development.blueos_3_ppc64le_ib_p9/output.dat' u 1:5 w l ls 11 t "Baseline", \
'../tests/ca.noair.b_development.blueos_3_ppc64le_ib_p9/output.dat' u 1:5 w p ls 21 t "Current", \

set output "NumHospitalizations_ca_noair.Lassen.eps"
set ylabel "Number of Hospitalizations" font "Times,16"
set key top right
set xrange [0:120]
plot \
'../baselines/ca.noair.b_development.blueos_3_ppc64le_ib_p9/output.dat' u 1:6 w l ls 11 t "Baseline", \
'../tests/ca.noair.b_development.blueos_3_ppc64le_ib_p9/output.dat' u 1:6 w p ls 21 t "Current", \

set output "NumInfections_ca_noair.Dane.eps"
set ylabel "Number of Infections" font "Times,16"
set key top right
set xrange [0:120]
plot \
'../baselines/ca.noair.b_development.toss_4_x86_64_ib/output.dat' u 1:3 w l ls 11 t "Baseline", \
'../tests/ca.noair.b_development.toss_4_x86_64_ib/output.dat' u 1:3 w p ls 21 t "Current", \

set output "NumDeaths_ca_noair.Dane.eps"
set ylabel "Number of Deaths" font "Times,16"
set key top left
set xrange [0:120]
plot \
'../baselines/ca.noair.b_development.toss_4_x86_64_ib/output.dat' u 1:5 w l ls 11 t "Baseline", \
'../tests/ca.noair.b_development.toss_4_x86_64_ib/output.dat' u 1:5 w p ls 21 t "Current", \

set output "NumHospitalizations_ca_noair.Dane.eps"
set ylabel "Number of Hospitalizations" font "Times,16"
set key top right
set xrange [0:120]
plot \
'../baselines/ca.noair.b_development.toss_4_x86_64_ib/output.dat' u 1:6 w l ls 11 t "Baseline", \
'../tests/ca.noair.b_development.toss_4_x86_64_ib/output.dat' u 1:6 w p ls 21 t "Current", \
