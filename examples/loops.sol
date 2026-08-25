; loops.sol -- the loops that live in the library rather than the language.
; Run with:  ./bin/solas examples/loops.sol && ./bin/solvm examples/loops.sob
;
; Named loops.sol rather than control.sol on purpose: a file that includes a
; library file of its own name would find *itself* beside it first, and -- a
; file being compiled once -- that include would quietly do nothing.

; One line brings the library in. There is no path here: `@include` looks beside
; this file first and then along the search path, and the library ships on it --
; so a program says what it wants, not where it lives.
@include "control.sol".

; ---------------------------------------------------------------------------
; None of this is language

; Control flow is message sending, so a loop is something a library can add --
; which is why the language has no syntax for any of these and does not need any.
;
; They all began in lib/control.sol, written in Solum. Four of them were then
; measured and moved into the VM, so `repeat`, `loopDo` and `doUntil` are
; primitives now and only `timesCollect` is still library code. Nothing you
; write below changes, which is the point: where a message lives is not part of
; what it means.

#3:repeat({ "tick":display }).            ; tick tick tick
{ "tock":display }:repeat(#2).            ; tock tock

; Both spellings exist because which reads better depends on which of the two
; the sentence is about: three of these, or this thing twice.

; ---------------------------------------------------------------------------
; doUntil is the one whileTrue cannot say

; `whileTrue` tests before the body runs, so a loop that must run at least once
; needs a flag declared outside it. The library writes that flag once, here, so
; that no program has to.

lines := #0.
{ lines := lines:add(#1) }:doUntil({ lines:greaterOrEqual(#3) }).
lines:print.                              ; #3

; Even when the condition is true from the start, the body has already run.
once := #0.
{ once := once:add(#1) }:doUntil({ true }).
once:print.                               ; #1

; ---------------------------------------------------------------------------
; Counted loops

; Inclusive at both ends, following `at` and `copyFrom`: an index here is an
; ordinal, and half-open ranges are what make zero-based indexing tidy.
[#1,#5]:loopDo({ n | n:display }).               ; 1 2 3 4 5

; With a step.
[#1,#10,#3]:loopDo({ n | n:display }).           ; 1 4 7 10

; A negative step counts down and stops when it passes the limit.
[#10,#7,#0:sub(#1)]:loopDo({ n | n:display }).   ; 10 9 8 7

; An empty range runs the body no times rather than complaining.
[#5,#1]:loopDo({ n | "never":display }).

; A step of #0 would never finish, so it says so instead of hanging.
;   [#1,#5,#0]:loopDo({ n | n })
;   ->  'loopDo' needs a step other than #0

; ---------------------------------------------------------------------------
; Gathering results

; `collect` maps an array that already exists; `timesCollect` makes one. The
; block is given the number of the pass, one-based like every other index.
#4:timesCollect({ n | n:mul(n) }):print.  ; [#1, #4, #9, #16]

; Which composes with everything else an array answers.
#6:timesCollect({ n | n })
    :select({ n | n:mod(#2):equals(#0) })
    :inject(#0, { total, n | total:add(n) })
    :print.                               ; #12 -- 2 + 4 + 6
