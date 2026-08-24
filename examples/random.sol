; Randomness is state, and in this language state lives in an object you make.
; Run with:  ./bin/solas examples/random.sol && ./bin/solvm examples/random.sob

; `random:new(#seed)` is a generator that repeats. Every number below is
; therefore a claim this file can make and the tests can check -- which is the
; argument for a seed you can name, written out.
r := random:new(#20260824).

; `upTo(#n)` answers #1 to #n, both included. One to n rather than zero to n-1,
; because an array is indexed from #1 and picking one of something is what this
; is mostly for.
r:upTo(#6):print.                ; #3
r:upTo(#6):print.                ; #2
r:upTo(#6):print.                ; #4

; `between` takes both ends, and either of them may be negative.
r:between(#-3, #3):print.        ; #-2
r:between(#10, #20):print.       ; #14

; `fraction` is a float, at least 0.0 and always less than 1.0. Named for what
; it answers rather than for its type: `asFloat` is what converting a receiver
; is called everywhere else here, and this converts nothing.
r:fraction:print.                ; 0.09265158547740904

; One of something, which is what `upTo` is shaped for.
colours := ["red", "green", "blue", "amber"].
colours:at(r:upTo(colours:size)):display.        ; blue

; ---------------------------------------------------------------------------
; The seed

; A generator records what it was made with, as an ordinary slot.
r:seed:print.                    ; #20260824
r:slots:print.                   ; ['seed]

; So the same seed is the same sequence, in this run or any other.
one := random:new(#7).
two := random:new(#7).
one:upTo(#1000000):equals(two:upTo(#1000000)):print.        ; true

; `random:new` with no seed asks the machine instead, which is the entropy no
; program here can reach on its own -- the clock is the only other candidate,
; and a clock's low bits are not entropy. Two of them are different generators,
; and the odds of this printing `false` are about one in nine quintillion.
random:new:seed:equals(random:new:seed):print.              ; false

; The seed the machine chose is an ordinary integer, so a run can be had again
; by writing it down and handing it back.
machine := random:new.
random:new(machine:seed):upTo(#100):equals(
    random:new(machine:seed):upTo(#100)):print.             ; true

; ---------------------------------------------------------------------------
; What it refuses

; The prototype is not a generator. Answering here would be one stream shared by
; everything that reached for it, which is what having a `random:new` avoids.
;   random:upTo(#6).             ; solvm: 'upTo' wants a random of its own -- random:new, or random:new(#seed)

; There has to be something to choose from, and the low end comes first.
;   r:upTo(#0).                  ; solvm: 'upTo' wants at least #1 to choose from, got #0
;   r:between(#5, #1).           ; solvm: 'between' wants the low end first, got #5 and #1

; A count is an integer, like every other count here.
;   r:upTo(1.5).                 ; solvm: 'upTo' wants an integer, got float
