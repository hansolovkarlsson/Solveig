/* extend.h -- the interface an extension is written against.
 *
 * An *extension* is a capability the VM does not have and could not reasonably
 * grow: a window, a socket, a codec, a database. It is a C file that gets
 * compiled on its own, hangs one global off the machine's root, and is named
 * when a program is started rather than from inside it.
 *
 * This stands to extensions as `embed.h` stands to hosts, and the two are
 * different jobs. A host *contains* a machine and runs programs through it. An
 * extension is *loaded into* a machine somebody else started, and never sees
 * argv, the chunk, or the run. So the two headers overlap in what they promise
 * and not in what they are for.
 *
 * **This is the whole supported surface**, together with the three headers it
 * includes. Everything else under `solum/include` is the machine's own business
 * and may change without notice -- which was not true before this file existed,
 * and the difference is the point: what an extension could reach used to be
 * whatever the linker happened to keep, which is a surface nobody chose.
 *
 *     #include "solum/extend.h"
 *
 *     static SolValue prim_beep(SolVM *vm, SolValue self, SolValue *args, int argc)
 *     {
 *         (void)self;
 *         if (argc != 0) { sol_vm_runtime_error(vm, "beep takes no arguments"); }
 *         return SOL_NIL_VAL;
 *     }
 *
 *     int sol_extension_init(SolVM *vm, int abi)
 *     {
 *         if (abi != SOL_EXTENSION_ABI) return -1;
 *         SolObject *audio = sol_object_new(vm, vm->object_class);
 *         sol_object_define_primitive(vm, audio, "beep", prim_beep);
 *         sol_vm_set_global(vm, "audio", SOL_OBJ_VAL(audio));
 *         return 0;
 *     }
 *
 * See docs/extensions.md for the contract in prose, and the four rules below in
 * full. tests/test_extension.c holds every promise this file makes.
 */
#ifndef SOLUM_EXTEND_H
#define SOLUM_EXTEND_H

#include "solum/common.h"
#include "solum/embed.h"
#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"

/* The number an extension and this build have to agree on.
 *
 * Bumped whenever anything an extension can see changes shape -- `SolValue`,
 * `SolObject`, `SolSlot`, `SolPrimitive`, or the meaning of any call named
 * here. `SolValue` is passed by value and `SolObject`'s layout is exposed, so
 * that is nearly every struct change and the number will move often.
 *
 * The policy is `.sob`'s exactly: compare for equality, refuse, say so, and do
 * not guess. A bundle built against a different number is turned away with a
 * message telling you to rebuild it, which is loud and cheap. The alternative
 * is that it loads and reads a struct at the wrong offsets, which is neither.
 *
 * Deliberately not `SOLUM_VERSION`: a release that changes no struct should not
 * invalidate every bundle, and one that changes a struct without changing the
 * version must still be caught. */
#define SOL_EXTENSION_ABI 1

/* What every extension exports, and the only symbol a loader looks for.
 *
 * Answer 0 to say the extension installed itself, and anything else to refuse
 * -- which is what an ABI it does not recognise must do. A refusal is not a
 * failure of the program: it is reported, and the machine is left exactly as it
 * was, because an extension that refused has bound nothing.
 *
 * Called once per machine, after the built-ins are installed and before the
 * program runs. There is no unload: nothing here removes a global, for the same
 * reason nothing else does (ROADMAP 3.10). */
typedef int (*SolExtensionInit)(SolVM *vm, int abi);

/* ---- the four rules ------------------------------------------------------ *
 *
 * Each is something a newcomer gets wrong, and each was found by getting it
 * wrong rather than by reasoning about it.
 *
 * **1. Arity is not checked for you.** `sol_object_define_primitive_for` checks
 * the *receiver* and nothing else, so a primitive is handed whatever argument
 * count the sender wrote and must say so itself:
 *
 *     if (argc != 2) { sol_vm_runtime_error(vm, "dot expects two arrays"); ... }
 *
 * A block checks its own arity because it has one to check. A C function does
 * not.
 *
 * **2. Failure is out of band.** A primitive answers a SolValue and has no way
 * to say "this went wrong" in it, so it calls `sol_vm_runtime_error` and
 * returns anything -- `SOL_NIL_VAL` by convention. The error unwinds the way
 * every other one does.
 *
 * **3. Nothing may hold a heap pointer across an allocation unless it is
 * reachable from a root.** The collector marks the value stack, the frames, the
 * temporary-root stack and the class objects. A cell held only in a C local, or
 * in a struct C owns, is *none of those* -- and a block registered as a
 * callback's user data is the case that bites, because the sweep happens
 * between one call and the next and the failure is a wrong block rather than a
 * crash. `sol_gc_push_temp` covers a short window inside one primitive, and the
 * temp stack is eight deep -- overflowing it calls `exit(1)` with no
 * diagnostic. Anything held *between* calls goes in the registry below instead,
 * which is unbounded and can tell you when a token has gone stale.
 *
 * **4. Check `vm->had_error` after every call back into the language.** After
 * `sol_vm_call_block` or `sol_vm_send`, and before doing anything else. A
 * limit-stop sets it, and a limit is deliberately not catchable -- so a loop
 * that does not look will keep calling into a machine that has already been
 * stopped, which is the one way an extension can defeat `--steps`. */

