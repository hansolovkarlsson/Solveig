; math.sol -- the comparisons a program keeps writing out by hand.
;
;     @include "math.sol".
;     #3:min(#7):print.           ; #3
;     [4.0, 1.0, 9.0]:max:print.  ; 9.0
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; Every method here was written out longhand somewhere first, and that is the
; whole of the case for the file -- see
; [3.14](../docs/ROADMAP.md#314-there-is-no-source-of-randomness):
;
;   `min` and `max` over an array   programs/bench.sol, as two `inject` folds
;   `max` of two values             programs/bench.sol, as a clamp on a rank
;   `between`                       lib/json.sol, three times, as a surrogate
;                                   range; programs/bench.sol, as "does this
;                                   interval contain 1"
;
; **Nothing here is language, and nothing here needed to be.** These are ordinary
; Solum methods bound on `integer`, `float` and `array`, which is the same thing
; control.sol does with a loop. `sqrt` is a primitive and these are not, and the
; difference is not importance: `sqrt` needs the C library to be correct at all,
; and a comparison needs nothing this language does not already have.
;
; They cost a block call and a frame per use, which is the measured lesson
; control.sol records after four of its loops turned out to be worth building
; into the VM. Nothing here is in a hot loop today. The moment something is,
; measure it before promoting it -- that file is the record of what measuring
; found, twice.
;
; It binds **no global**, following text.sol: a method on a built-in class needs
; no name of its own, and `math` is a name a program is entitled to want.

; ---------------------------------------------------------------------------
; Two values
;
; Written once per type rather than once, because there is no `number` between
; these two and `object` to hang them on -- integer and float are siblings under
; the single root, and the one hierarchy is deliberate
; (../docs/one-hierarchy.md). The bodies are identical because `lessThan` is all
; they use and both types have it.
;
; `min` and `max` answer the receiver when the two are equal, which matters only
; for telling them apart and cannot here, both being values.

integer:min := { other | other:lessThan(self):ifElse({ other }, { self }) }.
integer:max := { other | self:lessThan(other):ifElse({ other }, { self }) }.

float:min := { other | other:lessThan(self):ifElse({ other }, { self }) }.
float:max := { other | self:lessThan(other):ifElse({ other }, { self }) }.

; Inclusive at both ends, which is the reading the four sites that wrote it out
; longhand all wanted: a surrogate range and a confidence interval both include
; what they name.
integer:between := { low, high |
    self:greaterOrEqual(low):and({ self:lessOrEqual(high) }) }.

float:between := { low, high |
    self:greaterOrEqual(low):and({ self:lessOrEqual(high) }) }.

; ---------------------------------------------------------------------------
; A whole array
;
; No type is named, so these work on anything that answers `lessThan` -- strings
; sort, so an array of them has a smallest.
;
; An empty array raises rather than answering nil. There is no smallest element
; of nothing, and a nil travelling on into arithmetic would fail somewhere else
; with a message about the somewhere else. Letting `at(#1)` complain about an
; index would name the implementation rather than the mistake.

array:min := {
    self:size:equals(#0):ifTrue({ error:raise("'min' of an empty array") }).
    self:inject(self:at(#1), { a, b | b:lessThan(a):ifElse({ b }, { a }) }) }.

array:max := {
    self:size:equals(#0):ifTrue({ error:raise("'max' of an empty array") }).
    self:inject(self:at(#1), { a, b | a:lessThan(b):ifElse({ b }, { a }) }) }.
