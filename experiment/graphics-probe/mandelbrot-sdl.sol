; The same arithmetic, drawn, presenting once per row.
;
; Identical to mandelbrot.sol above the drawing: same bounds, same iteration
; cap, same checksum. What it adds is one sdl:colour and one sdl:fill per
; pixel, and one sdl:present per row -- and that last one is the whole cost.
;
;     bin/solvm --extension=../../../solveig-sdl/build/sdl.so mandelbrot-sdl.sob
w := #320. h := #200. maxIter := #400.
total := #0.
px := #0. py := #0.
cr := 0.0. ci := 0.0. zr := 0.0. zi := 0.0. zr2 := 0.0. zi2 := 0.0. it := #0.
shade := #0.
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
    sdl:present(screen).
    py := py:inc }).
"checksum: ":display. total:print.
