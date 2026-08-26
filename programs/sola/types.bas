' The three types, and the operators that tell them apart.
a% = 7
b# = 2.5
c$ = "text"
PRINT a%; " "; b#; " "; c$
' --- integer and double division differ
PRINT 7 / 2
' Integer divide and MOD cut towards nought and take the sign of the left-hand
' side, as QBasic does -- where the machine's own div and mod are floored.
PRINT 7 \ 2; " "; -7 \ 2; " "; 7 \ -2; " "; -7 \ -2
PRINT 7 MOD 2; " "; -7 MOD 2; " "; 7 MOD -2; " "; -7 MOD -2
PRINT -9 \ 5; " "; -9 MOD 5; " "; -6 \ 2; " "; -6 MOD 2
' And exactly, which a route through the float divide would not be.
PRINT 9007199254740993 \ 1
PRINT 9007199254740993 \ 3
PRINT 9007199254740993 MOD 2
' --- power
PRINT 2 ^ 10
PRINT -2 ^ 2
' --- string concatenation
PRINT "con" + "cat"
' --- comparisons are -1 and 0 when used as numbers
PRINT (1 < 2)
PRINT (1 > 2)
' --- bitwise, and conditions built from them
IF 1 < 2 AND 3 < 4 THEN PRINT "both"
IF 1 > 2 OR 3 < 4 THEN PRINT "either"
IF NOT (1 > 2) THEN PRINT "not"
PRINT 12 AND 10
PRINT 12 OR 10
PRINT 12 XOR 10
' --- based literals
PRINT &HFF; " "; &O17
' --- DEF
DEFINT I-N
i = 3 / 2
PRINT i
END
