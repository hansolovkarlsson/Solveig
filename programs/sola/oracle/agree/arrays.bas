DECLARE SUB Sort (v%(), count%)
' Arrays, both bases, two dimensions, and one handed to a procedure.
DEFINT A-Z
OPTION BASE 1
CONST Size = 6
DIM n(Size)
n(1) = 5
n(2) = 3
n(3) = 9
n(4) = 1
n(5) = 7
n(6) = 2
CALL Sort(n(), Size)
FOR i = 1 TO Size
  PRINT n(i);
NEXT i
PRINT
DIM Grid(1 TO 3, 1 TO 4)
FOR r = 1 TO 3
  FOR c = 1 TO 4
    Grid(r, c) = r * 10 + c
  NEXT c
NEXT r
FOR r = 1 TO 3
  FOR c = 1 TO 4
    PRINT Grid(r, c);
  NEXT c
  PRINT
NEXT r
END

SUB Sort (v%(), count%)
  DIM i AS INTEGER
  DIM j AS INTEGER
  DIM t AS INTEGER
  FOR i = 1 TO count% - 1
    FOR j = 1 TO count% - i
      IF v%(j) > v%(j + 1) THEN
        t = v%(j)
        v%(j) = v%(j + 1)
        v%(j + 1) = t
      END IF
    NEXT j
  NEXT i
END SUB
