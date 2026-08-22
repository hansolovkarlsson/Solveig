# Embedding the machine

*Holding a `SolVM` inside a larger C program and running scripts through it —
what a host may rely on, and what it may not. The header is
[solum/embed.h](../solum/include/solum/embed.h), the working example is
[embed/host.c](../embed/host.c) (`make embed`, then `./bin/solhost`), and
[tests/test_embed.c](../tests/test_embed.c) holds every promise on this page.*

This is the case
[6.32](ROADMAP.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
is about: a program that runs somebody else's scripts on its own behalf, where
the input arrives from a stranger and the host is what needs protecting. That
entry noted in passing that *"embedding is not a documented use today: the
headers make it possible and nothing claims it."*

**This page is that half, and it came first on purpose.** A permission is a
promise about what a host may rely on. There was no list of what a host may rely
on, so there was nothing for a permission to attach to — and, as it turned out,
nothing to test against: the first program to embed the machine found a
use-after-free (0.14.1) in a code path four shipped binaries could not reach.

---

## The shape

`make` builds `build/libsol.a`, holding the compiler and the VM. `solas`,
`solvm`, `solis` and `solid` are each a `main.c` linked against it; a host is a
fifth such program, except that instead of *being* the interpreter it contains
one.

Two headers, because the compiler and the machine are separate components and
embedding does not change that:

```c
#include "solas/compiler.h"     /* source text -> a chunk */
#include "solum/embed.h"        /* a chunk -> a run */
```

`solum/embed.h` is the **whole supported surface**. Anything else under
`solum/include` is the machine's own business and may change without notice.

```c
SolChunk chunk;
sol_chunk_init(&chunk);
if (!sol_compile_source(source, "<host>", &chunk)) { /* reported to stderr */ }

SolVM vm;
sol_vm_init(&vm);
sol_vm_set_step_limit(&vm, 200000);
sol_vm_set_memory_limit(&vm, 8u << 20);
sol_vm_set_global_text(&vm, "request", body);

if (sol_vm_run(&vm, &chunk) == SOL_OK) {
    char *answer = sol_vm_global_text(&vm, "answer");
    /* ... */
    free(answer);
}

sol_vm_free(&vm);
sol_chunk_free(&chunk);          /* after the VM, never before */
```

## What a host may rely on

| | |
| --- | --- |
| **One chunk, any number of machines** | Compile once and run it on as many VMs as you like. `sol_vm_run` resolves the chunk's names to whichever machine is about to run it, every time. A host does nothing to arrange this. |
| **The allowance is per run** | `sol_vm_run` resets the step budget from `step_limit` at every call, so a machine handed one request and then another gives each the whole of it rather than the remains of the last. Zero lifts a limit; both are lifted to begin with. |
| **Limits are settable only from C** | There is no message that sets, clears or reads either one. That is the whole of what makes them limits rather than suggestions, and it is what 6.32 requires of any mechanism: if the mechanism is argv parsing, the case that asked for it cannot use it. |
| **Five endings, told apart** | `SOL_OK`, `SOL_EXIT` (with `vm.exit_code`), `SOL_STOPPED`, `SOL_RUNTIME_ERROR`, `SOL_COMPILE_ERROR`. A stopped program did not fail; a host treating it as a bug would go looking for one that is not there. |
| **A script that exits ends itself** | `system:exit` unwinds rather than leaving from under the machine, so `sol_vm_run` answers `SOL_EXIT` and the host stays up. This is the behaviour an embedder would most expect to be wrong. |
| **The failure is readable** | `sol_vm_error_message` and `sol_vm_error_trace` after a run that answered `SOL_RUNTIME_ERROR` or `SOL_STOPPED`. Cleared by the next run, so what they hold is this run's. |
| **The failure is the host's** | `sol_vm_set_error_reporting(vm, false)` stops `sol_vm_run` writing it to stderr, and stops only that: the result still says what happened and the text is still there to read. On unless asked, which is what the four front ends here rely on. |
| **Text in, text out** | `sol_vm_set_global_text` before, `sol_vm_global_text` after. The text form is on the heap and the caller frees it, so it outlives the machine. |
| **The search path is the host's to set** | `sol_search_path_add_defaults` gives a script the same `@include` and the same shipped library it gets from `solas`. A host that skips it offers a smaller language than the one documented. |
| **One VM and one chunk per thread** | Machines on separate threads share nothing, including their collectors, and serials are handed out atomically. Source text may be shared freely — threads read one `.sol` and each compiles its own chunk. Tested, including under a collection on every allocation. |

## Three ordering rules

None of these is checked, and each is the kind of thing found by crashing rather
than by reading — which is the argument for their being written down at all.

1. **`sol_chunk_free` after `sol_vm_free`, never before.** Blocks made while the
   chunk ran point into it. That is
   [3.6](ROADMAP.md#36-a-caller-owned-chunk-must-outlive-blocks-defined-in-it),
   and a host is its second case after the test suite.
2. **Read what you want out before `sol_vm_free`.** Everything a run made dies
   with the machine. `sol_vm_global_text` copies for exactly this reason;
   `sol_vm_global` does not, and what it answers is valid only until the next
   run or the free.
3. **Set limits and globals before `sol_vm_run`, not during.** There is nothing
   to call them from during a run in any case, but a limit lowered mid-run would
   not be noticed until the counter next crossed it.

> **Not** a rule: calling `sol_vm_intern_chunk` yourself. `sol_vm_run` does it.
> An earlier version of this page said it was required, which was wrong — the
> 0.14.1 defect was *inside* that function rather than in a call somebody could
> miss. Writing the contract down is what caught the mistake.

## What is deliberately not promised

**A name the two sides agree on.** A host says `"request"` and `"answer"`; the
script has to say the same, and nothing checks that it does. This is the weakest
joint in the interface. It is a convention, not a contract, and the honest thing
is to say so rather than dress it up. That is
[3.8](ROADMAP.md#38-a-host-and-a-script-agree-a-name-and-nothing-checks-that-they-do).

**Reuse of one VM across runs.** It works and it leaks meaning: globals are one
flat namespace and nothing unbinds them, so a second run sees the first one's
names. That is the same flatness `@include` relies on, seen from the side where
it hurts. **A fresh VM per request is the only safe choice today**, and it costs
rebuilding the interned names and the built-in classes each time —
[3.10](ROADMAP.md#310-a-vm-cannot-be-reused-across-runs).

**A chunk shared between threads.** Running a chunk *mutates* it — the interned
names are cached on it, keyed to one machine at a time — so two threads running
one chunk free and rebuild that table under each other. Measured: eight threads,
one chunk, 2,400 runs is a segmentation fault; the same serialised behind a
mutex is 0 failures. Compile per thread, which costs milliseconds once. That is
[3.11](ROADMAP.md#311-a-chunk-cannot-be-shared-between-threads).

**Two threads in one VM.** A machine has one stack, one heap and one frame
array, and nothing guards any of them. Not supported, and no plan to change it.

**That a limit bounds cost.** It bounds a program that *loops*. A primitive does
all of its work between one step and the next, so `readFile` of 256MB plus a
scan of all of it is eight instructions — see
[3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work). Measured on
[serve.sol](../programs/serve.sol), one request costs 393 to 798 instructions
and about 15KB live, which are the numbers to set a limit *from* rather than
guess.

**Anything about what a script may reach.** It may run another program, delete a
file, read `~/.ssh/id_rsa`, and hand your environment to whoever asked. That is
[6.32](ROADMAP.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
and it is still a decision. Nothing on this page is a sandbox.

## What holds this page honest

[tests/test_embed.c](../tests/test_embed.c) has a case for every promise above.
It deliberately does what a host does rather than what a test finds convenient:
VMs are built inside *called* functions, chunks outlive the machines that ran
them, and one chunk serves eight.

That last detail is the point of the whole file. The test that should have
caught 0.14.1, `test_a_second_vm_reresolves`, holds both machines as locals of
one function — which puts them at different addresses and makes a pointer
comparison work. It was never wrong. It was never in the *shape* that fails, and
nothing about reading it revealed that, because the assertion it makes is true.

A contract is what tells you which shapes matter.
