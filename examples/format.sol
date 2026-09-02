; Getting text out: three messages that look similar and are not.
; Run with:  ./bin/solas examples/format.sol && ./bin/solvm examples/format.sob

; `print` shows the LITERAL form -- what you would type to get this value back.
; `display` writes the TEXT. `asString` answers that same text as a string.
#45:print.                       ; #45
#45:display.                     ; 45
#45:asString:print.              ; "45"    -- a string, so print quotes it

"a\"b":print.                    ; "a\"b"  -- escaped, so it reads back
"a\"b":display.                  ; a"b     -- the characters themselves

; Inside an array, elements are always shown in literal form, so a printed
; array reads back as one.
["a", #1]:print.                 ; ["a", #1]
["a", #1]:display.               ; ["a", #1]

; ---------------------------------------------------------------------------
; A format spec, as an argument to asString
;
;     [align] [','] ['0'] [width] ['.' decimals]
;
; There is deliberately no conversion letter -- the receiver knows its own type,
; so there is nothing that could contradict it -- and no sign mode, because a
; leading space for a positive number falls out of the width.

45.8:asString("6.2"):display.    ;  45.80 -- width 6, two decimals
45.8:asString("08.2"):display.   ; 00045.80 -- zero fill
#-45:asString("06"):display.     ; -00045 -- zeros go after the sign

; Numbers align right and text aligns left. '<' '>' '^' override that.
"ab":asString(">6"):print.       ; "    ab"
"ab":asString("<6"):print.       ; "ab    "
"ab":asString("^6"):print.       ; "  ab  "

; A value wider than the width is never cut: losing digits would be worse than
; a ragged column.
#1234567:asString("3"):display.  ; 1234567

; ',' groups whole-number digits in threes, and only those -- a sign, a
; fraction, and an exponent all pass through untouched.
#1234567:asString(","):display.        ; 1,234,567
1234.5:asString(",10.2"):display.      ;   1,234.50   -- grouped, width 10
#-1234567:asString(","):display.       ; -1,234,567

; Decimals belong to floats. Asking an integer for them is an error, not a
; no-op:
;   #45:asString("6.2").          ; solvm: decimals mean nothing for an integer

; ---------------------------------------------------------------------------
; Filling a template

; '{}' takes the next value and renders it by SENDING it asString, so a type
; that defines its own is honoured rather than bypassed.
"you have {} apples and {} pears":fill([#3, #4]):display.

; Placeholders and values must match exactly. Too few and too many are both
; errors, because filling a gap with blanks would turn a mistake into output
; that looks deliberate.
;   "{} and {}":fill([#1]).
;       solvm: 'fill' has more placeholders than the 1 value given

; '{{' writes a literal brace. '}' is never special and needs no escape, so
; '}}' is simply two of them. These are the template's escapes, so they mean
; something to `fill` and nothing to `display`, which just writes characters.
"{{} is a brace, }} is two":fill([]):display.

; ---------------------------------------------------------------------------
; Putting them together: a column of figures

row := { name, qty, cost |
    "{}{}{}":fill([ name:asString("<10"),
                    qty:asString("5"),
                    cost:asString(",12.2") ])
}.

"stock report":display.
row:value("apples", #3, 1234.5):display.
row:value("pears", #12, 99.75):display.
row:value("quinces", #1234, 7.5):display.

; Padding for a based number comes from the spec, by chaining -- which is why
; bases are a message rather than a letter in the spec.
#255:asBase(#16):asString("08"):print.        ; "000000ff"
#255:asBase(#16):asUppercase:print.           ; "FF"

; An object is rendered by asking it, so one that defines asString is shown that
; way by print, by display, by fill, and inside an enclosing array -- one
; definition serving all four.
point := object:new.
point:x := #0. point:y := #0.
point:asString := {
    "(":concat(self:x:asString):concat(", "):concat(self:y:asString):concat(")")
}.
p := point:new. p:x := #3. p:y := #4.

p:display.                       ; (3, 4)
"the point is {}":fill([p]):display.
[p, p]:print.                    ; [(3, 4), (3, 4)]
