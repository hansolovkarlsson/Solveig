DECLARE FUNCTION IsLetter% (c$)
DECLARE FUNCTION Find% (w$(), n%, t$)
DECLARE SUB SortByCount (w$(), c%(), n%)
' A word-frequency count -- the program that works the string functions hard.
DEFINT A-Z
CONST MaxWords = 40

DIM word$(MaxWords)
DIM count%(MaxWords)
DIM n
DIM i
DIM j
DIM line$
DIM ch$
DIM cur$
DIM at

OPEN "TEXT.DAT" FOR OUTPUT AS #1
PRINT #1, "the quick brown fox jumps over the lazy dog"
PRINT #1, "The DOG barks, and the fox runs."
PRINT #1, "   quick   quick   "
CLOSE #1

n = 0
OPEN "TEXT.DAT" FOR INPUT AS #1
DO UNTIL EOF(1)
  LINE INPUT #1, line$
  cur$ = ""
  FOR i = 1 TO LEN(line$) + 1
    IF i > LEN(line$) THEN
      ch$ = " "
    ELSE
      ch$ = MID$(line$, i, 1)
    END IF
    IF IsLetter%(ch$) = 1 THEN
      cur$ = cur$ + UCASE$(ch$)
    ELSE
      IF LEN(cur$) > 0 THEN
        at = Find%(word$(), n, cur$)
        IF at = 0 THEN
          n = n + 1
          word$(n) = cur$
          count%(n) = 1
        ELSE
          count%(at) = count%(at) + 1
        END IF
        cur$ = ""
      END IF
    END IF
  NEXT i
LOOP
CLOSE #1

CALL SortByCount(word$(), count%(), n)
PRINT USING "### distinct words"; n
FOR i = 1 TO n
  PRINT USING "\        \  ###"; word$(i); count%(i)
NEXT i
END

FUNCTION IsLetter% (c$)
  DIM u$
  u$ = UCASE$(c$)
  IF u$ >= "A" AND u$ <= "Z" THEN
    IsLetter% = 1
  ELSE
    IsLetter% = 0
  END IF
END FUNCTION

FUNCTION Find% (w$(), n%, t$)
  DIM k
  Find% = 0
  FOR k = 1 TO n%
    IF w$(k) = t$ THEN
      Find% = k
      EXIT FUNCTION
    END IF
  NEXT k
END FUNCTION

SUB SortByCount (w$(), c%(), n%)
  DIM a
  DIM b
  DIM ts$
  DIM ti
  FOR a = 1 TO n% - 1
    FOR b = 1 TO n% - a
      IF c%(b) < c%(b + 1) OR (c%(b) = c%(b + 1) AND w$(b) > w$(b + 1)) THEN
        ti = c%(b)
        c%(b) = c%(b + 1)
        c%(b + 1) = ti
        ts$ = w$(b)
        w$(b) = w$(b + 1)
        w$(b + 1) = ts$
      END IF
    NEXT b
  NEXT a
END SUB
