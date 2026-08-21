; system.sol -- the process, rather than any value.
; Run with:  ./bin/solas examples/system.sol && ./bin/solvm examples/system.sob one two
;
; `system` is not a class and has no instances. It is one object with slots,
; bound to a global like `integer` or `object` is -- the natural home for what
; is about the program rather than about a value.

; ---------------------------------------------------------------------------
; What the program was given
;
; An array of strings: everything on the command line after the .sob file.
; It is the empty array when there were none and never nil, so it can be walked
; without first asking whether it is there.

"{} argument(s):":fill([system:arguments:size]):display.
system:arguments:do({ a | "  {}":fill([a]):display }).

; It is a data slot rather than a method, because it is data -- the same array
; every time you ask, not a fresh one.
system:arguments:equals(system:arguments):print.        ; true

; ---------------------------------------------------------------------------
; What time it is
;
; `clock` answers monotonic seconds as a float. The epoch is deliberately
; unspecified: the only thing worth doing with two readings is subtracting
; them, and a wall clock can go backwards in between.

start := system:clock.
i := #0.
{ i:lessThan(#100000) }:whileTrue({ i := i:add(#1) }).
elapsed := system:clock:sub(start).

"counted to {} in {} seconds":fill([i, elapsed:asString("0.4")]):display.

; ---------------------------------------------------------------------------
; Timing a block
;
; `timeToRun` does the same thing without the bookkeeping: it answers the
; seconds the block took, as a float. The block's own answer is dropped -- what
; was wanted was the time.

{ | n | n := #0. { n:lessThan(#100000) }:whileTrue({ n := n:add(#1) }) }
    :timeToRun:asString("0.4"):display.

; The clock has a floor -- a microsecond on the machine this was written on --
; and one send and one add costs a small fraction of that. So a single run
; answers the floor rather than the block: 0 most times, and one whole
; microsecond when the two readings fall either side of a tick.
{ #1:add(#1) }:timeToRun:print.                  ; 0, or 0.000001

; Which is what the count is for. It runs the block that many times and answers
; the total, so dividing gives the cost of one.
total := { #1:add(#1) }:timeToRun(#200000).
total:greaterThan(0.0):print.                    ; true
total:div(200000.0):asString(".9"):display.      ; seconds for one send and one add

; ---------------------------------------------------------------------------
; Stopping
;
; `exit` is a message like any other, and it unwinds rather than leaving from
; under the machine: everything printed so far is flushed on the way out, and
; nothing after it runs. A status is #0 to #255, and #0 means it went well.

system:arguments:size:equals(#0):ifTrue({
    "nothing to do without arguments":display.
    system:exit(#2)
}).

"done":display.
system:exit(#0).
