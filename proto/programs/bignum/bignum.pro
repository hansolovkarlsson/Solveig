; bignum.pro -- arbitrary-precision natural numbers, as a library.
;
;     proto bignum.pro -o bignum.sol
;
; and then `@include "bignum.sol".` from the program that wants it. This file
; binds one global, `big`, and everything else hangs off it. calc.pro is the
; program that uses it; README.md is what the two of them were written to
; find out.
;
; Written in limbs.pro, where `base`, `digit(t)` and `carry(t)` come from and
; where the operators are lib/arith.pro's: `+` on two limbs is Solveig's add,
; and `*` on two bignums is `mul` below, by dispatch and not by declaration.

@use "limbs.pro".

; ------------------------------------------------------------------- shape
;
; An instance holds `limbs`, least significant first, with no zero limb at the
; top, so that two equal numbers have equal arrays and zero is the empty one.
; `from` is the one constructor everything else goes through, and it is where
; that invariant is kept.

big := object:new.
big:limbs := array:new.

big:from := { limbs | | b |
    while limbs:size > #0 && limbs:at(limbs:size) == #0 do limbs:removeLast.
    b := self:new.
    b:limbs := limbs.
    b }.

; A non-negative Solveig integer, taken apart a limb at a time.
big:fromInteger := { n | | limbs |
    if n < #0 then error:raise("bignum: a natural number cannot be negative").
    limbs := array:new.
    while n > #0 do (limbs:add(digit(n)). n := carry(n)).
    self:from(limbs) }.

; Decimal text, cut into limbs from the right, `width` digits at a time.
big:fromString := { s | | limbs, hi, lo |
    limbs := array:new.
    hi := s:size.
    while hi > #0 do (
        lo := hi - width + #1.
        if lo < #1 then lo := #1.
        limbs:add(s:copyFrom(lo, hi):asInteger).
        hi := lo - #1).
    self:from(limbs) }.

; The top limb as it is, and every one below it padded to `width`, because
; a limb of 7 in the middle of a number is nine characters wide.
big:asString := { | a, out, i |
    a := self:limbs.
    if a:size == #0 then "0" else (
        out := a:at(a:size):asString.
        i := a:size - #1.
        while i >= #1 do (
            out := out:concat(a:at(i):asString("09")).
            i := i - #1).
        out) }.

; --------------------------------------------------------------- comparing

; -1, 0 or 1. Longer is larger, since there is no zero limb at the top; equal
; lengths are decided from the top down.
big:compare := { other | | a, b, i, r |
    a := self:limbs. b := other:limbs.
    if a:size != b:size then (
        if a:size < b:size then #-1 else #1)
    else (
        r := #0.
        i := a:size.
        while r == #0 && i >= #1 do (
            if a:at(i) < b:at(i) then r := #-1.
            if a:at(i) > b:at(i) then r := #1.
            i := i - #1).
        r) }.

big:equals         := { other | self:compare(other) == #0 }.
big:notEquals      := { other | self:compare(other) != #0 }.
big:lessThan       := { other | self:compare(other) == #-1 }.
big:greaterThan    := { other | self:compare(other) == #1 }.
big:lessOrEqual    := { other | self:compare(other) != #1 }.
big:greaterOrEqual := { other | self:compare(other) != #-1 }.

; ---------------------------------------------------------------- arithmetic

big:add := { other | | a, b, r, n, i, c, t |
    a := self:limbs. b := other:limbs.
    n := if a:size > b:size then a:size else b:size.
    r := array:new.
    c := #0.
    i := #1.
    while i <= n do (
        t := c.
        if i <= a:size then t := t + a:at(i).
        if i <= b:size then t := t + b:at(i).
        r:add(digit(t)).
        c := carry(t).
        i := i + #1).
    if c > #0 then r:add(c).
    big:from(r) }.

; Natural numbers only, so the receiver must be the larger. Below zero is an
; error rather than a wrapped value, which is the same choice Solveig's own
; integer makes at its edge.
big:sub := { other | | a, b, r, i, c, t |
    a := self:limbs. b := other:limbs.
    r := array:new.
    c := #0.
    i := #1.
    while i <= a:size do (
        t := a:at(i) - c.
        if i <= b:size then t := t - b:at(i).
        if t < #0 then (t := t + base. c := #1) else c := #0.
        r:add(t).
        i := i + #1).
    if c > #0 || b:size > a:size then
        error:raise("bignum: subtraction below zero").
    big:from(r) }.

; Schoolbook. The inner line is the whole reason the base is what it is: a
; limb product is below base squared, and adding a limb and a carry to it
; stays below base squared, which is below 2^63. Everything about the
; representation is in that one inequality.
big:mul := { other | | a, b, r, i, j, ai, c, t |
    a := self:limbs. b := other:limbs.
    r := array:new.
    (a:size + b:size):repeat({ r:add(#0) }).
    i := #1.
    while i <= a:size do (
        ai := a:at(i).
        c := #0.
        j := #1.
        while j <= b:size do (
            t := r:at(i + j - #1) + ai * b:at(j) + c.
            r:atPut(i + j - #1, digit(t)).
            c := carry(t).
            j := j + #1).
        r:atPut(i + b:size, c).
        i := i + #1).
    big:from(r) }.

; Division by a Solveig integer below the base, from the top limb down; `div`
; answers the quotient as a bignum and `mod` the remainder as an integer.
; Dividing one bignum by another is not here, because no program has asked.
big:div := { d | | a, q, i, rem, t |
    if d <= #0 || d >= base then error:raise("bignum: div wants #1 to one below the base").
    a := self:limbs.
    q := array:new.
    a:size:repeat({ q:add(#0) }).
    rem := #0.
    i := a:size.
    while i >= #1 do (
        t := rem * base + a:at(i).
        q:atPut(i, t / d).
        rem := t % d.
        i := i - #1).
    big:from(q) }.

big:mod := { d | | a, i, rem |
    if d <= #0 || d >= base then error:raise("bignum: mod wants #1 to one below the base").
    a := self:limbs.
    rem := #0.
    i := a:size.
    while i >= #1 do (
        rem := (rem * base + a:at(i)) % d.
        i := i - #1).
    rem }.

; Square and multiply. `*` here is lib/arith.pro's, and it reaches `mul`
; above because the operands are bignums -- the same declaration that adds
; two limbs in `add`. That is README.md's prediction 2, inside the library
; as much as outside it.
big:pow := { e | | result, b |
    if e < #0 then error:raise("bignum: a negative power is not a natural number").
    result := big:fromInteger(#1).
    b := self.
    while e > #0 do (
        if e % #2 == #1 then result := result * b.
        e := e / #2.
        if e > #0 then b := b * b).
    result }.
