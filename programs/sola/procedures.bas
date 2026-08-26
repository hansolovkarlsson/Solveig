DECLARE SUB Greet (who$)
' --- a SUB, called both ways
SUB Greet (who$)
  PRINT "hello, "; who$
END SUB
CALL Greet("world")
Greet "again"

' --- a FUNCTION, answering by assigning to its own name
FUNCTION Square (x)
  Square = x * x
END FUNCTION
PRINT "5 squared is "; Square(5)

' --- recursion
FUNCTION Fact (n)
  IF n <= 1 THEN
    Fact = 1
  ELSE
    Fact = n * Fact(n - 1)
  END IF
END FUNCTION
PRINT "6! = "; Fact(6)

' --- by reference: the callee assigns to its parameter
SUB Double (v)
  v = v * 2
END SUB
a = 21
Double a
PRINT "doubled: "; a

' --- by reference, two of them, and the classic SWAP shape
SUB Exchange (p, q)
  t = p
  p = q
  q = t
END SUB
x = 1
y = 2
Exchange x, y
PRINT "swapped: "; x; " "; y

' --- brackets force a copy, which is QBasic's own spelling of by value
n = 10
Double (n)
PRINT "unchanged: "; n

' --- locals are local
SUB Shadow (v)
  t = 99
END SUB
t = 5
Shadow 1
PRINT "t is still "; t

' --- SHARED reaches the module's variable
total = 0
SUB AddOn (v)
  SHARED total
  total = total + v
END SUB
AddOn 3
AddOn 4
PRINT "total "; total

' --- STATIC survives between calls
SUB Counted
  STATIC seen
  seen = seen + 1
  PRINT "call number "; seen
END SUB
Counted
Counted
Counted

' --- EXIT SUB
SUB Maybe (v)
  IF v < 0 THEN EXIT SUB
  PRINT "positive "; v
END SUB
Maybe -1
Maybe 7
PRINT "done"
END
