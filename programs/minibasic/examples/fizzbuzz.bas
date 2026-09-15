10 REM FizzBuzz. Line 40 adds a string to a string and line 20 counts
20 REM an integer, which is why `+` is a send in basic.pro and not an operator
30 FOR I = 1 TO 20
40 LET S = ""
50 IF I / 3 * 3 = I THEN LET S = S + "Fizz"
60 IF I / 5 * 5 = I THEN LET S = S + "Buzz"
70 IF S = "" THEN PRINT I
80 IF S <> "" THEN PRINT S
90 NEXT I
100 END
