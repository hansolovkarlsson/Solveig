DECLARE FUNCTION Neighbours% (g%(), r%, c%)
DECLARE SUB Show (g%(), gen%)
' Conway's Life on a grid -- the canonical BASIC program, and the only thing
' here that works a two-dimensional array hard.
DEFINT A-Z
CONST Size = 8
CONST Gens = 4

DIM grid%(1 TO Size, 1 TO Size)
DIM nxt%(1 TO Size, 1 TO Size)
DIM r
DIM c
DIM g
DIM n

' A glider.
grid%(2, 3) = 1
grid%(3, 4) = 1
grid%(4, 2) = 1
grid%(4, 3) = 1
grid%(4, 4) = 1

CALL Show(grid%(), 0)
FOR g = 1 TO Gens
  FOR r = 1 TO Size
    FOR c = 1 TO Size
      n = Neighbours%(grid%(), r, c)
      nxt%(r, c) = 0
      IF grid%(r, c) = 1 THEN
        IF n = 2 OR n = 3 THEN nxt%(r, c) = 1
      ELSE
        IF n = 3 THEN nxt%(r, c) = 1
      END IF
    NEXT c
  NEXT r
  FOR r = 1 TO Size
    FOR c = 1 TO Size
      grid%(r, c) = nxt%(r, c)
    NEXT c
  NEXT r
  CALL Show(grid%(), g)
NEXT g
END

FUNCTION Neighbours% (g%(), r%, c%)
  DIM dr
  DIM dc
  DIM t
  DIM rr
  DIM cc
  t = 0
  FOR dr = -1 TO 1
    FOR dc = -1 TO 1
      IF dr <> 0 OR dc <> 0 THEN
        rr = r% + dr
        cc = c% + dc
        IF rr >= 1 AND rr <= Size AND cc >= 1 AND cc <= Size THEN
          t = t + g%(rr, cc)
        END IF
      END IF
    NEXT dc
  NEXT dr
  Neighbours% = t
END FUNCTION

SUB Show (g%(), gen%)
  DIM r
  DIM c
  DIM line$
  PRINT "generation"; gen%
  FOR r = 1 TO Size
    line$ = ""
    FOR c = 1 TO Size
      IF g%(r, c) = 1 THEN
        line$ = line$ + "#"
      ELSE
        line$ = line$ + "."
      END IF
    NEXT c
    PRINT line$
  NEXT r
END SUB
