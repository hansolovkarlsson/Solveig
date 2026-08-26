' INPUT and LINE INPUT, with the answers coming from input.in beside this file.
'
' A prompt followed by ';' gets a question mark and one followed by ',' does
' not. And a QuickBASIC program echoes an answer it read from a file, so that a
' redirected session reads the way the interactive one looked -- which is a
' thing SolaBasic had to be taught, and was taught by this comparison.
DEFINT A-Z
INPUT "TWO NUMBERS, SEPARATED BY A COMMA"; a, b
PRINT "SUM IS"; a + b
PRINT "PRODUCT IS"; a * b
INPUT "AND YOUR NAME", n$
PRINT "THANK YOU, "; n$
INPUT x
PRINT "AND"; x
LINE INPUT "A WHOLE LINE, COMMAS AND ALL: "; whole$
PRINT "["; whole$; "]"
END
