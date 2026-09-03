; conformance: split answers occurrences + 1 pieces and never drops one; replace does every occurrence
; varies: machine
;
; A separator at either end, or two together, gives an empty string where the
; missing piece would be -- which is what makes split and join a round trip.

"a,b,c":split(","):print.
"a,,b":split(","):print.
",a":split(","):print.
"a,":split(","):print.
"abc":split(","):print.
"":split(","):print.

"a,b,c":split(","):join(","):display.

"a-b-c":replace("-", "+"):display.
"one two one":replace("one", "1"):display.
"aaa":replace("aa", "b"):display.

; indexOf is one-based and answers nil rather than a sentinel number, so asking
; whether is `notNil` and there is no second message for it.
"hello":indexOf("l"):print.
"hello":indexOf("l", #4):print.
"hello":indexOf("z"):print.

; copyFrom includes both ends and is one-based, the array's rule exactly.
"hello":copyFrom(#2, #4):display.
"hello":at(#1):display.
"hello":size:print.

"  padded  ":trim:display.
"MiXeD":asUppercase:display.
"MiXeD":asLowercase:display.
