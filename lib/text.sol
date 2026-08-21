; text.sol -- what more than one library needs for handling text.
;
;     @include "text.sol".
;     #233:asUtf8:display.        ; é
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; This exists because two libraries wanted the same twelve lines. Encoding a
; code point is subtle enough that having it written twice would be two things
; to get wrong, and `@include` already answers where shared code goes -- a file
; beside the others, included by both. It is the first library here to be
; included by another library rather than by a program.
;
; It binds **no global at all**, and that was not the first draft. The first
; draft bound one object called `text` and hung `utf8` off it, following the
; advice in the reference about claiming one name instead of a dozen. The first
; program to use it had a variable called `text`, and the library broke from a
; distance with `string does not understand 'utf8'` -- which is
; [ROADMAP 6.21](../docs/ROADMAP.md#621-two-libraries-binding-one-name-collide-silently)
; happening, in the ten minutes after it was written down.
;
; The lesson is not that the object idiom is wrong. It is that a namespace only
; helps if the name is one nobody else wants, and `text` is about the most
; wanted name there is. A method on a built-in class needs no name of its own,
; which is what control.sol does with its loops, and it is the better answer
; whenever the thing being added is behaviour on a value.

; A code point as the bytes UTF-8 spells it with.
;
; `asByte` and `asCharacter` give a byte a number; everything above 127 is more
; than one byte and is arithmetic on top of them. Solum has no bitwise
; operators, so the shifts and masks are `div` and `mod`, and the tag bits go on
; with `add` -- which is exact, the bits being disjoint by construction.
integer:asUtf8 := {
    self:lessThan(#0):or({ self:greaterThan(#1114111) }):ifTrue({
        error:raise("#{} is not a code point":fill([self])) }).
    self:lessThan(#128):ifElse(
        { self:asCharacter },
        { self:lessThan(#2048):ifElse(
            { #192:add(self:div(#64)):asCharacter
                  :concat(#128:add(self:mod(#64)):asCharacter) },
            { self:lessThan(#65536):ifElse(
                { #224:add(self:div(#4096)):asCharacter
                      :concat(#128:add(self:div(#64):mod(#64)):asCharacter)
                      :concat(#128:add(self:mod(#64)):asCharacter) },
                { #240:add(self:div(#262144)):asCharacter
                      :concat(#128:add(self:div(#4096):mod(#64)):asCharacter)
                      :concat(#128:add(self:div(#64):mod(#64)):asCharacter)
                      :concat(#128:add(self:mod(#64)):asCharacter) }) }) }) }.
