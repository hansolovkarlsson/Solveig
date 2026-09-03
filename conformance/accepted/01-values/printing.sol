; conformance: print shows the literal form, display the text, and an array shows its elements literally
; varies: machine
;
; `print` writes the form that would read back as the same value and `display`
; writes the text. The difference is visible on exactly the values that have
; two forms -- a string, a symbol, and the two numeric types.

#45:print.
#45:display.
45:print.
45:display.

"a":print.
"a":display.
'b:print.
'b:display.

; An element inside an array is always shown in its literal form, so that a
; printed array reads back as one.
["a", 'b, #1, 2, nil, true]:print.
["a"]:display.

nil:print.
true:print.
false:print.

; asString answers the text display writes, as a string.
#45:asString:display.
"a":asString:display.
