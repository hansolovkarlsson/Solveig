; text.sol -- what more than one library needs for handling text.
;
;     @include "text.sol".
;     #233:asUtf8:display.        ; é
;     "notes.md":endsWith(".md"):print.   ; true
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
; [6.21](../docs/COMPLETED.md#621-two-libraries-binding-one-name-collide-silently--done)
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
; than one byte, and putting those bytes together is what the shifts and masks
; below are for.
;
; This was written before the language had them, with `div(#64)` for a shift and
; `mod(#64)` for a mask and `add` for the tag bits -- exact, since the bits are
; disjoint by construction, and nothing like what it means. Reading it against
; the table in RFC 3629 meant translating every line. Carrying that here is what
; made the case for `shiftRight`, `bitAnd` and `bitOr`.

; The continuation bytes are all the same shape: the tag 10xxxxxx over six bits
; of the code point, taken `at` bits from the bottom.
integer:utf8Tail := { at | #128:bitOr(self:shiftRight(at):bitAnd(#63)):asCharacter }.

integer:asUtf8 := {
    self:lessThan(#0):or({ self:greaterThan(#1114111) }):ifTrue({
        error:raise("#{} is not a code point":fill([self])) }).
    self:lessThan(#128):ifElse(
        { self:asCharacter },
        { self:lessThan(#2048):ifElse(
            { #192:bitOr(self:shiftRight(#6)):asCharacter
                  :concat(self:utf8Tail(#0)) },
            { self:lessThan(#65536):ifElse(
                { #224:bitOr(self:shiftRight(#12)):asCharacter
                      :concat(self:utf8Tail(#6))
                      :concat(self:utf8Tail(#0)) },
                { #240:bitOr(self:shiftRight(#18)):asCharacter
                      :concat(self:utf8Tail(#12))
                      :concat(self:utf8Tail(#6))
                      :concat(self:utf8Tail(#0)) }) }) }) }.


; ---------------------------------------------------------------------------
; Does this text begin, or end, with that text
;
; Both were written three times before they were written here: in
; [server.sol](../extensions/net/server.sol), which found the gap and left a
; comment saying so; in [expect.sol](../programs/expect.sol), which wrote
; `string:endsWith` in this exact shape; and in
; [plugins.sol](../examples/plugins.sol), which wrote it again as a local block.
; Two independent copies of one function is the trigger this repository built
; `replace` on.
;
; **The absence had already cost a defect.** Asking whether a name contains
; `.md` rather than ends with it called `draft.md.orig` a document, and would
; have handed `a.md.sol` to the markdown checker. Nothing in the tree was named
; that way, which is how it went unnoticed until the code was read.
;
; **And `indexOf(x):equals(#1)` is not the same question as `startsWith(x)`,
; which was the reason for deferring these and was wrong.** A search that fails
; has read the whole string, and failing is exactly what a prefix test is for.
; On 128 KB of text not containing the needle, 2000 calls each, that measured
; 308 microseconds against 150 nanoseconds -- a prefix test is O(prefix), the
; search is O(text). One of the call sites it replaces reads a UDP payload,
; where the text's length is a stranger's choice.
;
; **The size test is not an optimisation, it is what makes these total.**
; `copyFrom` answers `""` for an empty range and for a start past the end, but
; refuses an end past it -- so without the guard `"ab":startsWith("abc")` would
; raise rather than answer false, and `"ab":endsWith("abc")` would ask for index
; `#0`. With it, an empty affix answers true and every string has one.

string:startsWith := { prefix |
    self:size:greaterOrEqual(prefix:size):and({
        self:copyFrom(#1, prefix:size):equals(prefix) }) }.

string:endsWith := { suffix |
    self:size:greaterOrEqual(suffix:size):and({
        self:copyFrom(self:size:sub(suffix:size):add(#1), self:size)
            :equals(suffix) }) }.
