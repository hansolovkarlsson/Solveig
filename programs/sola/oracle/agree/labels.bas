' Numeric labels, out of order, with one that is never reached.
'
' CB80's rule -- which SolaBasic takes over -- is that a label is a string of
' characters and not a number, so these need not ascend. This file was written
' to ask whether QuickBASIC agrees, and it does: 4.5 compiles and runs it, and
' prints what SolaBasic prints. So the rule SolaBasic borrowed from CB80 is not
' a divergence from QBasic at all, and the divergence list needs no entry.
DEFINT A-Z
100 PRINT "at one hundred"
GOTO 50
30 PRINT "never reached"
50 PRINT "at fifty, which is written after one hundred"
END
