; conformance: '#[' is one token, and a dictionary key is a sum rather than an expression
; varies: front
;
; The '[' must follow the '#' immediately, the way a digit must. A scanner that
; reads '#' and '[' separately produces an array literal of one comparison and
; not a dictionary.

d := #["a" = #1, "b" = #2].
d:size:print.
d:at("a"):print.
d:at("b"):print.

; The value is a whole expression; only the key is narrow.
e := #["k" = #1:add(#2)].
e:at("k"):print.

; And an array literal is the other reading of the same characters.
a := [#1, #2].
a:size:print.
