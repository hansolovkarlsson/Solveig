' The numeric functions and their edges, with everything said as a Double so
' that both languages compute the same thing.
DIM x AS DOUBLE
PRINT "ABS"; ABS(-4.5#); ABS(4.5#)
PRINT "SGN"; SGN(-9#); SGN(0#); SGN(3#)
PRINT "INT"; INT(2.7#); INT(-2.5#)
PRINT "FIX"; FIX(2.7#); FIX(-2.5#)
PRINT "SQR"; SQR(16#)
PRINT "EXP"; EXP(0#)
PRINT "LOG"; LOG(1#)
PRINT "SIN"; SIN(0#)
PRINT "COS"; COS(0#)
PRINT "TAN"; TAN(0#)
PRINT "ATN"; ATN(0#)
x = 2# ^ 10#
PRINT "POW"; x
x = -2# ^ 2#
PRINT "NEG"; x
END