/* ---- handing a resource back to a program -------------------------------- *
 *
 * A socket, a window, a connection, a compiled pattern -- anything the program
 * may hold and the machine cannot make sense of. `sol_foreign_new` wraps it in
 * a cell the collector understands:
 *
 *     static void close_socket(void *handle) { close((int)(intptr_t)handle); }
 *
 *     SolForeign *cell = sol_foreign_new(vm, (void *)(intptr_t)fd,
 *                                        close_socket, "socket", 0);
 *     return SOL_FOREIGN_VAL(cell);
 *
 * and the primitive that receives one back asks for it by kind:
 *
 *     int fd = (int)(intptr_t)sol_foreign_handle(args[0], "socket");
 *     if (fd == 0 && sol_foreign_handle(args[0], "socket") == NULL) {
 *         sol_vm_runtime_error(vm, "send expects an open socket");
 *         return SOL_NIL_VAL;
 *     }
 *
 * **`release` runs exactly once, and from two directions.** The collector calls
 * it when the program lets go of the value, which is the path that matters for
 * a program holding many in turn -- and `sol_vm_free` calls it for everything
 * still alive, whatever its reachability, which is the path that matters when a
 * limit took the program away mid-flight. There is deliberately no `close`
 * message: a program cannot be relied on to send one, and a stopped program
 * could not be given the chance.
 *
 * **`kind` must outlive the VM.** A string literal in the extension does. It is
 * compared with `strcmp`, so one extension's `"socket"` cannot be handed to
 * another extension's primitive that wanted its own.
 *
 * **`footprint` is what the resource costs where the machine cannot see it** --
 * a texture, a decoded image, a connection's buffers -- and is added to the
 * live-byte figure `--memory` is measured against. Zero when there is nothing
 * sensible to say, which is usual; a wrong guess is worse than none. */

/* ---- keeping a value alive between calls ---------------------------------- *
 *
 * **Rule 3 covers a window inside one primitive. This is the other half.**
 *
 * A toolkit takes a callback and a pointer to hand back with it -- GTK's
 * `gpointer user_data`, SDL's userdata, a signal handler's closure. The obvious
 * thing is to put a Solum block in that pointer, and it is wrong: the tracer
 * walks the value stack, the frames, the temporary roots and the class objects,
 * and a block in a C struct is none of them. So a collection between one
 * callback and the next sweeps it, and the next call runs **whatever now
 * occupies that cell**.
 *
 * That failure was measured before this existed, and it is not a crash:
 *
 *     #1
 *     probe: callback failed: 'block' takes 1 argument, got 0
 *
 * -- an arity complaint about a block the program never registered anywhere,
 * with nothing in it pointing at the collector.
 *
 * So: retain the value, keep the *token* in `user_data`, and look it up when
 * the callback fires.
 *
 *     typedef struct { SolVM *vm; SolRetained on_click; } Button;
 *
 *     button->on_click = sol_extension_retain(vm, args[0]);
 *
 *     static void clicked(GtkWidget *w, gpointer data)
 *     {
 *         Button *button = data;
 *         SolValue block;
 *         if (!sol_extension_retained(button->vm, button->on_click, &block)) {
 *             return;                     // released, or never valid
 *         }
 *         sol_vm_call_block(button->vm, block, NULL, 0);
 *         if (button->vm->had_error) { ... }         // rule 4
 *     }
 *
 *     // when the widget goes away
 *     sol_extension_release(button->vm, button->on_click);
 *
 * **Keeping the token rather than the SolValue is the point.** The collector
 * does not move cells, so a retained `SolValue` would stay valid -- but a token
 * that has been released answers *false*, where a stale `SolValue` answers a
 * plausible wrong block. The registry can tell you that you are wrong; a cached
 * value cannot, and being unable to is the whole defect.
 *
 * **Not reference counted.** Two retains of one value give two tokens, each
 * released on its own. Retaining twice and releasing once leaves it rooted,
 * which is the safe direction to be wrong in.
 *
 * Everything still retained is released when the VM goes down. */

/* A token standing for one retained value. Zero is never valid, so a zeroed
   struct means "nothing retained here" without anybody arranging it. */
typedef uint64_t SolRetained;
#define SOL_RETAINED_NONE ((SolRetained)0)

