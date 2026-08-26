DECLARE SUB Double0 (v%)
DECLARE SUB Exchange (p%, q%)
DECLARE FUNCTION Fact% (n%)
' A parameter assigned to reaches the caller's variable; one in brackets does
' not. And a FUNCTION answers by assigning to its own name.
DEFINT A-Z
a = 21
CALL Double0(a)
PRINT a
b = 10
Double0 (b)
PRINT b
x = 1
y = 2
CALL Exchange(x, y)
PRINT x; y
PRINT Fact%(6)
END

SUB Double0 (v%)
  v% = v% * 2
END SUB

SUB Exchange (p%, q%)
  DIM t AS INTEGER
  t = p%
  p% = q%
  q% = t
END SUB

FUNCTION Fact% (n%)
  IF n% <= 1 THEN
    Fact% = 1
  ELSE
    Fact% = n% * Fact%(n% - 1)
  END IF
END FUNCTION
