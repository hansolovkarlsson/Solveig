; conformance: a symbol is interned, so equals is identity -- and the order it has is the text's
; varies: machine
;
; Interning is what makes equals a pointer comparison and exactly what makes the
; pointers say nothing about order, so the four comparison messages are the only
; symbol operations that look at the characters. A symbol never equals a string.

'foo:equals('foo):print.
"foo":asSymbol:equals('foo):print.
'foo:equals("foo"):print.
"foo":equals('foo):print.

'foo:asString:display.
'foo:size:print.

'apple:lessThan('pear):print.
'pear:lessThan('apple):print.
'fig:lessOrEqual('fig):print.

; Which is what lets an array of symbols sort: `sorted` with no block sends
; lessThan, and a tally kept under symbol keys needs a stable order to print in.
['pear, 'apple, 'fig]:sorted:print.
