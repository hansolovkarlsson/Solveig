' Sequential files: written, read back, appended to, and read again.
'
' WRITE # puts commas between its items and quotes round its text, which is the
' form INPUT # reads back -- where PRINT #'s spacing is for a person to look at.
DEFINT A-Z
DIM l$
DIM nm$
DIM ag

OPEN "TEST.DAT" FOR OUTPUT AS #1
PRINT #1, "first line"
PRINT #1, "value"; 42
WRITE #1, "Hans", 7, "end"
CLOSE #1

OPEN "TEST.DAT" FOR INPUT AS #1
DO UNTIL EOF(1)
  LINE INPUT #1, l$
  PRINT "["; l$; "]"
LOOP
CLOSE #1

OPEN "TEST.DAT" FOR APPEND AS #2
PRINT #2, "appended"
CLOSE #2

OPEN "TEST.DAT" FOR INPUT AS #3
n = 0
DO UNTIL EOF(3)
  LINE INPUT #3, l$
  n = n + 1
LOOP
CLOSE #3
PRINT "lines now"; n

OPEN "RECS.DAT" FOR OUTPUT AS #1
WRITE #1, "Hans", 42
WRITE #1, "Solveig", 7
CLOSE #1

OPEN "RECS.DAT" FOR INPUT AS #1
DO UNTIL EOF(1)
  INPUT #1, nm$, ag
  PRINT nm$; " is"; ag
LOOP
CLOSE #1
END
