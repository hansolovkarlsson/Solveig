/* embed.h -- the interface a C program embeds Solum through.
 *
 * `solvm` runs a program and exits. A *host* keeps a machine and runs programs
 * through it on its own behalf -- a webserver rendering a page per request, an
 * editor evaluating a snippet, a tool scripted in Solum. That was possible from
 * the first release and documented nowhere, so the first program to try it
 * found a use-after-free (0.14.1). This header is the answer to *why nobody
 * noticed*: there was no statement of what a host may rely on, so there was
 * nothing to test against and nothing to get wrong.
 *
 * **This is the whole supported surface.** Everything a host needs is declared
 * here or in the two headers below it; anything else in solum/include is the
 * machine's own business and may change without notice. See docs/embedding.md
 * for the contract in prose -- lifetimes, ordering, and what is deliberately
 * not promised.
 *
 * Compiling is a separate component and stays that way: a host includes
 * `solas/compiler.h` to turn source into a chunk, and this to run one. Solas
 * and SolVM meet only at bytecode.h, and embedding does not change that.
 *
 *     #include "solas/compiler.h"
 *     #include "solum/embed.h"
 *
 *     SolChunk chunk;
 *     sol_chunk_init(&chunk);
 *     if (!sol_compile_source(source, "<host>", &chunk)) { ... }
 *
 *     SolVM vm;
 *     sol_vm_init(&vm);
 *     sol_vm_set_step_limit(&vm, 200000);
 *     sol_vm_set_memory_limit(&vm, 8u << 20);
 *     sol_vm_set_global_text(&vm, "request", body);
 *
 *     if (sol_vm_run(&vm, &chunk) == SOL_OK) {
 *         char *answer = sol_vm_global_text(&vm, "answer");
 *         ...
 *         free(answer);
 *     }
 *
 *     sol_vm_free(&vm);
 *     sol_chunk_free(&chunk);        // after the VM, never before
 */
#ifndef SOLUM_EMBED_H
#define SOLUM_EMBED_H

#include "solum/bytecode.h"
#include "solum/common.h"
#include "solum/value.h"
#include "solum/vm.h"

/* ---- what a host already had ------------------------------------------- *
 *
 * Declared in vm.h and named here so that the supported surface is one list
 * rather than something to be inferred from a header full of internals:
 *
 *   sol_vm_init(vm)                     build a machine
 *   sol_vm_free(vm)                     take it down; everything it made dies
 *   sol_vm_run(vm, chunk)               run a chunk to completion
 *   sol_vm_set_step_limit(vm, n)        what it may spend, before it starts
 *   sol_vm_set_memory_limit(vm, bytes)
 *   sol_vm_set_arguments(vm, argc, argv)   what `system:arguments` answers
 *
 * `sol_vm_run` answers a SolResult, and the five cases are the whole of what a
 * host learns about how it went: SOL_OK, SOL_EXIT (with `vm->exit_code`),
 * SOL_STOPPED (a limit ended it), SOL_RUNTIME_ERROR, SOL_COMPILE_ERROR. They
 * are distinct on purpose -- a stopped program did not fail, and a host that
 * treated it as a bug would go looking for one that is not there.
 *
 * A host does **not** need to call `sol_vm_intern_chunk`. `sol_vm_run` does it,
 * every time, which is what lets one chunk serve any number of machines.
 */

/* ---- passing values in and out ----------------------------------------- *
 *
 * A script's globals are slots on the VM's root object, so this is where a host
 * and a script meet. Both sides agree a name; nothing checks that they do,
 * which is the weakest joint in this interface and is said so in
 * docs/embedding.md rather than hidden.
 *
 * Everything a run made dies with `sol_vm_free`, so a value read out is read
 * *before* the machine goes down, and the text forms below copy rather than
 * borrow for exactly that reason.
 */

/* The value bound to a global, or false when nothing of that name is bound.
   Valid until the next run or `sol_vm_free`, whichever comes first. */
bool sol_vm_global(SolVM *vm, const char *name, SolValue *out);

/* The same, rendered -- `#45`, `"hi"`, `[#1, #2]`, the form `print` shows. On
   the heap and **the caller frees it**, so it outlives the machine. NULL when
   the name is unbound.
 *
   Rendering calls `asString`, which is a send like any other, so this can fail
   the way a send can: a value whose `asString` raises answers NULL and leaves
   the VM's error set. Do not call it on a VM that is already failing. */
char *sol_vm_global_text(SolVM *vm, const char *name);

/* Binds a global, which is how a host hands a script its input before the run.
   Rebinds if the name is already bound. */
void sol_vm_set_global(SolVM *vm, const char *name, SolValue value);

/* The same for text, which is what a host usually has. Copies `chars`, so the
   caller's string need not outlive the call, and the script sees an ordinary
   string it can `split` and `concat` like any other. */
void sol_vm_set_global_text(SolVM *vm, const char *name, const char *chars);

/* ---- what went wrong --------------------------------------------------- *
 *
 * Set when a run answered SOL_RUNTIME_ERROR or SOL_STOPPED, and kept until the
 * next run clears them. The message alone is what a handler inside the language
 * would have been given; the trace is the frames beneath it, already formatted
 * with one line per frame.
 *
 * Both point into the VM and die with it. Copy what you mean to keep.
 *
 * A failing run **also writes both to stderr**, and there is currently no way
 * to ask it not to. A host that wants failures in its own log gets them in two
 * places. That is a real gap rather than an oversight in this comment; see
 * docs/embedding.md.
 */
const char *sol_vm_error_message(const SolVM *vm);
const char *sol_vm_error_trace(const SolVM *vm);

#endif /* SOLUM_EMBED_H */
