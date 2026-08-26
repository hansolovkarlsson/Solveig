' DIVERGENCE -- how many digits a Double shows.
'
' QBasic  fixes a count for a DOUBLE
' Sola    prints the shortest text that reads back as the same number, which is
'         the machine's own rule and not one BASIC states
'
' This is the one the language definition says is NOT settled. Whatever a real
' QuickBASIC prints here is the answer, and the divergence list should say so
' afterwards rather than saying "not yet settled".
DIM d AS DOUBLE
d = 1 / 3
PRINT d
d = 2 / 3
PRINT d
d = 1 / 7
PRINT d
d = 1E20
PRINT d
d = 1E-20
PRINT d
END
