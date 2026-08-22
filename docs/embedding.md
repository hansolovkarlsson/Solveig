# Embedding the machine

*Holding a `SolVM` inside a larger C program and running scripts through it. The
working example is [embed/host.c](../embed/host.c), built with `make embed` and
run as `./bin/solhost`.*

This is the case
[6.32](ROADMAP.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
is about — a program that runs somebody else's scripts on its own behalf, where
the script's input arrives from a stranger and the host is what needs
protecting. The entry noted in passing that *"embedding is not a documented use
today: the headers make it possible and nothing claims it."* This page is the
smaller half of that, written after a host was built to find out what was
actually there.

**It found a defect on the first run**, which is recorded below and is fixed.

## The shape

`make` builds `build/libsol.a`, holding the compiler and the VM. `solas`,
`solvm`, `solis` and `solid` are each a `main.c` linked against it, and a host
is a fifth such program — except that instead of *being* the interpreter it
contains one.

```c
#include "solas/compiler.h"
#include "solum/vm.h"

SolSearchPath search;
sol_search_path_init(&search);
sol_search_path_add_defaults(&search, argv[0]);   /* so @include finds lib/ */

SolChunk chunk;
sol_chunk_init(&chunk);
if (!sol_compile_file(source, path, &search, &chunk)) { /* reported to stderr */ }
sol_search_path_free(&search);

SolVM vm;
sol_vm_init(&vm);
sol_vm_set_step_limit(&vm, 200000);          /* before it runs, and from C */
sol_vm_set_memory_limit(&vm, 8u << 20);

sol_vm_intern_chunk(&vm, &chunk);            /* required; see below */
SolResult result = sol_vm_run(&vm, &chunk);

sol_vm_free(&vm);
sol_chunk_free(&chunk);                      /* after the VM, not before */
```

`SolResult` is the whole of what a host learns: `SOL_OK`, `SOL_EXIT` with
`vm.exit_code`, `SOL_STOPPED` when a limit ended it, `SOL_RUNTIME_ERROR`,
`SOL_COMPILE_ERROR`. Those three failure kinds are distinct on purpose — a
stopped program did not fail, and a host treating it as a bug would go looking
for one that is not there.

## Compile once, run many

The reason to hold the machine rather than shell out to `solvm`: the compiler
runs once however many times the script does.

`sol_vm_run` resets the step budget from `step_limit` at every call, so the
allowance is **per run and not per VM**. That was written for a server handing
one machine a request and then another, and until `host.c` existed no second run
had ever happened. It works:

| request | steps | memory | result |
| --- | --- | --- | --- |
| the index | 200000 | 8192K | exit |
| one note | 200000 | 8192K | exit |
| a search | 200000 | 8192K | exit |
| a script tag | 200000 | 8192K | exit |
| a traversal | 200000 | 8192K | exit |
| too little rope | **300** | 8192K | **stopped** |
| too little room | 200000 | **12K** | **stopped** |

The starved runs stop and the ones around them do not.

**The numbers to set a limit from**, measured on
[programs/serve.sol](../programs/serve.sol): a request costs **393 to 798
instructions** and about **15KB live**. Both are properties of that script
rather than of the machine, and both are worth measuring rather than guessing —
and see [3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work) for what a step
limit does not bound.

## `sol_vm_intern_chunk` is required, and was where the defect was

A chunk's names are resolved to the *interned copies belonging to the VM about
to run it*, so a send compares pointers instead of walking characters. Run one
chunk on a second VM and they must be resolved again.

**The defect**: `SolChunk.interned_for` recorded which machine had done that, as
a `const SolVM *`, and the work was skipped when it matched. A host serves each
request in a function that builds a VM as a local — so every request's machine
lands at the same stack address, the chunk believed it was already resolved, and
every run after the first read the **freed** previous VM's name table.

```
==== a search: /search?q=limit
solvm: undefined name 'lessThan'
==== a traversal: /note/..
solvm: undefined name 'truncated'
==== the index: /
solvm: cannot bind 'shiftRight' on boolean
```

Six of seven requests failed that way, each naming a different built-in and none
of it meaning anything. `interned_for` is a **serial** now — `vm->id`, unique
for the life of the process — so an address handed back to a later VM cannot be
mistaken for the same machine.

The test that should have caught it, `test_a_second_vm_reresolves`, holds both
VMs as locals of one function, which puts them at different addresses and made
the pointer comparison work. `test_a_reused_address_is_not_the_same_vm` builds
each in a called function, which is what a host does.

## What is missing

Three things, none of them large, none of them decided.

**There is no route for the answer.** A script's output goes to stdout, because
`display` writes there and nothing else exists. A webserver needs the page as a
*value*. The mechanism is there —

```c
SolSlot *slot = sol_object_lookup(vm->root, "answer");
SolText text;
sol_text_init(&text);
sol_value_render(vm, slot->value, &text);      /* copy it out before sol_vm_free */
```

— but a host has to assemble it, know that the value dies with the VM, and agree
a global name with the script by convention with nothing to check that they do.

**A fresh VM per request is the only safe choice.** Globals are one flat
namespace and nothing unbinds them, so a second request on a reused VM sees the
first one's names — the same flatness `@include` relies on, seen from the side
where it hurts. Discarding the VM discards the interned names and the built-in
classes with it, so every request pays to rebuild them.

**Ordering rules you find out by crashing.** `sol_chunk_free` after
`sol_vm_free`, never before, because blocks made while the chunk ran point into
it — that is
[3.6](ROADMAP.md#36-a-caller-owned-chunk-must-outlive-blocks-defined-in-it), and
a host is its second case after the test suite. `sol_vm_intern_chunk` before
each run. Copy a value out before the VM goes. None of the three is checked and
none was written down for a host.

## What this says about 6.32

The entry's aside — that deciding it is also deciding to have an embedding
interface — is right, and understated. The pieces exist and compose; a host is
about a hundred lines. What is missing is that nothing said which of them a host
may rely on, and the first program to try it found a use-after-free that
nothing in the repository was shaped to catch.

That is an argument for writing the interface down before deciding what
permissions it should carry, rather than after.
