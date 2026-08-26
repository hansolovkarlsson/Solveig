DECLARE SUB C0 (v%)
DECLARE SUB B0 (v%)
DECLARE SUB A0 (v%)
DECLARE SUB Bump (v%)
DECLARE FUNCTION Twice% (x%)
' By reference through a chain: only C0 assigns to its parameter, but A0 and B0
' hand theirs on to something that does, so all three pass by reference and the
' write reaches the caller. And brackets pass a copy instead.
DEFINT A-Z
n = 0
CALL A0(n)
PRINT "reached through three procedures:"; n

m = 5
PRINT "twice"; m; "is"; Twice%(m); ", and m is still"; m

k = 1
CALL Bump(k)
PRINT "CALL Bump(k) gives"; k
Bump (k)
PRINT "Bump (k) leaves it at"; k
END

SUB C0 (v%)
  v% = 42
END SUB

SUB B0 (v%)
  CALL C0(v%)
END SUB

SUB A0 (v%)
  CALL B0(v%)
END SUB

SUB Bump (v%)
  v% = v% + 1
END SUB

FUNCTION Twice% (x%)
  Twice% = x% + x%
END FUNCTION
