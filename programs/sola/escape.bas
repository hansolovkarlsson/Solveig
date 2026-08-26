' A GOTO that leaves a block from inside a loop, and a label inside one.
' The second is how BASIC spells what a later language calls `continue`: a
' label just before NEXT, jumped to from inside the body.
FOR i = 1 TO 10
  IF i = 3 THEN GOTO Escaped
  PRINT "i "; i
NEXT i
PRINT "not reached"
Escaped:
PRINT "left the loop at i = "; i
FOR j = 1 TO 3
  IF j = 2 THEN GOTO Skip
  PRINT "j "; j
Skip:
NEXT j
PRINT "done"
END
