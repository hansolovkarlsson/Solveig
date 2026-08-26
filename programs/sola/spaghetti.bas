' Jumps that cross each other, and two loops woven from nothing but GOTO.
' Nothing here nests, which is the point: the compiler never sees a structure,
' only labels and the offsets they turn into.
  N = 0
  T = 0
Outer:
  N = N + 1
  M = 0
  GOTO Inner
BackFromInner:
  IF N < 4 THEN GOTO Outer
  GOTO Report
Inner:
  M = M + 1
  T = T + 1
  IF M < 3 THEN GOTO Inner
  GOTO BackFromInner
Report:
  PRINT "outer "; N; " inner total "; T
  END
