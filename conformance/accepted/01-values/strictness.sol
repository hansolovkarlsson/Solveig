; conformance: types never coerce, so every conversion is written out
; varies: machine
;
; An integer does not combine with a float and a string does not join to a
; number. What makes that liveable is that the conversions are all there and
; each one names its direction.

#45:asFloat:add(1.5):print.
"12":asInteger:print.
"1.5":asFloat:print.
#12:asString:concat("!"):display.

; Bases are an integer's business, in both directions.
"ff":asInteger(#16):print.
%111101101:asBase(#8):display.
#255:asBase(#16):display.

#65:asCharacter:display.
"A":asByte:print.

"foo":asSymbol:equals('foo):print.
'foo:asString:display.
