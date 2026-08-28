/* A real extension, built as a real shared object, for the one question that
 * cannot be answered from inside a test binary.
 *
 * `test_extension.c` registers its extensions as ordinary functions, which
 * tests the contract and deliberately not the linker. But whether a *loaded*
 * bundle can resolve `sol_*` back into the program that loaded it depends on
 * what that program exports, and a symbol reaches an executable's export table
 * only if the executable already referenced it -- so a test binary that calls
 * `sol_vm_set_global` itself would find it exported however the link was done,
 * and would prove nothing.
 *
 * `bin/solvm` does not call it. Nothing in the four front ends calls anything
 * in embed.c, so before the Makefile's whole-archive link those six functions
 * were in the archive and in no binary's export table:
 *
 *     sol_vm_set_global   sol_vm_global      sol_vm_global_text
 *     sol_vm_set_global_text   sol_vm_error_message   sol_vm_error_trace
 *
 * **So this file calls `sol_vm_set_global` on purpose.** It is the historical
 * defect turned into a fixture: build this, hand it to `bin/solvm`, and a
 * regression in the link flags is a failed `dlopen` rather than something
 * discovered by somebody else's extension a year later.
 *
 * Built by the Makefile, not by the test at run time -- see the `ext_probe.so`
 * rule there.
 */
#include "solum/extend.h"

/* Deliberately drawn from the far corners of the promised surface, so that this
   fails if any part of it stopped being exported rather than only the part an
   extension is likeliest to touch first. */
static SolValue prim_shout(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_STRING) {
        sol_vm_runtime_error(vm, "shout expects one string");
        return SOL_NIL_VAL;
    }
    /* sol_vm_send, so that an override would be honoured -- and so that this
       file depends on it being exported. */
    SolValue loud = sol_vm_send(vm, args[0], "asUppercase", NULL, 0);
    if (vm->had_error) return SOL_NIL_VAL;             /* rule 4 */
    return loud;
}

/* Uses the array calls and a temporary root, which is rule 3's mechanism. */
static SolValue prim_three(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args;
    if (argc != 0) {
        sol_vm_runtime_error(vm, "three takes no arguments");
        return SOL_NIL_VAL;
    }
    SolArray *array = sol_array_new(vm, 3);
    sol_gc_push_temp(vm, (SolGCHeader *)array);
    for (int i = 1; i <= 3; i++) {
        SolString *text = sol_string_new(vm, "x", 1);
        sol_array_add(vm, array, SOL_STRING_VAL(text));
    }
    sol_gc_pop_temp(vm);
    return SOL_ARRAY_VAL(array);
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != SOL_EXTENSION_ABI) return -1;

    SolObject *probe = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, probe, "shout", prim_shout);
    sol_object_define_primitive(vm, probe, "three", prim_three);
    sol_object_define(vm, probe, "loaded", SOL_BOOL_VAL(true));

    /* The line this whole file exists for. */
    sol_vm_set_global(vm, "probe", SOL_OBJ_VAL(probe));
    return 0;
}
