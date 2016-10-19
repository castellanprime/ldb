# Note you need gnuplot 4.4 for the pdfcairo terminal.

# set terminal pdfcairo font "Gill Sans,9" linewidth 4 rounded fontscale 1.0
set terminal pdfcairo font "Gill Sans,7" linewidth 1 rounded fontscale 1.0

# Line style for axes
set style line 80 lt rgb "#808080"

# Line style for grid
set style line 81 lt 0  # dashed
set style line 81 lt rgb "#808080"  # grey

set grid back linestyle 81
set border 3 back linestyle 80 # Remove border on top and right.  These
             # borders are useless and make it harder
             # to see plotted lines near the border.
    # Also, put it in grey; no need for so much emphasis on a border.
# set xtics nomirror
# set ytics nomirror

#set log x
#set mxtics 10    # Makes logscale look good.

# Line styles: try to pick pleasing colors, rather
# than strictly primary colors or hard-to-see colors

# like gnuplot's default yellow.  Make the lines thick
# so they're easy to see in small plots in papers.
set style line 1 lc rgb "#27ae60" lw 4 pt 7 ps 0
set style line 2 lc rgb "#2980b9" lw 4 pt 7 ps 0
set style line 3 lc rgb "#f1c40f" lw 4 pt 7 ps 0
set style line 4 lc rgb "#7f8c8d" lw 4 pt 7 ps 0 
set style line 5 lc rgb "#c0392b" lw 4 pt 7 ps 0
set style line 6 lc rgb "#2c3e50" lw 4 pt 7 ps 0

set output outputname
set xlabel "Time in Seconds"
set ylabel "MB Transmitted"

set key left top

set datafile missing '0'

# log scale on the y axis
# set logscale y 2
# set format y ""
# set ytics 1e-6, 10, 1
# set ytics add ("1" 1, ".1" 0.1, ".01" 0.01, "10^-3" 0.001, \
#                "10^-4" 0.0001)
# set mytics 10

set yrange [0:*]

# set xrange [0:60]
# set yrange [0.5:64]

# Titles with spaces are not allowed
# These titles should be separated by "_" and here we replace by " "
pretty(title) = system("echo ".title." | sed 's/_/ /g'")

# Input file contains comma-separated values fields
set datafile separator ","

plot for [i=0:words(statefiles) - 1] word(statefiles, i + 1) using 1:2 title pretty(word(statetitles, i + 1)) with linespoints ls i + 1
replot for [i=0:words(deltafiles) - 1] word(deltafiles, i + 1) using 1:2 title pretty(word(deltatitles, i + 1)) with linespoints ls i + 4
#replot for [i=0:words(joinfiles) - 1] word(joinfiles, i + 1) using 1:2 title pretty(word(jointitles, i + 1)) with linespoints ls i + 4
