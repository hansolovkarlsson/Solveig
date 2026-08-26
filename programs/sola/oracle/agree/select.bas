' Every shape a CASE takes.
DEFINT A-Z
FOR n = 1 TO 8
  SELECT CASE n
  CASE 1, 2
    PRINT n; "one or two"
  CASE 3 TO 5
    PRINT n; "three to five"
  CASE IS >= 8
    PRINT n; "eight or more"
  CASE ELSE
    PRINT n; "none of those"
  END SELECT
NEXT n
END
