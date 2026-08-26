' By reference, and the analysis that decides which parameters are.
'
' Only C assigns to its parameter, but A and B hand theirs on to something that
' does -- so all three are by reference, and finding that out is a fixed point
' rather than one pass over the listing.
SUB C (v)
  v = 42
END SUB
SUB B (v)
  CALL C(v)
END SUB
SUB A (v)
  CALL B(v)
END SUB
n = 0
CALL A(n)
PRINT "reached through three procedures: "; n

' A parameter nobody assigns to is passed by value, and a copy is all the
' callee ever sees.
FUNCTION Twice (x)
  Twice = x + x
END FUNCTION
m = 5
PRINT "twice "; m; " is "; Twice(m); ", and m is still "; m

' Brackets are QBasic's own way of spelling by value.
SUB Bump (v)
  v = v + 1
END SUB
k = 1
CALL Bump(k)
PRINT "CALL Bump(k) gives "; k
Bump (k)
PRINT "Bump (k) leaves it at "; k
END
