; conformance: values are equal when they say the same thing, references when they are the same one
; varies: machine
;
; Numbers, strings and symbols are immutable, so two are equal when they spell
; the same thing and sharing is always safe. Arrays, blocks and objects are
; equal only to themselves, so `a := b` makes two names for one thing rather
; than a copy.

a := "hi". b := "hi". a:equals(b):print.
c := [#1]. d := [#1]. c:equals(d):print.
e := c. e:equals(c):print.

'foo:equals('foo):print.
"foo":equals('foo):print.

; The two numeric types never meet, equality included.
#1:equals(1):print.
#1:equals(#1):print.

; notEquals is the negative of it and not a separate rule.
"hi":notEquals("ho"):print.
