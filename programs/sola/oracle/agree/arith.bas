' Integer divide and MOD take their signs from QBasic and not from the machine
' underneath, and this is where that is checked by somebody else.
DEFINT A-Z
PRINT 7 \ 2, -7 \ 2, 7 \ -2, -7 \ -2
PRINT 7 MOD 2, -7 MOD 2, 7 MOD -2, -7 MOD -2
PRINT 9 \ 5, -9 \ 5, 9 MOD 5, -9 MOD 5
PRINT 6 \ 2, -6 \ 2, 6 MOD 2, -6 MOD 2
DIM d AS DOUBLE
d = 7 / 2
PRINT d
PRINT 2 ^ 10
PRINT -2 ^ 2
PRINT 12 AND 10, 12 OR 10, 12 XOR 10, NOT 0
PRINT (1 < 2), (1 > 2)
END
