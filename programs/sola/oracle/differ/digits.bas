' DIVERGENCE -- how many digits a Double shows. MEASURED, no longer guessed.
'
' The language definition said this was the one thing NOT settled. It is now,
' against QuickBASIC 4.5 compiled with BC.EXE:
'
'   QBasic  sixteen significant digits, rounded    .3333333333333334
'   Sola    the shortest text that reads back as
'           the same number, up to seventeen       .3333333333333333
'
' So they agree whenever the shortest round-trip is sixteen digits or fewer and
' rounds the same way, and part company on the seventeenth digit and on the
' last one. Exponential form agrees exactly, D and all.
'
' The arithmetic is forced into Double on both sides -- 1# rather than 1 -- so
' that this file measures the printing and not where the sum happened, which is
' what defaulttype.bas is for.
DIM d AS DOUBLE
d = 1# / 3#
PRINT d
d = 1# / 7#
PRINT d
d = 2# / 3#
PRINT d
d = 1D20
PRINT d
d = 1D-20
PRINT d
END
