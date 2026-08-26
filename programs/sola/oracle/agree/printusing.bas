' PRINT USING -- the fiddliest formatting in BASIC, and the one place where
' guessing was never going to do. Every line here was measured against
' QuickBASIC 4.5 before a line of the formatter was written.
DEFINT A-Z
PRINT USING "###"; 5
PRINT USING "###"; -5
PRINT USING "###"; 1234
PRINT USING "###.##"; 3.14159#
PRINT USING "###.##"; -3.14159#
PRINT USING "#.##"; .5#
PRINT USING "#####,.##"; 1234567.891#
PRINT USING "+###"; 42
PRINT USING "+###"; -42
PRINT USING "###-"; -42
PRINT USING "**###"; 7
PRINT USING "$$###.##"; 12.5#
PRINT USING "**$##.##"; 12.5#
PRINT USING "value: ### units"; 9
PRINT USING "### ###"; 1; 2
PRINT USING "###"; 1; 2; 3
PRINT USING "!"; "hello"
PRINT USING "\   \"; "hello"
PRINT USING "&"; "hello"
PRINT USING "_####"; 7
PRINT USING "##.##^^^^"; 1234.5#
END
