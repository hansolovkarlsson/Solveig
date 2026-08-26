' A backward GOTO for the loop and a forward one over the code it skips.
i = 0
Top:
  i = i + 1
  PRINT "i = "; i
  IF i < 5 THEN GOTO Top
  GOTO Done
  PRINT "never printed"
Done:
  PRINT "counted to "; i
  END
