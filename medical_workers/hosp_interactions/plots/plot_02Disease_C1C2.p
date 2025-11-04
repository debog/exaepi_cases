# usage: CASE=<name> gnuplot plot_02Disease_C1C2.p

set terminal postscript enhanced eps color "Times" 12

set style line 11 dt 1 lw 1 lc rgbcolor "black"        pt  4 ps 1
set style line 12 dt 1 lw 1 lc rgbcolor "blue"         pt  6 ps 1
set style line 13 dt 1 lw 1 lc rgbcolor "red"          pt  8 ps 1
set style line 14 dt 1 lw 1 lc rgbcolor "dark-green"   pt 10 ps 1

set style line 20 dt 4 lw 1 lc rgbcolor "black"        pt  4 ps 1
set style line 23 dt 4 lw 1 lc rgbcolor "blue"         pt  6 ps 1
set style line 26 dt 4 lw 1 lc rgbcolor "red"          pt  8 ps 1
set style line 29 dt 4 lw 1 lc rgbcolor "dark-green"   pt 10 ps 1

set style line 30 dt 2 lw 1 lc rgbcolor "black"        pt  4 ps 0.5
set style line 33 dt 2 lw 1 lc rgbcolor "blue"         pt  6 ps 0.5
set style line 36 dt 2 lw 1 lc rgbcolor "red"          pt  8 ps 0.5
set style line 39 dt 2 lw 1 lc rgbcolor "dark-green"   pt 10 ps 0.5

set format x "%1g"
set format y "%1.1e"

set key width 0

set grid  xtics lw 1 dt 4 lc rgbcolor "gray"
set grid  ytics lw 1 dt 4 lc rgbcolor "gray"
set grid mxtics lw 1 dt 4 lc rgbcolor "gray"
set grid mytics lw 1 dt 4 lc rgbcolor "gray"

hostname = system("echo $LCHOST")
case_name = system("echo $CASE")

path = "../"
dirname = ".run_" . case_name . "." . hostname 
fname_d1 = "/output_covid1.dat"
fname_d2 = "/output_covid2.dat"

set xlabel "Days" font "Times,16"
set ylabel "Number of Infections" font "Times,16"
output_fname="NumInfections_" . case_name . "." . hostname . ".eps"
set output output_fname

do for [mwp = 0 : 9 : 3] {
    xp2d=0
    xd2p=0
    xp2p=0
    titlestr = "CA: xmit_{hosp} = " . sprintf("0.%03d (patient-to-doctor), ", xp2d) . sprintf("0.%03d (doctor-to-patient), ", xd2p) . sprintf("0.%03d (patient-to-patient), ", xp2p) . " med worker %age = " . sprintf("%d", mwp)
    set title titlestr
    set key top right
    set xrange [0:70]
    pltcmd = "plot"
    do for [xd2d = 0 : 12 : 6] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xd2d) . fname_d1
        keystr = "\"covid1, xmit_{hosp} (d2d)=" . sprintf("0.%03d\"",xd2d)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xd2d+20) . " t " . keystr . ","
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xd2d) . fname_d2
        keystr = "\"covid2, xmit_{hosp} (d2d)=" . sprintf("0.%03d\"",xd2d)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xd2d+30) . " t " . keystr . ","
    }
#    print "plot command is: " . pltcmd
    eval pltcmd

    xd2d=0
    xd2p=0
    xp2p=0
    titlestr = "CA: xmit_{hosp} = " . sprintf("0.%03d (doctor-to-doctor), ", xd2d) . sprintf("0.%03d (doctor-to-patient), ", xd2p) . sprintf("0.%03d (patient-to-patient), ", xp2p) . " med worker %age = " . sprintf("%d", mwp)
    set title titlestr
    set key top right
    set xrange [0:70]
    pltcmd = "plot"
    do for [xp2d = 0 : 12 : 6] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xp2d) . fname_d1
        keystr = "\"covid1, xmit_{hosp} (p2d)=" . sprintf("0.%03d\"",xp2d)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xp2d+20) . " t " . keystr . ","
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xp2d) . fname_d2
        keystr = "\"covid2, xmit_{hosp} (p2d)=" . sprintf("0.%03d\"",xp2d)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xp2d+30) . " t " . keystr . ","
    }
#    print "plot command is: " . pltcmd
    eval pltcmd

    xd2d=0
    xp2d=0
    xp2p=0
    titlestr = "CA: xmit_{hosp} = " . sprintf("0.%03d (doctor-to-doctor), ", xd2d) . sprintf("0.%03d (patient-to-doctor), ", xp2d) . sprintf("0.%03d (patient-to-patient), ", xp2p) . " med worker %age = " . sprintf("%d", mwp)
    set title titlestr
    set key top right
    set xrange [0:70]
    pltcmd = "plot"
    do for [xd2p = 0 : 10 : 5] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xd2p) . fname_d1
        keystr = "\"covid1, xmit_{hosp} (d2p)=" . sprintf("0.%03d\"",xd2p)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xd2p+20) . " t " . keystr . ","
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xd2p) . fname_d2
        keystr = "\"covid2, xmit_{hosp} (d2p)=" . sprintf("0.%03d\"",xd2p)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xd2p+30) . " t " . keystr . ","
    }
#    print "plot command is: " . pltcmd
    eval pltcmd

    xd2d=0
    xp2d=0
    xd2p=0
    titlestr = "CA: xmit_{hosp} = " . sprintf("0.%03d (doctor-to-doctor), ", xd2d) . sprintf("0.%03d (patient-to-doctor), ", xp2d) . sprintf("0.%03d (doctor-to-patient), ", xd2p) . " med worker %age = " . sprintf("%d", mwp)
    set title titlestr
    set key top right
    set xrange [0:70]
    pltcmd = "plot"
    do for [xp2p = 0 : 6 : 3] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xp2p) . fname_d1
        keystr = "\"covid1, xmit_{hosp} (p2p)=" . sprintf("0.%03d\"",xp2p)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xp2p+20) . " t " . keystr . ","
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xp2p) . fname_d2
        keystr = "\"covid2, xmit_{hosp} (p2p)=" . sprintf("0.%03d\"",xp2p)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xp2p+30) . " t " . keystr . ","
    }
#    print "plot command is: " . pltcmd
    eval pltcmd
}
