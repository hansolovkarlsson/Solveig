; The arithmetic alone -- no graphics, no extension.
;
; The control in the pair. Every operand in the inner loop is a global on
; purpose, which is 4.5's exact case, so the difference between two builds
; running this is the difference the global-slot work made.
;
;     bin/solvm mandelbrot.sob
w := #320. h := #200. maxIter := #400.
total := #0.
px := #0. py := #0.
cr := 0.0. ci := 0.0. zr := 0.0. zi := 0.0. zr2 := 0.0. zi2 := 0.0. it := #0.
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
        px := px:inc }).
    py := py:inc }).
"checksum: ":display. total:print.
