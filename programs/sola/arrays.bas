' Arrays, DIM, OPTION BASE and CONST.
OPTION BASE 1
CONST Size = 6

' One dimension, bounds from a CONST, and a bubble sort that is handed the
' array rather than a copy of it -- a Solum array is a reference already, so
' by-reference costs nothing here and needs no box.
DIM n(Size)
n(1) = 5
n(2) = 3
n(3) = 9
n(4) = 1
n(5) = 7
n(6) = 2

SUB Sort (v(), count%)
  FOR i% = 1 TO count% - 1
    FOR j% = 1 TO count% - i%
      IF v(j%) > v(j% + 1) THEN
        t = v(j%)
        v(j%) = v(j% + 1)
        v(j% + 1) = t
      END IF
    NEXT j%
  NEXT i%
END SUB

CALL Sort(n(), Size)
FOR i% = 1 TO Size
  PRINT n(i%);
NEXT i%
PRINT

' Two dimensions, with the type said outright rather than by a suffix. The
' strides are constant because the bounds are, so the index arithmetic that can
' be done at compile time is.
DIM Grid(1 TO 3, 1 TO 4) AS INTEGER
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

' Text in an array, and a CONST that is text.
CONST Greeting$ = "hello"
DIM Names$(2)
Names$(1) = Greeting$
Names$(2) = "world"
PRINT Names$(1); ", "; Names$(2)
END
