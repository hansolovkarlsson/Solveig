' --- FOR, ascending and descending, with a literal step
FOR i = 1 TO 3
  PRINT "up "; i
NEXT i
FOR i = 3 TO 1 STEP -1
  PRINT "down "; i
NEXT
' --- a FOR whose range is already empty runs no times
FOR i = 5 TO 1
  PRINT "never"
NEXT i
' --- nested, closed on one line
FOR a = 1 TO 2
  FOR b = 1 TO 2
    PRINT "cell "; a; ","; b
NEXT b, a
' --- a step that is only known at run time
s = 2
FOR i = 1 TO 6 STEP s
  PRINT "by two "; i
NEXT i
' --- block IF with ELSEIF and ELSE
FOR n = 1 TO 4
  IF n = 1 THEN
    PRINT n; " one"
  ELSEIF n = 2 THEN
    PRINT n; " two"
  ELSEIF n = 3 THEN
    PRINT n; " three"
  ELSE
    PRINT n; " many"
  END IF
NEXT n
' --- one-line IF, with and without ELSE
IF 1 < 2 THEN PRINT "one-line then"
IF 1 > 2 THEN PRINT "wrong" ELSE PRINT "one-line else"
' --- SELECT CASE: value lists, ranges, IS, and ELSE
FOR n = 1 TO 6
  SELECT CASE n
  CASE 1, 2
    PRINT n; " is one or two"
  CASE 3 TO 4
    PRINT n; " is in three to four"
  CASE IS >= 6
    PRINT n; " is six or more"
  CASE ELSE
    PRINT n; " is none of those"
  END SELECT
NEXT n
' --- DO with the test at the top, and at the bottom
k = 0
DO WHILE k < 3
  k = k + 1
  PRINT "do while "; k
LOOP
k = 0
DO
  k = k + 1
  PRINT "loop until "; k
LOOP UNTIL k >= 3
k = 0
DO UNTIL k >= 2
  k = k + 1
  PRINT "do until "; k
LOOP
' --- WHILE / WEND
k = 0
WHILE k < 2
  k = k + 1
  PRINT "wend "; k
WEND
' --- EXIT, from inside an IF inside the loop
FOR i = 1 TO 10
  IF i = 3 THEN EXIT FOR
  PRINT "exit for "; i
NEXT i
k = 0
DO
  k = k + 1
  IF k = 2 THEN EXIT DO
  PRINT "exit do "; k
LOOP
PRINT "done"
END
