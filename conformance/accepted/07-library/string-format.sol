; conformance: the asString spec is [align] [','] ['0'] [width] ['.' decimals], in that order
; varies: machine
;
; The flags have one order, so there is one way to write a given spec. A value
; wider than the width is never cut, numbers align right by default and
; everything else left, and zero fill goes after any sign.

45.8:asString("6.2"):print.
45.8:asString("08.2"):print.
#1234567:asString(","):print.
1234.5:asString(",10.2"):print.
#45:asString("<6"):print.
"ab":asString(">6"):print.
"ab":asString("^6"):print.
#-45:asString("06"):print.

; A value wider than the width keeps all of itself.
#1234567:asString("3"):print.

; fill puts the array's values into the {} blanks, rendering each by sending it
; asString. '{{' writes a literal brace and '}' is never special.
"you have {} apples":fill([#3]):display.
"{} by {}":fill([#24, #80]):display.
"{{}}":fill([]):display.
"{{}":fill([]):display.
"a } b":fill([]):display.
