' DIVERGENCE 1 -- there is no SINGLE, and the default numeric type is DOUBLE.
'
' QBasic  a bare name is a SINGLE, printed to about seven significant digits
' Sola    a bare name is a DOUBLE, so more digits come out
'
' This is the divergence most likely to surprise somebody porting a listing,
' and it is why every program in agree/ says its types outright.
x = 1 / 3
PRINT x
y = 2 / 7
PRINT y
END
