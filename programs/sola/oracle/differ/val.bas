' DIVERGENCE 6 -- VAL is strict here and lenient in QBasic.
'
' QBasic  12, having read a number off the front and stopped
' Sola    the program fails, because the whole string has to be a number
'
' Reading a number out of the front of text wants a scanner, and there is no
' library in the file this compiler writes to hold one.
PRINT VAL("3.5")
PRINT VAL("12ab")
END
