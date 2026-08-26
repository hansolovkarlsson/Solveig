' PRINT's rules, which are the part of BASIC everyone remembers wrongly.
' A number is a sign character -- a minus, or a space where one would go --
' then the digits, then a trailing space. A string gets neither.
PRINT 14
PRINT -7
PRINT 2.5
PRINT .5
PRINT -.5
PRINT "text"
' A comma moves to the next print zone; a semicolon moves nowhere.
PRINT 1, 2, 3
PRINT "a"; "b"; "c"
' A separator at the end of the line holds the line open.
PRINT "open";
PRINT " continued"
PRINT "held",
PRINT "zone"
' TAB puts the next thing in a column; SPC counts spaces from where it is.
PRINT TAB(10); "at ten"
PRINT "x"; SPC(5); "y"
' PRINT with nothing after it ends the line it is on.
PRINT
PRINT "after a blank line"
' A line built a piece at a time, and wrapped at the margin of 80.
FOR i = 1 TO 30
  PRINT i;
NEXT i
PRINT
' A line left open still goes out before the program stops.
PRINT "no newline was written after this";
END
