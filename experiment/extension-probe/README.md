# The extension probe

*Thrown away on purpose, kept because the findings were paid for.*

[ideas.md](../../docs/ideas.md#extensions-a-capability-from-a-binary-rather-than-from-the-vm)
closes its extensions entry by saying that the first move is not any of the
design above it: *write one throwaway extension — fifty lines, something with
nothing to release — build it, load it, and find out what the path actually
wants.* This is that, run on 2026-08-28 when GTK fired the trigger. What it
found is written up
[there](../../docs/ideas.md#gtk-and-the-afternoon-that-was-supposed-to-be-a-page);
this directory is only the evidence, so the claims can be re-run rather than
believed.

**It is not a proposal.** Nothing here is the interface an extension should
have. There is no ABI beyond an integer, no `extend.h`, no foreign value type,
and the callback registry is four lines behind an `#ifdef` because its absence
was the point.

**Nothing builds it.** It is off `make all` deliberately, which is the same
property the real thing has to have — see the entry on why the front-page
sentence survives only if a bundle lives outside the default build.

| file | what it is |
| --- | --- |
| `probe_host.c` | the loader: `dlopen`, `dlsym("sol_extension_init")`, call it before the run. Takes any number of bundles and a script |
| `probe_ext_hash.c` | the throwaway the entry asks for. One message, nothing to release |
| `probe_ext_gtk.c` | the half a checksum cannot test: a GLib main loop calling back into the VM, and a block the collector cannot see. **Since rewritten onto `sol_extension_retain`**, so the `#ifdef PROBE_ROOTED` it was built around is gone |
| `probe.sol` | sends `hash:fnv1a` |
| `tick.sol` | drives `gtk:every` under `gc_stress`. **This is the one that matters** |
| `both.sol` | two bundles in one machine, which is the combinatorial claim |
| `ext_sdl.c`, `ext_fastmath.c`, `ext_net.c` | **the claim at full size** — a graphics toolkit, a hand-written maths library and a socket, three files that do not know about each other |
| `game.sol` | uses all three |

## Running it

```sh
make                                   # for build/libsol.a
R=$PWD

# -force_load is finding two. Without it the host exports only what it
# happens to reference, and the bundle fails on sol_vm_set_global.
cc -std=c11 -D_DARWIN_C_SOURCE -I$R/solum/include -I$R/solas/include -I$R/build \
   experiment/extension-probe/probe_host.c -Wl,-force_load,$R/build/libsol.a \
   -o /tmp/probe_host -lm

cc -std=c11 -D_DARWIN_C_SOURCE -I$R/solum/include -I$R/solas/include -I$R/build \
   -fPIC -shared experiment/extension-probe/probe_ext_hash.c \
   -o /tmp/hash.so -Wl,-undefined,dynamic_lookup

cc -std=c11 -D_DARWIN_C_SOURCE -I$R/solum/include -I$R/solas/include -I$R/build \
   $(pkg-config --cflags gtk4) -fPIC -shared \
   experiment/extension-probe/probe_ext_gtk.c \
   -o /tmp/gtk.so $(pkg-config --libs gtk4) -Wl,-undefined,dynamic_lookup

/tmp/probe_host /tmp/hash.so /tmp/gtk.so experiment/extension-probe/both.sol
```

On Linux the two linker flags differ: `-Wl,--whole-archive` for the host, plus
`-rdynamic`, and a bundle needs neither `-undefined dynamic_lookup` nor any
substitute. **That paragraph is reasoned and not measured** — the probe ran on
macOS/arm64 only, and saying so is the difference between this file and the one
it corrects.

## The finding, and what became of it

As first written, `probe_ext_gtk.c` kept the block in a C struct and `tick.sol`
under `gc_stress` printed:

```
#1
probe: callback failed: 'block' takes 1 argument, got 0
```

The block registered with `g_timeout_add` was reachable from nothing the tracer
walks, so the collection between the first tick and the second swept it, and the
second tick called whatever landed in that cell — the inner
`{ x | x:asString }` from the same script. An arity complaint about a block the
program never registered: **not a crash, and nothing in it pointing at the
collector.**

The workaround was four lines putting the block in an array hung on the
extension's own global, behind `-DPROBE_ROOTED`. Those four lines were the
argument for `sol_extension_retain`, and this file now uses it instead — one
call, and a token that says so when it goes stale rather than resolving to
something plausible. The same program under the same stress prints five ticks
and `"done"`, with nothing conditional left in it.

## Three at once, which was the question the design is for

`hash.so` and `gtk.so` prove two bundles load. The shape somebody actually wants
is a *game*: SDL2 for the window, a C library of their own for the arithmetic
that has to be fast, and a socket for the other player. So that is built here
too, headless, in ninety lines each:

```sh
SDL_VIDEODRIVER=dummy /tmp/probe_host \
    /tmp/sdl.so /tmp/fastmath.so /tmp/net.so \
    experiment/extension-probe/game.sol
```

```
true
listening on
#49493
  got
"1:11"
  got
"2:11"
  got
"3:11"
"clean exit"
```

SDL owns the frame loop and calls a Solum block; the block asks `fastmath` for a
dot product and hands the answer to `net`; the datagram comes back on the next
frame. **Naming the three bundles in any order runs the same**, and starting
without one of them fails at the line that first uses it — `undefined name
'net'` — rather than at load.

**What the three files do not contain is the point.** No file mentions another,
none of them can tell whether the others were loaded, and they meet only at the
root object, the way `system` and `array` do.

**`ext_net.c` was the argument for `SolForeign`, and has since been rewritten
onto it.** It used to hand a socket back as a plain integer, because no value
type could carry a file descriptor — so nothing closed it if the program was
stopped, it was not counted against `--memory`, and a program could invent one
and pass it to `net:close`. All three of those became the case for the foreign
cell, made by a file that needed it rather than by a paragraph.

It now answers a `<socket>`, asks for the handle by kind, and **has no `close`
at all**: the collector closes one the program has let go of, and VM teardown
closes one it was still holding. Opening real sockets through it is also what
found that bytes are the wrong currency for a scarce resource — see the
changelog entry for the pressure count that came out of it.
