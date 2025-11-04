# usage: CASE=<name> gnuplot plot_01Disease.p

set terminal postscript enhanced eps color "Times" 12

set style line 11 dt 1 lw 1 lc rgbcolor "black"        pt  4 ps 1
set style line 12 dt 1 lw 1 lc rgbcolor "blue"         pt  6 ps 1
set style line 13 dt 1 lw 1 lc rgbcolor "red"          pt  8 ps 1
set style line 14 dt 1 lw 1 lc rgbcolor "dark-green"   pt 10 ps 1

set style line 20 dt 4 lw 1 lc rgbcolor "black"        pt  4 ps 1
set style line 23 dt 4 lw 1 lc rgbcolor "blue"         pt  6 ps 1
set style line 26 dt 4 lw 1 lc rgbcolor "red"          pt  8 ps 1
set style line 29 dt 4 lw 1 lc rgbcolor "dark-green"   pt 10 ps 1

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
filename = "/output.dat"

set xlabel "Days" font "Times,16"
set ylabel "Number of Infections" font "Times,16"
output_fname="NumInfections_" . case_name . "." . hostname . ".eps"
set output output_fname

do for [xd2d = 0 : 12 : 6] {
    xd2p=0
    xp2d=0
    xp2p=0
    titlestr = "CA: xmit_{hosp} = " . sprintf("0.%03d (doctor-to-doctor) ", xd2d) . sprintf("0.%03d (patient-to-doctor) ", xp2d) . sprintf("0.%03d (doctor-to-patient) ", xd2p) . sprintf("0.%03d (patient-to-patient)", xp2p)
    set title titlestr
    set key top right
    set xrange [0:70]
    pltcmd = "plot"
    do for [mwp = 0 : 9 : 3] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xp2p) . filename
        keystr = "\"%age med. workers=" . sprintf("%d\"",mwp)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w l ls " . sprintf("%d",mwp+20) . " t " . keystr . ","
    }
#    print "plot command is: " . pltcmd
    eval pltcmd
}

do for [xp2d = 0 : 12 : 6] {
    xd2d=0
    xd2p=0
    xp2p=0
    titlestr = "CA: xmit_{hosp} = " . sprintf("0.%03d (doctor-to-doctor) ", xd2d) . sprintf("0.%03d (patient-to-doctor) ", xp2d) . sprintf("0.%03d (doctor-to-patient) ", xd2p) . sprintf("0.%03d (patient-to-patient)", xp2p)
    set title titlestr
    set key top right
    set xrange [0:70]
    pltcmd = "plot"
    do for [mwp = 0 : 9 : 3] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xp2p) . filename
        keystr = "\"%age med. workers=" . sprintf("%d\"",mwp)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w l ls " . sprintf("%d",mwp+20) . " t " . keystr . ","
    }
#    print "plot command is: " . pltcmd
    eval pltcmd
}

do for [xd2p = 0 : 10 : 5] {
    xd2d=0
    xp2d=0
    xp2p=0
    titlestr = "CA: xmit_{hosp} = " . sprintf("0.%03d (doctor-to-doctor) ", xd2d) . sprintf("0.%03d (patient-to-doctor) ", xp2d) . sprintf("0.%03d (doctor-to-patient) ", xd2p) . sprintf("0.%03d (patient-to-patient)", xp2p)
    set title titlestr
    set key top right
    set xrange [0:70]
    pltcmd = "plot"
    do for [mwp = 0 : 9 : 3] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xp2p) . filename
        keystr = "\"%age med. workers=" . sprintf("%d\"",mwp)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w l ls " . sprintf("%d",mwp+20) . " t " . keystr . ","
    }
#    print "plot command is: " . pltcmd
    eval pltcmd
}

do for [mwp = 0 : 9 : 3] {
    xd2d=0
    xp2d=0
    xd2p=0
    titlestr = "CA: xmit_{hosp} = " . sprintf("0.%03d (doctor-to-doctor) ", xd2d) . sprintf("0.%03d (patient-to-doctor) ", xp2d) . sprintf("0.%03d (doctor-to-patient) ", xd2p) . ", med worker %age = " . sprintf("%d", mwp)
    set title titlestr
    set key top right
    set xrange [0:70]
    pltcmd = "plot"
    do for [xp2p = 0 : 6 : 3] {
        pltfile = path . dirname . sprintf(".mwprop0.0%1d",mwp) . sprintf(".xmitd2d0.%03d",xd2d) . sprintf(".xmitp2d0.%03d",xp2d) . sprintf(".xmitd2p0.%03d",xd2p) . sprintf(".xmitp2p0.%03d",xp2p) . filename
        keystr = "\"xmit_{hosp} (p2p)=" . sprintf("0.%03d\"",xp2p)
        pltcmd = pltcmd . " \"" . pltfile . "\" u 1:3 w lp ls " . sprintf("%d",xp2p+20) . " t " . keystr . ","
    }
#    print "plot command is: " . pltcmd
    eval pltcmd
}
