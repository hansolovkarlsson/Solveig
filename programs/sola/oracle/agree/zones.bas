' Print zones, semicolons, TAB and SPC, and a separator that holds a line open.
DEFINT A-Z
PRINT 1, 2, 3
PRINT "a"; "b"; "c"
PRINT "left", "right"
PRINT TAB(10); "ten"
PRINT "x"; SPC(5); "y"
PRINT "open";
PRINT " continued"
PRINT
PRINT "after a blank"
FOR i = 1 TO 12
  PRINT i;
NEXT i
PRINT
END
