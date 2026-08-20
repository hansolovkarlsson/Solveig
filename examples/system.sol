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
