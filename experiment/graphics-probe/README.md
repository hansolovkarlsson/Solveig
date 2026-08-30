# The graphics probe

*Thrown away on purpose, kept because the findings were paid for.*

Five programs from 2026-08-30, when the question was whether to implement
SolaBasic's graphics statements over the SDL2 extension. The answer was no and
[ideas.md](../../docs/ideas.md#graphics-in-solabasic-through-the-sdl2-extension)
says why — no program wanted a screen, so the trigger never fired. **These are
the evidence for the numbers that entry and the
[journal](../../docs/journal.md) quote**, so the claims can be re-run rather
than believed.

**Two of the three findings are about SDL and one is about Solum**, and the
Solum one is the reason this is not filed under solveig-sdl: the pair at the top
is a clean measurement of
[4.5](../../docs/COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done)
on a program written after it landed, by somebody trying to draw a picture
rather than to win a benchmark.

**Nothing builds these and nothing tests them.** Same property as
[extension-probe/](../extension-probe/) and the same reason: the SDL bundle
lives outside this repository, so anything here that needed it on the path would
put SDL into a build that promises no dependencies.

| file | what it is |
| --- | --- |
| `mandelbrot.sol` | the control — the arithmetic alone, no extension loaded |
| `mandelbrot-sdl.sol` | the same picture, presenting once per row |
| `mandelbrot-sdl-throttled.sol` | the same picture, presenting at most every 16ms. **The one that matters** |
| `send-cost.sol` | 200,000 extension sends against 200,000 ordinary ones |
| `present-cost.sol` | 200 presents, drawing nothing |

## What they found

| | |
| --- | --- |
| an extension send | **205ns**, against an ordinary send's 55ns |
| `sdl:present` | **8.3ms**, because it is vsync-locked |
| 0.38.0 to 0.39.0, arithmetic alone | 1.59s to **1.07s**, a 1.49x |
| presenting per row, then on a 16ms clock | 1.90s to **1.29s** |

**The second row is the one nothing predicted.** QBasic graphics is
immediate-mode — `PSET` draws and you see it — and SDL is double-buffered, so a
faithful `PSET` would present after every statement at 8.3ms each: 120 pixels
per second, and a program drawing a circle would take a minute. Reading the SDL
headers does not produce that sentence. Running two hundred presents in a loop
produces it in ten seconds.

**And the last row is worth as much as the interpreter work above it.** The
throttle is four lines and bought a larger factor on this program than a week of
optimisation did. It is the reminder that a policy decision can outweigh the
machine underneath it.

## Running them again

Needs [solveig-sdl](https://github.com/hansolovkarlsson/solveig-sdl) built as a
sibling checkout, and `bin/` built here:

```sh
make -C ../solveig-sdl SOLVEIG=$PWD
bin/solas experiment/graphics-probe/present-cost.sol -o /tmp/p.sob
bin/solvm --extension=../solveig-sdl/build/sdl.so /tmp/p.sob
```

**Time the Mandelbrots against an `-O2` build or the numbers mean nothing** —
the default `CFLAGS` is `-g` with no optimiser, which is
[performance.md](../../docs/performance.md#the-build-flag-is-worth-more-than-any-of-this)'s
standing warning:

```sh
make clean && make CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -O2"
```

`make clean` is not optional there. `CFLAGS` is not a prerequisite, so changing
it alone rebuilds nothing and relinks the `-g` binary under the new name.

## What it does not answer

**Nothing here draws a circle, fills an area, or puts a character on a graphics
screen**, because the eleven messages solveig-sdl publishes cannot do the last
two: `PAINT` needs a pixel read back and there is no message that reads one, and
text needs a font. Those are named in the ideas entry as what would have to grow
first. **And none of this is checkable by
[oracle.sh](../../programs/sola/oracle.sh)** — it compares printed bytes, and
graphics print none, which is the argument that would decide the question if it
were ever asked again.
