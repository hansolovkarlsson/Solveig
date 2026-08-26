' GOTO -- the claim the whole design rests on, and until now the one thing the
' comparison did not touch. Forwards, backwards, out of a block, and a label
' just before NEXT, which is how BASIC spells what a later language calls
' `continue`.
DEFINT A-Z
i = 0
Top:
  i = i + 1
  PRINT "i ="; i
  IF i < 5 THEN GOTO Top
  GOTO Done
  PRINT "never printed"
Done:
  PRINT "counted to"; i

FOR j = 1 TO 10
  IF j = 3 THEN GOTO Escaped
  PRINT "j"; j
NEXT j
PRINT "not reached"
Escaped:
PRINT "left the loop at j ="; j

FOR k = 1 TO 3
  IF k = 2 THEN GOTO Skip
  PRINT "k"; k
Skip:
NEXT k
PRINT "done"
END
