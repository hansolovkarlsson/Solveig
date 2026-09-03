; conformance: a number literal's tag says which of the two numeric types it is
; varies: both
;
; '#' marks an integer and its absence marks a float, so the same digits are two
; different values of two different types. '$' and '%' write an integer in
; hexadecimal and binary and carry no tag, there being no float in either base.

#45:print.
45:print.
#-45:print.

$FF08:print.
$ff08:print.
%10101100:print.

1e3:print.
1.5e-3:print.
1E+3:print.

; A whole float prints without a point, which is how the two are told apart on
; the page. An integer prints with its tag for the same reason.
0.5:print.
2:print.
