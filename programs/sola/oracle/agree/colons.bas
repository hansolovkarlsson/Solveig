' Several statements on one line, and what a one-line IF does with them.
'
' Everything after THEN up to the end of the line belongs to the arm, so both
' of these run when the condition holds and neither runs when it does not --
' which was measured rather than guessed.
DEFINT A-Z
a = 1 : PRINT a : PRINT "two"
IF a = 1 THEN PRINT "yes" : PRINT "also"
IF a = 2 THEN PRINT "no" : PRINT "nor"
FOR i = 1 TO 3 : PRINT i; : NEXT i
PRINT
b = 2 : c = b * 3 : PRINT "c is"; c
PRINT "end"
END
