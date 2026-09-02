; sha2.pro -- the notation SHA-256 is written in, and the arithmetic it is
; defined over.
;
; A dialect, so directives and nothing else.
;
; ---------------------------------------------------------------------------
; Why the operators carry the mask
;
; SHA-256 is defined on mod-2^32 arithmetic. Solveig has one integer, signed
; 64-bit, and it **traps rather than wrapping** -- which is the right choice for
; a language and the wrong arithmetic for this algorithm. Solveig's own
; programs/sha256sum pays for the difference in twenty-three `bitAnd`s written
; out by hand, one after every addition that could carry past bit 31.
;
; Here the mask is in the operator. `a + b` is *addition modulo 2^32* in this
; file because the header says so, and there is no way to write the unmasked one
; by accident -- a dialect enforcing a rule rather than abbreviating one.
;
; The precedences are C's, because the FIPS 180-4 formulas are written for a
; reader who knows C: `+` binds tightest, then the shifts and the rotation, then
; `&`, then `^`. So `x & y ^ ~x & z` is `(x & y) ^ ((~x) & z)` here exactly as
; it is there.
;
; **Standalone, and not built on lib/arith.pro**, for a stronger reason than
; lib/clike.pro has: that file wants a different *shape*, and this one wants a
; different `+`. Composing them is a collision the compiler reports and then
; resolves by position -- `@use "arith.pro"` after this file silently buys
; addition that traps at bit 32 instead of wrapping at it. A dialect that
; redefines an operator cannot stand on one that defines it differently, and
; being told so by a warning is not the same as being safe.

@infix  +   60 => (left:add(right)):bitAnd(#4294967295).
@infix  -   60 => (left:sub(right)):bitAnd(#4294967295).

; `>>` needs no mask: a value under 2^32 shifted right stays under it. `<<`
; does, and Solveig's shift left refuses to lose the number rather than
; discarding it, so the mask is what makes it a 32-bit shift instead of an
; error.
@infix  >>  55 shiftRight.
@infix  <<  55 => (left:shiftLeft(right)):bitAnd(#4294967295).

; Rotate right, which the substrate has no message for and C has no operator
; for. It is the one place notation invents rather than renames.
@infix  >>> 55 => (left:shiftRight(right)):bitOr((left:shiftLeft(#32:sub(right))):bitAnd(#4294967295)).

; `*` and `%` are the plain ones, and that is not an inconsistency: SHA-256
; never multiplies, so nothing in the 32-bit domain can reach them. They are
; here for indices and lengths, which are not 32-bit quantities and must not be
; masked as if they were.
@infix  *   70 mul.
@infix  %   70 mod.

@infix  &   50 bitAnd.
@infix  ^   45 bitXor.
@infix  \   40 bitOr.

; `~x & z` is `(~x) & z`: a prefix operator takes the smallest thing it can, and
; then the infix ladder applies. Masked, because bitNot of a 32-bit value sets
; every bit above 31.
@prefix ~      => (operand:bitNot):bitAnd(#4294967295).

; ---------------------------------------------------------------------------
; The rest, so that this file needs nothing under it
;
; Comparisons and two control forms. They would have come from lib/arith.pro and
; lib/control.pro if `+` above had not made that file's `+` a collision.

@infix  ==  35 equals.
@infix  <   35 lessThan.
@infix  >   35 greaterThan.
@infix  >=  35 => (left:lessThan(right)):not.
@infix  <=  35 => (left:greaterThan(right)):not.
@infix  !=  35 => (left:equals(right)):not.

@syntax if <c> then <a>          => c:ifTrue({ a }).
@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).
@syntax while <t> do <b>         => { t }:whileTrue({ b }).
