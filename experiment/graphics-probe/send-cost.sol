; What one extension send costs, against one ordinary send.
;
; 200,000 of each. The ordinary send is a four-argument method on a plain
; object, so the two differ in the dlopen boundary and not much else.
;
;     bin/solvm --extension=../../../solveig-sdl/build/sdl.so send-cost.sob
n := #200000.
i := #0.
sdl:start.
screen := sdl:window("cost", #320, #200).
t0 := sdl:ticks.
i := #0.
{ i:lessThan(n) }:whileTrue({ sdl:fill(screen, #1, #1, #1, #1). i := i:inc }).
t1 := sdl:ticks.
o := object:new.
o:noop := { a, b, c, d | a }.
i := #0.
{ i:lessThan(n) }:whileTrue({ o:noop(#1, #1, #1, #1). i := i:inc }).
t2 := sdl:ticks.
"sdl:fill  x200k ms: ":display. @expr(t1 - t0):print.
"solum send x200k ms: ":display. @expr(t2 - t1):print.
