' Jumps that cross each other, and two loops woven from nothing but GOTO.
' Nothing here nests, which is the point: the compiler never sees a structure,
' only labels and the offsets they turn into.
DEFINT A-Z
n = 0
t = 0
Outer:
  n = n + 1
  m = 0
  GOTO Inner
BackFromInner:
  IF n < 4 THEN GOTO Outer
  GOTO Report
Inner:
  m = m + 1
  t = t + 1
  IF m < 3 THEN GOTO Inner
  GOTO BackFromInner
Report:
  PRINT "outer"; n; "inner total"; t
END
