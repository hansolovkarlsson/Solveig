' DIVERGENCE 2 -- INTEGER is 64 bits here and 16 bits in QBasic.
'
' MEASURED, and the prediction written here first was wrong. It said QuickBASIC
' would stop with an overflow. It does not:
'
'   QBasic  -32768, having wrapped
'   Sola     32768, having not
'
' BC.EXE compiles without overflow checking unless /D asks for it, so the
' compiled program wraps where the QB.EXE environment would have raised
' Overflow. Either way a listing that leans on 32767 being the top will not
' behave here -- and it will not fail, which is worse than failing differently.
DIM x AS INTEGER
x = 32767
x = x + 1
PRINT x
END
