; The same picture again, presenting on the clock instead of per row.
;
; The only difference from mandelbrot-sdl.sol is that present is guarded by
; sdl:ticks and runs at most every 16ms. That one line is worth more than the
; interpreter work between 0.38.0 and 0.39.0 -- 1.90s to 1.29s against 1.59s
; to 1.07s -- which is the finding this directory exists for.
;
;     bin/solvm --extension=../../../solveig-sdl/build/sdl.so mandelbrot-sdl-throttled.sob
w := #320. h := #200. maxIter := #400.
total := #0.
px := #0. py := #0.
cr := 0.0. ci := 0.0. zr := 0.0. zi := 0.0. zr2 := 0.0. zi2 := 0.0. it := #0.
shade := #0. lastPresent := #0.
sdl:start.
screen := sdl:window("mandelbrot", w, h).
sdl:clear(screen, #0, #0, #0).
py := #0.
{ py:lessThan(h) }:whileTrue({
    px := #0.
    { px:lessThan(w) }:whileTrue({
        cr := @expr(px:asFloat / 320.0 * 3.0 - 2.0).
        ci := @expr(py:asFloat / 200.0 * 2.0 - 1.0).
        zr := 0.0. zi := 0.0. it := #0.
        zr2 := 0.0. zi2 := 0.0.
        { @expr(it < maxIter):and({ @expr(zr2 + zi2 < 4.0) }) }:whileTrue({
            zi := @expr(2.0 * zr * zi + ci).
            zr := @expr(zr2 - zi2 + cr).
            zr2 := @expr(zr * zr).
            zi2 := @expr(zi * zi).
            it := it:inc }).
        total := @expr(total + it).
        shade := @expr(it * #6:mod(#256)).
        sdl:colour(screen, shade, @expr(shade / #2), @expr(#255 - shade)).
        sdl:fill(screen, px, py, #1, #1).
        px := px:inc }).
    @expr(sdl:ticks - lastPresent > #16):ifTrue({ sdl:present(screen). lastPresent := sdl:ticks }).
    py := py:inc }).
"checksum: ":display. total:print.
