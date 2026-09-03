; conformance: an @expr region is notation -- every operator lowers to the send it reads as
; varies: front
;
; The region compiles to the bytes the chain would have compiled to, so a front
; end that gets the precedence wrong differs from the written-out form here and
; nowhere else. `*` and `/` bind tighter than `+` and `-`, `^` binds tighter
; still and groups to the right, and a comparison is looser than either.

@expr( #1 + #2 * #3 ):print.
#1:add(#2:mul(#3)):print.

@expr( 2.0 ^ 3.0 ^ 2.0 ):print.
@expr( -2.0 ^ 2.0 ):print.

; A comparison is looser than the arithmetic and '~' is looser than the
; comparison, so both of these are the reading the words have. The other reading
; does not merely answer differently -- it asks an integer for 'not', or asks
; 'add' to take a boolean, so a front end that binds them the other way fails
; here rather than disagreeing.
@expr( #1 + #2 = #3 ):print.
@expr( ~ (#1 = #2) ):print.
@expr( ~ #1 = #2 ):print.

; A prefix call is a send to its argument, and takes exactly one.
@expr( sqrt(9.0 + 7) ):print.
@expr( sqrt(9.0):abs ):print.

; '&' and '|' take a block, which is how they stop early.
@expr( true & false ):print.
@expr( true | false ):print.
