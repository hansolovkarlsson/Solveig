DECLARE SUB Rule (n%)
' A sales report -- a real program rather than a test of a feature, written to
' see what a real one would want. It reads records, totals them and lays out a
' table, which is what BASIC was for.
DEFINT A-Z
CONST MaxLines = 50

DIM nm$(MaxLines)
DIM qty(MaxLines)
DIM price#(MaxLines)
DIM count
DIM i
DIM total#
DIM value#

OPEN "SALES.DAT" FOR OUTPUT AS #1
WRITE #1, "Widgets", 12, 2.5
WRITE #1, "Grommets", 3, 14.99
WRITE #1, "Flanges", 120, .75
WRITE #1, "Sprockets", 7, 33.4
CLOSE #1

OPEN "SALES.DAT" FOR INPUT AS #1
count = 0
DO UNTIL EOF(1)
  count = count + 1
  INPUT #1, nm$(count), qty(count), price#(count)
LOOP
CLOSE #1

PRINT "SALES REPORT"
CALL Rule(42)
PRINT "ITEM           QTY        EACH       VALUE"
CALL Rule(42)

total# = 0
FOR i = 1 TO count
  value# = qty(i) * price#(i)
  total# = total# + value#
  PRINT USING "\          \  ####  $$#####.##  $$#####.##"; nm$(i); qty(i); price#(i); value#
NEXT i
CALL Rule(42)
PRINT USING "TOTAL                             $$#####.##"; total#
PRINT USING "### items, ### lines read"; count; count
END

SUB Rule (n%)
  PRINT STRING$(n%, "-")
END SUB
