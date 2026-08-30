; What sdl:present costs, on its own, drawing nothing.
;
; 200 presents into an untouched window. The answer is vsync and it is the
; reason an immediate-mode PSET cannot be built on this surface as it stands.
;
;     bin/solvm --extension=../../../solveig-sdl/build/sdl.so present-cost.sob
n := #200.
i := #0.
sdl:start.
screen := sdl:window("present", #320, #200).
t0 := sdl:ticks.
i := #0.
{ i:lessThan(n) }:whileTrue({ sdl:present(screen). i := i:inc }).
t1 := sdl:ticks.
"present x200 ms: ":display. @expr(t1 - t0):print.
"per present ms:  ":display. @expr((t1 - t0):asFloat / 200.0):print.
