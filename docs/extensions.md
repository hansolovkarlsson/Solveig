# Extensions

*Giving the machine a capability it does not have and could not reasonably
grow — a window, a socket, a codec — from a C file compiled on its own and named
when a program is started. The header is
[solum/extend.h](../solum/include/solum/extend.h), the working example is
[tests/ext_probe.c](../tests/ext_probe.c), and
[tests/test_extension.c](../tests/test_extension.c) holds every promise on this
page.*

This page stands to extensions as [embedding.md](embedding.md) does to hosts,
and the two are different jobs. A **host** contains a machine and runs programs
through it. An **extension** is loaded into a machine somebody else started, and
never sees argv, the chunk, or the run.

The case for the mechanism, and what was measured before any of it was built, is
[in ideas.md](ideas.md#extensions-a-capability-from-a-binary-rather-than-from-the-vm).

---

## The whole of it

```c
#include "solum/extend.h"

static SolValue prim_shout(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_STRING) {
        sol_vm_runtime_error(vm, "shout expects one string");
        return SOL_NIL_VAL;
    }
    return sol_vm_send(vm, args[0], "asUppercase", NULL, 0);
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != SOL_EXTENSION_ABI) return -1;

    SolObject *probe = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, probe, "shout", prim_shout);
    sol_vm_set_global(vm, "probe", SOL_OBJ_VAL(probe));
    return 0;
}
```

```sh
cc -std=c11 -fPIC -shared -Isolum/include probe.c -o probe.so \
   -Wl,-undefined,dynamic_lookup        # macOS only; ELF needs nothing

bin/solvm --extension=probe.so program.sob
```

and in the program, nothing about loading at all:

```
probe:shout("quiet"):print.        ; -- "QUIET"
```

`probe` is a global, sitting beside `system` and `array`. It is there because
the machine was started with the bundle, and a program run without it fails at
the first line that names it — `undefined name 'probe'` — rather than at load.

**`solvm`, `solis` and `solid` all take the flag**, repeatably, loading in the
order written. Every front end that *runs* a program takes it, including the
debugger — a program that needs an extension is exactly the kind worth stepping
through, and stepping stops inside Solum and never inside an extension, which is
C and has no lines to stop on.

**`solas` does not, and never will.** A compiler that loaded native code in
order to compile a file would put that requirement into the `.sob`, where every
machine that ever ran it would inherit it — including one that only wanted to
disassemble it.

## Who decides

**Whoever starts the program**, and there is deliberately no message that loads
an extension.

Native code runs past `--steps`, past `--memory`, past everything: those bound
what the *machine* does, and an extension is not the machine. A capability a
script can invoke is not a capability a host can withhold, and this is the
largest possible thing to be unable to withhold — which is
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
seen from its worst angle. Limits are settable only from C for exactly this
reason; loading is the same shape.

At a terminal this costs you nothing, because you can type the flag. It matters
when the person starting the program is not the person who wrote the script.

There is also no `@link` directive, and that one fails worse: it would put
`dlopen` inside **Solas**, so the compiler would load native code in order to
compile a file, and the `.sob` would carry the requirement into every machine
that ever ran it — including one that only wanted to disassemble it.

## Two doors

| | |
| --- | --- |
| `sol_extension_load(vm, path, &error)` | `dlopen`, then `dlsym`, then register. What `--extension=` calls. |
| `sol_extension_register(vm, init, name, &error)` | For an extension linked into the binary. No dynamic linker involved. |

Both end in the same call to `sol_extension_init`, and `extend.h` mentions
`dlopen` nowhere. The test suite uses the second, because building a shared
object part-way through a test run needs a compiler at test time — fragile
under three CI configurations and impossible under a sanitiser.

## What an extension may rely on

```text
sol_object_new(vm, proto)                 an object; proto is usually vm->object_class
sol_object_define(vm, obj, name, value)   bind a name to a value
sol_object_define_primitive(vm, obj, name, fn)
sol_object_define_primitive_for(vm, obj, name, fn, type)
sol_vm_set_global(vm, name, value)        hang the extension's global
sol_vm_global(vm, name, &out)             read one back

sol_string_new(vm, chars, length)         copies
sol_symbol_intern(vm, chars, length)      a symbol, made only if new
sol_array_new(vm, capacity)
sol_array_add(vm, array, value)

sol_extension_retain(vm, value)            keep it between calls
sol_extension_retained(vm, token, &out)    get it back, or learn you cannot
sol_extension_release(vm, token)           stop keeping it

sol_vm_call_block(vm, block, args, argc)   then rule 4
sol_vm_send(vm, receiver, name, args, argc) then rule 4
sol_vm_runtime_error(vm, format, ...)      rule 2
sol_gc_push_temp(vm, cell) / sol_gc_pop_temp(vm)   rule 3

vm->object_class and the other built-in classes
vm->had_error
```

**A primitive an extension installs is indistinguishable from a built-in.** Same
slot, same dispatch, same speed. `respondsTo` finds it and `slots` lists it.
That is a promise rather than an accident: it is what would let a capability
leave the core one day without becoming second class.

## Handing a resource back

A socket, a window, a connection, a compiled pattern — anything the program may
hold and the machine cannot make sense of:

```c
static void close_socket(void *handle) { close((int)(intptr_t)handle); }

/* net:udp(#port) */
return SOL_FOREIGN_VAL(sol_foreign_new(vm, (void *)(intptr_t)fd,
                                       close_socket, "socket", 0));
```

and the primitive that receives one back asks for it **by kind**, never by
casting:

```c
void *handle = sol_foreign_handle(args[0], "socket");
if (handle == NULL) {
    sol_vm_runtime_error(vm, "send expects an open socket");
    return SOL_NIL_VAL;
}
```

The program sees an ordinary value. It renders as `<socket>`, compares by
identity, answers `isKindOf(foreign)`, and cannot be made with `new` — a
resource comes from an extension or it does not exist.

**`release` runs exactly once, and from two directions.** The collector calls it
when the program lets go of the value; `sol_vm_free` calls it for everything
still alive at shutdown, whatever its reachability. So a socket is closed when
the program drops it *and* when a limit takes the program away mid-flight —
which is the case an explicit `close` could never cover, since a limit-stop is
uncatchable and does not run `ensure`
([6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)).
That is the argument for there being no `close` message at all.

`kind` must outlive the VM — a string literal does — and is compared with
`strcmp`, so one extension's `"socket"` cannot be handed to another's primitive
that wanted its own.

### The currency the collector counts in

**`footprint` is what the resource costs where the machine cannot see it** — a
texture, a decoded image, a connection's buffers. It is added to the live-byte
figure `--memory` is measured against, so a limit measures the texture rather
than the pointer to it. Zero when there is nothing honest to say, which is
usual.

> **And bytes are the wrong currency for a scarce resource, which was found by
> opening real sockets.** A foreign cell is forty bytes however scarce the thing
> it holds, so a program opening descriptors in a loop exhausted the process
> while the heap was still nearly empty — measured at a 256-descriptor ceiling,
> where it died with no collection having happened at all.
>
> So foreign cells carry a pressure count of their own:
> `SOL_GC_FOREIGN_PRESSURE` of them forces a collection whatever the byte figure
> says. **An extension does not have to do anything about this**, and in
> particular should not inflate `footprint` to buy scheduling — a wrong number
> there makes `--memory` lie. The same program now opens 5,000 sockets under a
> ceiling of 256.

## The four rules

Each is something a newcomer gets wrong, and each was found by getting it wrong.

**1. Arity is not checked for you.** `sol_object_define_primitive_for` checks the
*receiver* and nothing else. A block checks its own arity because it has one to
check; a C function does not.

**2. Failure is out of band.** A primitive answers a `SolValue` and has no way to
say "this went wrong" in it. Call `sol_vm_runtime_error` and return
`SOL_NIL_VAL`.

**3. Nothing may hold a heap pointer across an allocation unless it is reachable
from a root.** The collector marks the value stack, the frames, the
temporary-root stack and the class objects. A cell held only in a C local, or in
a struct C owns, is none of those.

> **The case that bites is a callback.** A block registered as a graphics
> toolkit's `user_data` is reachable from nothing the tracer walks, so a
> collection between one call and the next sweeps it — and the next call runs
> *whatever now occupies that cell*. Measured: the failure was `'block' takes 1
> argument, got 0`, an arity complaint about a block the program never
> registered. Not a crash, and nothing pointing at the collector.
>
> `sol_gc_push_temp` covers a short window inside one primitive and is eight
> deep; overflowing it calls `exit(1)` with no diagnostic. Anything held
> **between** calls goes in the registry below.
>
> Note that a **foreign** cell is not this problem: it is a value the collector
> knows about, and holding one in a slot roots it like anything else. The
> problem is a Solum *block* held by C.

**4. Check `vm->had_error` after every call back into the language.** After
`sol_vm_call_block` or `sol_vm_send`, before doing anything else. A limit-stop
sets it and is deliberately not catchable, so a loop that does not look will
keep calling into a machine that has already been stopped — the one way an
extension can defeat `--steps`.

## Keeping a value alive between calls

Rule 3 covers a window inside one primitive. A toolkit holding your callback
holds it *between* calls, where nothing the tracer walks can see it — so retain
it, keep the **token** in `user_data`, and look it up when the callback fires:

```c
typedef struct { SolVM *vm; SolRetained on_click; } Button;

button->on_click = sol_extension_retain(vm, args[0]);

static void clicked(GtkWidget *w, gpointer data)
{
    Button *button = data;
    SolValue block;
    if (!sol_extension_retained(button->vm, button->on_click, &block)) {
        return;                            /* released, or never valid */
    }
    sol_vm_call_block(button->vm, block, NULL, 0);
    if (button->vm->had_error) { ... }     /* rule 4 */
}

sol_extension_release(button->vm, button->on_click);   /* widget gone */
```

**Keeping the token rather than the `SolValue` is the point.** The collector
does not move cells, so a retained value would stay valid — but a token that has
been released answers *false*, where a stale value answers a plausible wrong
block. The registry can tell you that you are wrong; a cached value cannot, and
being unable to is the entire defect this exists to end.

A token carries the slot's generation as well as its index, so a token outliving
its slot is detected rather than resolving to whatever was retained into that
slot next — which would be the same silent misdispatch moved one layer up.

**Not reference counted.** Two retains of one value give two tokens, each
released on its own. Retaining twice and releasing once leaves it rooted, which
is the safe direction to be wrong in. Everything still retained is released when
the VM goes down, so an extension that never releases leaks nothing beyond the
machine's life.

## The handshake

`SOL_EXTENSION_ABI` is compared for equality. A bundle built against a different
number is refused by name, with what to do about it:

```text
solvm: cannot load extension probe.so: refused ABI 1 -- built against a
different SolVM, rebuild it against this one
```

The policy is [`.sob`'s](ROADMAP.md#34-no-compatibility-across-sob-versions)
exactly — refuse, do not guess, rebuild — and for the same reason. `SolValue` is
passed by value and `SolObject`'s layout is exposed, so nearly any struct change
in the VM moves the number. **You never rebuild `solvm` to add an extension; you
do rebuild your extensions when `solvm` changes.**

It is deliberately not `SOLUM_VERSION`: a release that changes no struct should
not invalidate every bundle, and one that changes a struct without changing the
version must still be caught.

A refusal is not a half-load. The extension has bound nothing and the machine is
exactly as it was, so `solvm` reports it and exits 65 — the status a `.sob` that
cannot be read gets, because it is the same kind of thing.

## Two real ones

[solveig-gtk](https://github.com/hansolovkarlsson/solveig-gtk) and
[solveig-sdl](https://github.com/hansolovkarlsson/solveig-sdl) are written
against this page rather than alongside it, each in its own repository and
built by nothing here.

It is worth knowing what it settled, because two things about a real toolkit
were genuinely uncertain and neither was answerable from a checksum:

| | |
| --- | --- |
| **A foreign main loop calling back in** | Free. `sol_vm_call_block` re-enters from a GTK signal handler exactly as it does from `array:do`, and an error inside one formats a trace naming the `gtk:run` line beneath it. |
| **Widget lifetimes against a collector** | `g_object_ref_sink` turns GTK's floating reference into one the extension owns and the foreign cell releases; a parent taking a child adds its own. The two lifetimes do not fight. |
| **Whether a limit still bounds a program with a window** | It does, and only because rule 4 is kept: `--steps=400` stops the counter mid-loop and exits 124. |

And it is the reason this repository still builds with no dependencies beyond a
C11 compiler and `make`.

**The second one is the check on the first.** SDL2 needed no change to the
mechanism — same header, same ABI, same loader, same foreign cell — and it is
deliberately *not* shaped like the GTK one, because SDL hands a program a frame
and gets out of the way where GTK owns the loop. So `sdl` has no `run` and no
callback at all, and the program writes an ordinary `whileTrue`.

That difference is the evidence for two decisions that were taken on argument:

| decision | what the second back end showed |
| --- | --- |
| The retain registry is a **service**, not the shape of an extension | solveig-sdl uses none of it. Had callbacks been the shape, it would be fighting the interface. |
| No back end names itself the general case | `gtk:` and `sdl:` share no vocabulary, and neither had to pretend to be the other. |

It also found the one thing missing from the list above — `sol_symbol_intern`,
which an extension answering *what happened* wants immediately — and that is
what a second customer is for.

## What is deliberately not promised

**A sandbox.** Nothing on this page is one. See "who decides" above.

**That an extension can be unloaded.** The `dlopen` handle is never closed.
Primitives, and any string constant a message points at, live as long as the
machine, and unmapping the code underneath them would leave slots pointing into
a dead page. Nothing unbinds a global either — this is
[3.10](ROADMAP.md#310-a-vm-cannot-be-reused-across-runs) seen from another side.

**Deterministic close from inside a program.** There is no `close` message; see
"handing a resource back" above for why. `sol_foreign_release` is there for an
extension that must close in a known order — a child before its parent — and is
not reachable from Solum.

**Anything about two extensions agreeing.** They meet at the root object and
nowhere else. Two that bind the same global will overwrite each other in the
order given on the command line, and nothing warns.

**Portability of a bundle.** A bundle is per-platform and per-build. There is no
format here, only the platform's.

## What holds this page honest

[tests/test_extension.c](../tests/test_extension.c) has a case for the contract
— registration, the handshake, refusal, ordering, and that a limit still ends a
program using an extension.

**But the linker's half is checked somewhere else, and the reason is worth
knowing.** Whether a loaded bundle can resolve `sol_*` back into the program
that loaded it depends on what that program exports, and a symbol reaches an
executable's export table only if the executable already referenced it. A test
binary that calls `sol_vm_set_global` on its own account finds it exported
however the link was done — so an assertion there passes while `bin/solvm` stays
broken. The first draft of that file made exactly this mistake and had to be
corrected.

So the decisive case is
[`test_an_extension_reaches_the_program`](../tests/test_cli.c), which builds a
real bundle and hands it to the real binary. Against a `solvm` linked the old
way it fails with

```text
symbol not found in flat namespace '_sol_vm_set_global'
```

which is the defect the Makefile's `WHOLE_LIB` exists to prevent: before it, the
four binaries exported four different accidental sets of `sol_*` — 100, 118, 133
and 118 — and every function in `embed.c` was in none of them, because no front
end here calls one.
