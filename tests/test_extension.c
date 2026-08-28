/* The extension contract: what a C extension may rely on.
 *
 * docs/extensions.md is the prose, solum/include/solum/extend.h is the header,
 * and this is what holds them. It is the same arrangement as test_embed.c, made
 * for the same reason: a surface nobody states is a surface nobody can check,
 * and the last time that was true here a use-after-free got out.
 *
 * **Nothing below builds a shared object.** The extensions are ordinary
 * functions in this file, registered through `sol_extension_register`, which is
 * the same door `sol_extension_load` walks through once `dlopen` has found the
 * entry point. Building a bundle part-way through a test run would need a
 * compiler at test time, which is fragile under three CI configurations and
 * impossible under a sanitiser -- and it would test the loader rather than the
 * contract.
 *
 * **The linker's half is not tested here, and cannot be.** Whether a loaded
 * bundle can resolve `sol_*` back into the program that loaded it depends on
 * what that program exports -- and a symbol reaches an executable's export
 * table only if the executable already referenced it. This file references
 * `sol_vm_set_global` on its own account, so it would find that symbol exported
 * however the link had been done, and an assertion here would pass while
 * `bin/solvm` stayed broken. That is exactly the mistake the first draft of
 * this file made.
 *
 * So the decisive case lives in test_cli.c, where a real bundle is handed to
 * the real binary: `test_an_extension_reaches_the_program`. What is left here
 * is the enumeration below, which is worth keeping for a different reason --
 * it is the promised surface written down in a form that fails the build if a
 * name in extend.h is deleted or renamed.
 */
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/extend.h"

/* ---- an extension, written the way the header says to --------------------- */

static SolValue prim_double(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    /* Rule 1: arity is not checked for you. */
    if (argc != 1 || args[0].type != SOL_INT) {
        sol_vm_runtime_error(vm, "double expects one integer");   /* rule 2 */
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(args[0].as.integer * 2);
}

static int init_arith(SolVM *vm, int abi)
{
    if (abi != SOL_EXTENSION_ABI) return -1;
    SolObject *arith = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, arith, "double", prim_double);
    sol_vm_set_global(vm, "arith", SOL_OBJ_VAL(arith));
    return 0;
}

/* One that refuses, the way a bundle built against another SolVM must. */
static int init_from_the_future(SolVM *vm, int abi)
{
    (void)vm;
    if (abi != SOL_EXTENSION_ABI + 1) return -1;
    /* Deliberately unreachable: a refusing extension binds nothing, and the
       test below checks that the machine is untouched. */
    sol_vm_set_global(vm, "future", SOL_INT_VAL(1));
    return 0;
}

/* ---- helpers -------------------------------------------------------------- */

static void compile(SolChunk *chunk, const char *source)
{
    sol_chunk_init(chunk);
    assert(sol_compile_source(source, "<test>", chunk));
}

/* Runs `source` on a machine `init` was registered into, and answers what the
   global `answer` holds, rendered. The caller frees it. */
static char *run_with(SolExtensionInit init, const char *source)
{
    SolVM vm;
    sol_vm_init(&vm);

    char *error = NULL;
    assert(sol_extension_register(&vm, init, "<test>", &error));
    assert(error == NULL);           /* untouched on success */

    SolChunk chunk;
    compile(&chunk, source);
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    char *answer = sol_vm_global_text(&vm, "answer");
    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    return answer;
}

/* ---- registration --------------------------------------------------------- */

static void test_an_extension_binds_a_global(void)
{
    char *answer = run_with(init_arith, "answer := arith:double(#21).");
    assert(answer != NULL);
    assert(strcmp(answer, "#42") == 0);
    free(answer);
    printf("  an extension binds a global a program can send to\n");
}

/* The promise that would let a capability leave the core without becoming
   second class: a primitive an extension installs is a primitive. */
static void test_it_is_indistinguishable_from_a_builtin(void)
{
    char *answer = run_with(init_arith, "answer := arith:respondsTo('double).");
    assert(answer != NULL);
    assert(strcmp(answer, "true") == 0);
    free(answer);

    answer = run_with(init_arith, "answer := arith:slots:size.");
    assert(answer != NULL);
    assert(strcmp(answer, "#1") == 0);
    free(answer);
    printf("  reflection finds it, exactly as it finds a built-in\n");
}

/* Rule 1, from the other side: nothing checks arity for the primitive, so the
   primitive's own check is what the program meets. */
static void test_the_primitive_checks_its_own_arity(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_error_reporting(&vm, false);
    assert(sol_extension_register(&vm, init_arith, "<test>", NULL));

    SolChunk chunk;
    compile(&chunk, "arith:double.");
    assert(sol_vm_run(&vm, &chunk) == SOL_RUNTIME_ERROR);
    assert(strstr(sol_vm_error_message(&vm), "one integer") != NULL);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a primitive's own arity check is what a program meets\n");
}

/* ---- the handshake -------------------------------------------------------- */

static void test_a_mismatched_abi_is_refused(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    char *error = NULL;
    assert(!sol_extension_register(&vm, init_from_the_future, "future.so", &error));
    assert(error != NULL);
    assert(strstr(error, "future.so") != NULL);       /* says which one */
    assert(strstr(error, "rebuild") != NULL);         /* and what to do */
    free(error);

    sol_vm_free(&vm);
    printf("  an extension built against another SolVM is refused by name\n");
}

/* A refusal is not a half-load: the machine is exactly as it was. */
static void test_a_refusal_leaves_the_machine_alone(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    assert(!sol_extension_register(&vm, init_from_the_future, "future.so", NULL));

    SolValue bound;
    assert(!sol_vm_global(&vm, "future", &bound));
    sol_vm_free(&vm);
    printf("  a refused extension has bound nothing\n");
}

