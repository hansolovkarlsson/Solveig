' DIVERGENCE 5 -- STR$ does not add the leading space that BASIC's does.
'
' QBasic  " 42" -- a space where the minus would go
' Sola    "42"  -- PRINT adds the sign character, which is where BASIC puts it
'
' PRINT itself agrees; it is STR$ alone that differs, so this brackets its
' answer to make the difference visible.
PRINT "["; STR$(42); "]"
PRINT "["; STR$(-42); "]"
END
