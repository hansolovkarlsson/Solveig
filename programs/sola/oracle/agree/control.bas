' FOR with a step in both directions, a range that is already empty, and every
' shape of DO. The counters are integers so both languages agree on the type.
DEFINT A-Z
FOR i = 1 TO 3
  PRINT i;
NEXT i
PRINT
FOR i = 3 TO 1 STEP -1
  PRINT i;
NEXT i
PRINT
FOR i = 5 TO 1
  PRINT "never";
NEXT i
PRINT "empty range ran no times"
FOR i = 1 TO 6 STEP 2
  PRINT i;
NEXT i
PRINT
k = 0
DO WHILE k < 3
  k = k + 1
  PRINT k;
LOOP
PRINT
k = 0
DO
  k = k + 1
  PRINT k;
LOOP UNTIL k >= 3
PRINT
k = 0
WHILE k < 2
  k = k + 1
  PRINT k;
WEND
PRINT
FOR i = 1 TO 10
  IF i = 4 THEN EXIT FOR
  PRINT i;
NEXT i
PRINT
END