static void test_the_error_is_optional(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    /* NULL for `error` is allowed, and must not be written through. */
    assert(!sol_extension_register(&vm, init_from_the_future, "future.so", NULL));
    assert(!sol_extension_register(&vm, NULL, "nothing.so", NULL));
    sol_vm_free(&vm);
    printf("  a caller that does not want the message may pass NULL\n");
}

/* ---- loading -------------------------------------------------------------- */

static void test_a_missing_bundle_is_reported_not_fatal(void)
{
    SolVM vm;
    sol_vm_init(&vm);

    char *error = NULL;
    assert(!sol_extension_load(&vm, "./no-such-extension.so", &error));
    assert(error != NULL);
    assert(strstr(error, "no-such-extension") != NULL);
    free(error);

    /* And the machine still runs, which is what makes this a refusal rather
       than a failure of the program. */
    SolChunk chunk;
    compile(&chunk, "answer := #1:add(#1).");
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a bundle that will not load is refused, and the machine lives\n");
}

/* Every name extend.h promises, named once so that removing one breaks a build.
 *
 * **This is weaker than it looks and the weakness is the point of the comment.**
 * `dlopen(NULL)` is this program, and this program calls most of these itself,
 * so their objects are linked in whatever the flags said and the lookup
 * succeeds either way. It caught nothing when the link was wrong; test_cli.c's
 * `test_an_extension_reaches_the_program` did.
 *
 * What it is good for is the other direction: a name that goes out of extend.h
 * without going out of here fails to compile, and a name that stops existing
 * fails here. That is a list kept honest, not a link kept honest. */
static void test_the_promised_surface_is_exported(void)
{
    static const char *promised[] = {
        "sol_extension_register", "sol_extension_load",
        "sol_object_new", "sol_object_define",
        "sol_object_define_primitive", "sol_object_define_primitive_for",
        "sol_vm_set_global", "sol_vm_global",
        "sol_string_new", "sol_array_new", "sol_array_add",
        "sol_vm_call_block", "sol_vm_send", "sol_vm_runtime_error",
        "sol_gc_push_temp", "sol_gc_pop_temp",
    };

    void *self = dlopen(NULL, RTLD_LAZY);
    assert(self != NULL);

    int missing = 0;
    for (size_t i = 0; i < sizeof promised / sizeof promised[0]; i++) {
        dlerror();
        if (dlsym(self, promised[i]) == NULL) {
            fprintf(stderr, "  MISSING from the dynamic symbol table: %s\n",
                    promised[i]);
            missing++;
        }
    }
    if (missing > 0) {
        fprintf(stderr,
                "  %d of %zu promised symbols could not be found. Either a name\n"
                "  left extend.h without leaving this list, or the Makefile's\n"
                "  whole-archive link regressed -- see WHOLE_LIB there.\n",
                missing, sizeof promised / sizeof promised[0]);
    }
    assert(missing == 0);
    dlclose(self);
    printf("  every name extend.h promises still exists and is spelled the same\n");
}

/* ---- ordering ------------------------------------------------------------- */

/* Loaded in the order written, so one that reads a name another bound can be
   ordered after it. */
static int init_first(SolVM *vm, int abi)
{
    if (abi != SOL_EXTENSION_ABI) return -1;
    sol_vm_set_global(vm, "order", SOL_INT_VAL(1));
    return 0;
}

static int init_second(SolVM *vm, int abi)
{
    if (abi != SOL_EXTENSION_ABI) return -1;
    SolValue earlier;
    /* Sees what the one before it bound. */
    assert(sol_vm_global(vm, "order", &earlier));
    sol_vm_set_global(vm, "order", SOL_INT_VAL(earlier.as.integer + 1));
    return 0;
}

static void test_extensions_load_in_the_order_written(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    assert(sol_extension_register(&vm, init_first, "first", NULL));
    assert(sol_extension_register(&vm, init_second, "second", NULL));

    SolValue order;
    assert(sol_vm_global(&vm, "order", &order));
    assert(order.type == SOL_INT && order.as.integer == 2);

    sol_vm_free(&vm);
    printf("  they are loaded in the order written, and can see each other\n");
}

/* ---- limits --------------------------------------------------------------- */

/* Rule 4 is the extension's to keep, and this is the reason it matters: a limit
   stops the *machine*, and native code is not the machine. What is asserted
   here is only that the limit still ends the run -- an extension that ignored
   `had_error` in a loop of its own could not be caught by anything here, which
   is why the rule is written down rather than enforced. */
static void test_a_limit_still_stops_a_program_using_an_extension(void)
{
    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_error_reporting(&vm, false);
    sol_vm_set_step_limit(&vm, 2000);
    assert(sol_extension_register(&vm, init_arith, "<test>", NULL));

    SolChunk chunk;
    compile(&chunk, "{ true }:whileTrue({ arith:double(#1) }).");
    assert(sol_vm_run(&vm, &chunk) == SOL_STOPPED);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    printf("  a step limit still ends a program that is calling an extension\n");
}

int main(void)
{
    printf("the extension contract\n");
    test_an_extension_binds_a_global();
    test_it_is_indistinguishable_from_a_builtin();
    test_the_primitive_checks_its_own_arity();
    test_a_mismatched_abi_is_refused();
    test_a_refusal_leaves_the_machine_alone();
    test_the_error_is_optional();
    test_a_missing_bundle_is_reported_not_fatal();
    test_the_promised_surface_is_exported();
    test_extensions_load_in_the_order_written();
    test_a_limit_still_stops_a_program_using_an_extension();
    printf("ok\n");
    return 0;
}