/* Roots `value` until released, and answers a token for it. Never answers
   SOL_RETAINED_NONE. */
SolRetained sol_extension_retain(SolVM *vm, SolValue value);

/* The value `token` stands for, or false if it was released, was never valid,
   or names a slot since reused. `*out` is untouched when this answers false, so
   a caller that reads it anyway reads its own initialiser rather than somebody
   else's value. */
bool sol_extension_retained(SolVM *vm, SolRetained token, SolValue *out);

/* Stops rooting it, and answers whether there was anything to stop. Releasing
   twice is not an error and answers false the second time. */
bool sol_extension_release(SolVM *vm, SolRetained token);

/* ---- what an extension may rely on --------------------------------------- *
 *
 * Declared in the headers above and named here so that the surface is one list
 * rather than something inferred from a header full of internals.
 *
 *   sol_object_new(vm, proto)                    an object; proto may be
 *                                                vm->object_class, and usually is
 *   sol_object_define(vm, obj, name, value)      bind a name to a value
 *   sol_object_define_primitive(vm, obj, name, fn)
 *   sol_object_define_primitive_for(vm, obj, name, fn, type)
 *                                                the same, for one receiver type
 *   sol_vm_set_global(vm, name, value)           hang the extension's global
 *   sol_vm_global(vm, name, &out)                read one back
 *
 *   sol_string_new(vm, chars, length)            copies; answers a SolString *
 *   sol_array_new(vm, capacity)
 *   sol_array_add(vm, array, value)
 *
 *   sol_foreign_new(vm, handle, release, kind, footprint)
 *                                                a resource the machine holds
 *                                                for you and gives back
 *   sol_foreign_handle(value, kind)              the handle, or NULL if it is
 *                                                the wrong kind or released
 *   sol_foreign_release(value)                   give it back now, in an order
 *                                                you choose
 *
 *   sol_extension_retain(vm, value)              keep it between calls
 *   sol_extension_retained(vm, token, &out)      get it back, or learn you
 *                                                cannot
 *   sol_extension_release(vm, token)             stop keeping it
 *
 *   sol_vm_call_block(vm, block, args, argc)     run a block -- then rule 4
 *   sol_vm_send(vm, receiver, name, args, argc)  send a message -- then rule 4
 *   sol_vm_runtime_error(vm, format, ...)        rule 2
 *   sol_gc_push_temp(vm, cell) / sol_gc_pop_temp(vm)     rule 3
 *
 *   vm->object_class, vm->integer_class, ...     the built-in classes
 *   vm->had_error                                rule 4
 *
 * A primitive an extension installs is indistinguishable from a built-in: same
 * slot, same dispatch, same speed, same reflection. `respondsTo` finds it and
 * `slots` lists it. That is a promise and not an accident -- it is what would
 * let a capability move out of the core without becoming second class.
 */

/* ---- loading ------------------------------------------------------------- *
 *
 * Two doors into the same contract. `extend.h` is deliberately free of any
 * mention of the dynamic linker, which lives behind `sol_extension_load` alone.
 */

/* Registers an extension linked into this binary: calls `init` with the ABI
   this build speaks, and answers whether it accepted.
 *
 * `name` is what a message names in a failure, so it should be what the user
 * asked for. On failure `*error` is set to a message on the heap and **the
 * caller frees it**; on success it is left alone. `error` may be NULL.
 *
 * This is what the test suite uses, because building a shared object part-way
 * through a test run is fragile under three CI configurations and impossible
 * under a sanitiser. It is a supported way to ship an extension, not only a
 * way to test one: a program that knows its extensions at build time may link
 * them and never touch the loader below. */
bool sol_extension_register(SolVM *vm, SolExtensionInit init, const char *name,
                            char **error);

/* Loads a shared object, finds `sol_extension_init` in it, and registers it.
 *
 * `path` is handed to `dlopen` unchanged, so it follows the platform's rules: a
 * name with a slash in it is a path, and one without is searched for. On
 * failure `*error` is set to a message on the heap and **the caller frees it**.
 *
 * The handle is never closed. Everything the extension installed -- primitives,
 * and any string constant a message of its own points at -- lives as long as
 * the machine, and unloading the code underneath them would leave slots
 * pointing into an unmapped page. Nothing unbinds a global either, and this is
 * the same decision seen from the other side.
 *
 * **A loaded extension is unlimited authority.** It runs as the program does,
 * past `--steps`, past `--memory`, past everything: those bound what the
 * *machine* does, and native code is not the machine. That is why loading is a
 * decision taken by whoever starts the program and why there is no message that
 * does it -- see docs/extensions.md, and ideas.md 6.32. */
bool sol_extension_load(SolVM *vm, const char *path, char **error);

#endif /* SOLUM_EXTEND_H */
