; control.sol -- what is left that the language does not have.
;
;     @include "control.sol".
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; This file is nearly empty, and that is the record of something rather than an
; oversight: it opened with five loops in it, four were measured, and all four
; were worth building into the VM. What is left is the one nobody has measured.
;
; The machinery around it -- the search path, `@include` finding a name it was
; not told the location of -- is what matters and is unchanged. This is where
; the next thing goes.
;
; This file binds names and does nothing else. A library that printed something
; when you included it would be a poor guest.

; ---------------------------------------------------------------------------
; repeat and the counted loop are not here any more
;
; Nor is doUntil. All four started in this file, written in Solum, and all four
; turned out to be worth building into the VM -- which is what ROADMAP 6.6 was
; asking, though it expected the answer to be compiler inlining rather than
; primitives. Measured, a primitive `repeat` is 3.2x the version that lived here
; and 2.5x what inlining would have produced: inlining removes the block call
; per iteration and keeps two bytecode sends for the counter, where a primitive
; removes the two sends and keeps the block call. The sends cost more.
;
; Defining any of them here again would be a trap rather than an override. A
; slot bound on `integer` shadows the primitive, so the slow version would
; quietly win -- and for doUntil the compiler splices the loop in anyway, so a
; definition would be bypassed exactly where it was most wanted.

; ---------------------------------------------------------------------------
; timesCollect -- n results, gathered
;
;     #4:timesCollect({ n | n:mul(n) }):print.   ; [#1, #4, #9, #16]
;
; `collect` maps an array that already exists; this makes one. The block is
; given the number of the pass, one-based, like every other index here.

integer:timesCollect := { body | | out, i |
    out := array:new.
    i := #1.
    { i:lessOrEqual(self) }:whileTrue({ out:add(body:value(i)). i := i:add(#1) }).
    out
}.

; ---------------------------------------------------------------------------
; ifElseIf -- a chain of alternatives, written flat
;
;     kind := [
;         { c:equals("#") },  { self:integer },
;         { c:equals("\"") }, { self:string },
;         { c:equals("'") },  { self:symbol },
;                             { self:error("unexpected character") }
;     ]:ifElseIf.
;
; Pairs of blocks: a condition and what to do when it holds. The first condition
; that answers true wins, its action's value is the answer, and nothing after it
; runs -- neither the later conditions nor their actions. **An odd number of
; blocks means the last one is the else**, which is why there is no marker for
; it: a list of pairs with one left over is exactly a list of pairs and a
; default. With an even number and no match, the answer is nil.
;
; Lisp calls this `cond` and has since 1958. The name here says what it is to
; somebody who has not met that.
;
; **This is the thing nested `ifElse` is bad at.** Written as a chain, six
; alternatives are six levels of nesting and a wall of `}) }) })` at the end;
; the reader has to count brackets to see which branch they are in, and adding a
; case in the middle re-indents everything below it. Flat, the cases line up and
; the last one is the default because it is last.
;
; ---------------------------------------------------------------------------
; What it costs, which decides where to use it
;
; A nested `ifElse` written literally compiles to **jumps**, with no blocks made
; and no frames entered. This makes a block call per condition tested and one
; for the action, and pays for it twice:
;
;   speed  200,000 six-way dispatches: 0.145s as a chain, 0.835s here. **5.8x.**
;   depth  recursion through it costs **three frames a level** rather than none,
;          so a recursive method that reaches 254 levels as a chain reaches 84.
;
; So: **use it for a flat dispatch and not inside a recursion.** A scanner
; deciding what a character starts, or a reader deciding what a tag means, is
; exactly the shape this is for -- the frames are transient there, peaking at
; three rather than accumulating, and the legibility is free. A recursive
; descent spends a third of its depth on it, which is the wrong trade in a
; language whose depth is 254.
;
; ---------------------------------------------------------------------------
; And what a primitive would buy, which was measured when something finally
; used this in anger
;
; Four loops left this file for the VM once measuring said they were worth
; building in, and the obvious next question is whether this should follow.
; [programs/basic.sol](../programs/basic.sol) is the second program to reach for
; it, after `disasm.sol`, so there was something to measure at last. Both halves
; were, and **the answer is that a primitive fixes neither problem fully**:
;
;   speed  200,000 six-way dispatches landing on the third arm: 0.08s as a
;          chain, 0.49s here, and **0.15s** for the four block calls alone with
;          nothing else -- which is the floor a primitive could reach, since the
;          block calls are the part it cannot remove. So about **3.3x**, in line
;          with what `repeat` got, and still 2x the inlined chain.
;
;   depth  a recursion reaches 251 levels plain, **125** with one extra block
;          call per level, and **83** through this. The three frames are: this
;          method, the condition block, the action block -- and the action
;          block's frame is live while the recursion continues, so a primitive
;          takes three to **two** and no lower.
;
; **Two is still twice one.** `basic.sol` reads 60 brackets deep with a
; staircase in its `primary` and 39 with `ifElseIf` there; a primitive would put
; that near 46. So the advice above does not change -- a recursive descent still
; wants the staircase -- which is the useful half of the measurement, because it
; says the thing a primitive would be *for* is not the thing it would fix.
;
; And nothing is hot on it. The tokeniser in `basic.sol` runs this once per
; character **at load**, which is 5ms for a listing anybody types; 3.3x of that
; is 3.5ms, once. What would change the answer is a program running it per
; iteration of something rather than per character of something read once.
;
; **No early exit** ([3.13](../docs/ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing)),
; so the loop carries a flag whose only job is to stop it -- the tenth site in
; this repository to do that, and one more argument for that entry.

array:ifElseIf := { | i, answer, done |
    i := #1.
    done := false.
    answer := nil.
    { done:not:and({ i:lessThan(self:size) }) }:whileTrue({
        self:at(i):value:ifElse(
            { answer := self:at(i:inc):value. done := true },
            { i := i:add(#2) }) }).

    ; One block left over is the else. `i` lands on it exactly when the pairs
    ; ran out without matching and there is an odd one at the end.
    done:not:and({ i:equals(self:size) }):ifTrue({ answer := self:at(i):value }).
    answer }.
