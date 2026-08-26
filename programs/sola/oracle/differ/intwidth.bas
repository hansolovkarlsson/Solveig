' DIVERGENCE 2 -- INTEGER is 64 bits here and 16 bits in QBasic.
'
' QBasic  overflow, and the program stops
' Sola    32768, and the program carries on
'
' A listing that relies on the overflow will not fail here, which is worse than
' failing differently.
DIM x AS INTEGER
x = 32767
x = x + 1
PRINT x
END
