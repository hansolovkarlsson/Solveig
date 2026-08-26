' CB80's rule: a label is a string of characters, not a number. So these need
' not ascend, the listing jumps past one that is never reached, and nothing in
' the compiler sorts them.
100 PRINT "at one hundred"
GOTO 50
30 PRINT "never reached"
50 PRINT "at fifty, which is written after one hundred"
END
