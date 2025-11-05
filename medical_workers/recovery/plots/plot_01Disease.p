# usage: CASE=<name> gnuplot plot_01Disease.p

set terminal postscript enhanced eps color "Times" 12

set style line 10 dt 1 lw 1 lc rgbcolor "black"        pt  4 ps 1
set style line 11 dt 1 lw 1 lc rgbcolor "black"        pt  4 ps 1
set style line 12 dt 1 lw 1 lc rgbcolor "blue"         pt  6 ps 1
set style line 13 dt 1 lw 1 lc rgbcolor "red"          pt  8 ps 1
set style line 14 dt 1 lw 1 lc rgbcolor "dark-green"   pt 10 ps 1

set style line 21 dt 4 lw 2 lc rgbcolor "dark-orange"  pt  4 ps 1
set style line 22 dt 4 lw 2 lc rgbcolor "blue"         pt  6 ps 1
set style line 23 dt 4 lw 2 lc rgbcolor "red"          pt  8 ps 1
set style line 24 dt 4 lw 2 lc rgbcolor "dark-green"   pt 10 ps 1
set style line 25 dt 4 lw 2 lc rgbcolor "magenta"      pt 12 ps 1

set format x "%1g"
set format y "%1.1e"

set key width 0

set grid  xtics lw 1 dt 4 lc rgbcolor "gray"
set grid  ytics lw 1 dt 4 lc rgbcolor "gray"
set grid mxtics lw 1 dt 4 lc rgbcolor "gray"
set grid mytics lw 1 dt 4 lc rgbcolor "gray"


hostname_LC = system("echo $LCHOST")
hostname_NERSC = system("echo $NERSC_HOST")
hostname=""
cluster=""
if (hostname_LC eq "") {
    if (hostname_NERSC eq "") {
        print "Unable to get hostname."
    } else {
        hostname=hostname_NERSC
        cluster="NERSC"
    }
} else {
    hostname=hostname_LC
    cluster="LC"
}
print "Cluster is " . cluster . ", hostname is " . hostname
case_name = system("echo $CASE")

path = "../"
dirname = ".run_" . case_name . "." . hostname 
fname_op = "/output.dat"
fname_hosp = "/num_bad_hospitals.dat"

mwp_l=3
mwp_h=9
mwp_i=3

array nppd[5] = [5, 10, 20, 50, 100]

set xrange [0:80]

set xlabel "Days" font "Times,16"
set ylabel "Number of Infections" font "Times,16"
output_fname="NumInfections_" . case_name . "." . hostname . ".eps"
set output output_fname
do for [mwp = mwp_l : mwp_h : mwp_i] {
    titlestr = "CA: ". sprintf("Medical workers percentage - %d", mwp)
    set title titlestr
    set key top right
    pltcmd = "plot"
    pltfile = path . dirname . ".baseline" . fname_op
    keystr = "\"baseline\""
    pltcmd = pltcmd . " \"" . pltfile . "\" u 1:($3+$4+$5+$6+$7+$8) w l ls 10 t " . keystr . ","
    do for [i=1:|nppd|] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".nppd%03d",nppd[i]) . fname_op
        keystr = "\"num. patients per doctor=" . sprintf("%3d\"",nppd[i])
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:($3+$4+$5+$6+$7+$8) w lp ls " . sprintf("%d",i+20) . " t " . keystr . ","
    }
    eval pltcmd
}

set xlabel "Days" font "Times,16"
set ylabel "Number of Hospitalizations" font "Times,16"
output_fname="NumHospitalizations_" . case_name . "." . hostname . ".eps"
set output output_fname
do for [mwp = mwp_l : mwp_h : mwp_i] {
    titlestr = "CA: ". sprintf("Medical workers percentage - %d", mwp)
    set title titlestr
    set key top right
    pltcmd = "plot"
    pltfile = path . dirname . ".baseline" . fname_op
    keystr = "\"baseline\""
    pltcmd = pltcmd . " \"" . pltfile . "\" u 1:($9+$10) w l ls 10 t " . keystr . ","
    do for [i=1:|nppd|] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".nppd%03d",nppd[i]) . fname_op
        keystr = "\"num. patients per doctor=" . sprintf("%3d\"",nppd[i])
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:($9+$10) w lp ls " . sprintf("%d",i+20) . " t " . keystr . ","
    }
    eval pltcmd
}

set xlabel "Days" font "Times,16"
set ylabel "Number of Deaths" font "Times,16"
output_fname="NumDeaths_" . case_name . "." . hostname . ".eps"
set output output_fname
do for [mwp = mwp_l : mwp_h : mwp_i] {
    titlestr = "CA: ". sprintf("Medical workers percentage - %d", mwp)
    set title titlestr
    set key bottom right
    pltcmd = "plot"
    pltfile = path . dirname . ".baseline" . fname_op
    keystr = "\"baseline\""
    pltcmd = pltcmd . " \"" . pltfile . "\" u 1:14 w l ls 10 t " . keystr . ","
    do for [i=1:|nppd|] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".nppd%03d",nppd[i]) . fname_op
        keystr = "\"num. patients per doctor=" . sprintf("%3d\"",nppd[i])
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:14 w l ls " . sprintf("%d",i+20) . " t " . keystr . ","
    }
    eval pltcmd
}

set xlabel "Days" font "Times,16"
set ylabel "Number of Overloaded Hospitals" font "Times,16"
output_fname="NumHospitals_" . case_name . "." . hostname . ".eps"
set output output_fname
do for [mwp = mwp_l : mwp_h : mwp_i] {
    titlestr = "CA: ". sprintf("Medical workers percentage - %d", mwp)
    set title titlestr
    set key top right
    set logscale y
    pltcmd = "plot"
    do for [i=1:|nppd|] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".nppd%03d",nppd[i]) . fname_hosp
        keystr = "\"num. patients per doctor=" . sprintf("%3d\"",nppd[i])
        pltcmd = pltcmd . " \"" . pltfile . "\" u 2:3 w l ls " . sprintf("%d",i+20) . " t " . keystr . ","
    }
    eval pltcmd
}

set xlabel "Days" font "Times,16"
set ylabel "Number of Underserved Patients" font "Times,16"
output_fname="NumPatients_" . case_name . "." . hostname . ".eps"
set output output_fname
do for [mwp = mwp_l : mwp_h : mwp_i] {
    titlestr = "CA: ". sprintf("Medical workers percentage - %d", mwp)
    set title titlestr
    set key top right
    set logscale y
    pltcmd = "plot"
    do for [i=1:|nppd|] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".nppd%03d",nppd[i]) . fname_hosp
        keystr = "\"num. patients per doctor=" . sprintf("%3d\"",nppd[i])
        pltcmd = pltcmd . " \"" . pltfile . "\" u 2:7 w l ls " . sprintf("%d",i+20) . " t " . keystr . ","
    }
    eval pltcmd
}
