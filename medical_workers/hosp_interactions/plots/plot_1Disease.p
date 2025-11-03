# usage: CASE=<name> gnuplot plot.p

set terminal postscript enhanced eps color "Times" 18

set style line 11 dt 1 lw 1 lc rgbcolor "black"        pt  4 ps 1
set style line 12 dt 1 lw 1 lc rgbcolor "blue"         pt  6 ps 1
set style line 13 dt 1 lw 1 lc rgbcolor "red"          pt  8 ps 1
set style line 14 dt 1 lw 1 lc rgbcolor "dark-green"   pt 10 ps 1

set style line 20 dt 4 lw 1 lc rgbcolor "black"        pt  4 ps 1
set style line 22 dt 4 lw 1 lc rgbcolor "blue"         pt  6 ps 1
set style line 24 dt 4 lw 1 lc rgbcolor "red"          pt  8 ps 1
set style line 28 dt 4 lw 1 lc rgbcolor "dark-green"   pt 10 ps 1

set format x "%1g"
set format y "%1.1e"

set key width 0

set grid  xtics lw 1 dt 4 lc rgbcolor "gray"
set grid  ytics lw 1 dt 4 lc rgbcolor "gray"
set grid mxtics lw 1 dt 4 lc rgbcolor "gray"
set grid mytics lw 1 dt 4 lc rgbcolor "gray"

set xlabel "Days" font "Times,20"

hostname = system("echo $LCHOST")
case_name = system("echo $CASE")

path = "../"
dirname = ".run_" . case_name . "." . hostname . ".mwprop"
filename = "/output.dat"

output_fname="NumInfections_" . case_name . "." . hostname . ".eps"
set output output_fname
set title "California, 120 days, xmit_{hosp}=0.01*xmit_{work}"
set ylabel "Number of Infections" font "Times,16"
set key top right
set xrange [0:120]
pltcmd = "plot"
do for [i = 0 : 8 : 2] {
    pltfile = path . dirname . sprintf("0.0%1d",i) . filename
    keystr = sprintf("\"%d\%\"",i)
    pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w l ls " . sprintf("%d",i+20) . " t " . keystr . ","
}
print "plot command is: " . pltcmd
eval pltcmd
