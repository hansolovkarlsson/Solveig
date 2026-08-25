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
; And at the time that was measured, nothing was hot on it: the tokeniser in
; `basic.sol` runs this once per character **at load**, which is 5ms for a
; listing anybody types.
;
; ---------------------------------------------------------------------------
; Then something was, and the number is worth having
;
; The paragraph above said what would change the answer -- *a program running it
; per iteration of something* -- and `basic.sol` grew one the same day. Every
; `IF` in a running listing goes through one dispatch, and a loop of 20,000
; iterations driven by `IF` and `GOTO` ran in **0.246s** as a staircase and
; **0.30s** through this. **Twenty-two per cent of the whole interpreter**, for
; six arms. It went back to the staircase.
;
; **So both edges of the niche are now measured, and the niche is narrow.** This
; is out of the recursive dispatches on depth and out of the hot one on speed,
; and what is left to it is the flat, cool, many-armed case: a tokeniser, and
; `disasm.sol` reading constant tags. Where a hot dispatch has *many* arms it
; wants a dictionary rather than either of these, because a dictionary asks one
; question instead of n.
;
; That is the honest case for and against a primitive, and it points both ways.
; For: a program reached for this in a hot path, measured it, and had to give it
; up -- which is exactly what happened to the four loops before they were built
; in. Against: what it had to give it up *for* was a six-arm staircase that
; reads perfectly well, and a primitive at 3.3x would still be slower than one.
; The decision wants a site with many arms, arbitrary conditions and a hot loop,
; and no program here has had one yet.
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
