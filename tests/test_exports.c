/* `exports`: the line an object draws between what it is for and how it works.
 *
 * The rule is one sentence -- from outside, an object that has drawn a boundary
 * *is* its export list -- and these are the ways out of it that had to be shut:
 * sending, binding, `slotAt`, `slots`, `respondsTo`, `perform`, and redrawing
 * the line from outside. A boundary that any one of those walks around is
 * decorative. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/gc.h"
#include "solum/object.h"
#include "solum/vm.h"

static SolResult run_source(SolVM *vm, const char *source)
{
    SolCode *code = sol_code_new(vm);
    sol_gc_push_temp(vm, &code->gc);
    bool compiled = sol_compile_source(source, "test", &code->chunk);
    assert(compiled);
    sol_gc_pop_temp(vm);
    return sol_vm_run(vm, &code->chunk);
}

static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

static void quiet_vm(SolVM *vm)
{
    sol_vm_init(vm);
    vm->report_errors = false;
}

/* The object under test, in every test below: two names published, one kept. */
#define COUNTER \
    "counter := object:new.\n" \
    "counter:n := #0.\n" \
    "counter:bump := { self:n := self:n:add(#1) }.\n" \
    "counter:total := { self:n }.\n" \
    "counter:exports(['bump, 'total]).\n"

/* Runs COUNTER followed by `line` and expects it to fail with `wanted` in the
   message -- which is how each way out of the boundary is checked. */
static void refused(const char *line, const char *wanted)
{
    char source[1024];
    snprintf(source, sizeof source, COUNTER "%s\n", line);

    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, source) != SOL_OK);
    if (strstr(vm.error_message.chars, wanted) == NULL) {
        printf("\n%s\n  wanted: %s\n  got:    %s\n", line, wanted,
               vm.error_message.chars);
        assert(false);
    }
    sol_vm_free(&vm);
}

/* ------------------------------------------------------------------ */

/* An exported name works from outside, and the object's own methods go on
   reaching what it kept -- which is the only reason a boundary is usable. */
static void test_the_exports_work_and_the_inside_is_unchanged(void)
{
    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, COUNTER
                      "counter:bump.\n"
                      "counter:bump.\n"
                      "seen := counter:total.\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 2);
    sol_vm_free(&vm);
    printf("  an export works from outside; inside still reaches everything\n");
}

/* Every way out of it, shut. The binding cases are the ones that matter: the
   failure this exists to stop is a write, not a read. */
static void test_every_way_out_is_shut(void)
{
    refused("counter:n:print.",              "'n' is not exported");
    refused("counter:n := #99.",             "'n' is not exported");
    refused("counter:fresh := #1.",          "'fresh' is not exported");
    refused("counter:slotAt('n):print.",     "'n' is not exported");
    refused("counter:perform('n):print.",    "'n' is not exported");
    refused("counter:exports(['bump, 'n]).", "cannot be redrawn from outside");
    printf("  send, bind, add, slotAt, perform and redrawing are all refused\n");
}

/* Reflection reports the boundary rather than walking around it. `respondsTo`
   in particular must agree with what sending would do -- its own comment in
   builtins.c makes that argument for the receiver check, and it holds here. */
static void test_reflection_keeps_the_line(void)
{
    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, COUNTER
                      "shown := counter:slots:size.\n"
                      "yes := counter:respondsTo('bump).\n"
                      "no  := counter:respondsTo('n).\n"
                      "list := counter:exports:size.\n"
                      "none := object:new:exports.\n") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "shown")) == 2);      /* not the three it has */
    assert(SOL_AS_BOOL(global(&vm, "yes")) == true);
    assert(SOL_AS_BOOL(global(&vm, "no")) == false);
    assert(SOL_AS_INT(global(&vm, "list")) == 2);
    assert(SOL_IS_NIL(global(&vm, "none")));            /* no boundary drawn */
    sol_vm_free(&vm);
    printf("  slots, respondsTo and exports all report the line\n");
}

/* Privacy is inherited, because the check compares the receiver against the
   sender's self rather than against whichever object holds the slot. A child's
   own method reaches what it inherited; an unrelated object does not. */
static void test_privacy_is_inherited_but_does_not_leak_sideways(void)
{
    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, COUNTER
                      "child := counter:new.\n"
                      "child:peek := { self:n }.\n"
                      "seen := child:peek.\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 0);
    sol_vm_free(&vm);

    quiet_vm(&vm);
    assert(run_source(&vm, COUNTER
                      "other := object:new.\n"
                      "other:pry := { counter:n }.\n"
                      "other:pry.\n") != SOL_OK);
    assert(strstr(vm.error_message.chars, "'n' is not exported") != NULL);
    sol_vm_free(&vm);
    printf("  a child reaches what it inherited; a stranger does not\n");
}

/* An object that never draws a line is untouched, which is the whole of the
   compatibility promise -- and what `examples/include.sol` depends on, since it
   extends an included object from outside on purpose. */
static void test_an_object_without_a_boundary_is_unchanged(void)
{
    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "open := object:new.\n"
                           "open:hidden := #7.\n"
                           "seen := open:hidden.\n"
                           "open:added := #8.\n"
                           "also := open:added.\n"
                           "count := open:slots:size.\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 7);
    assert(SOL_AS_INT(global(&vm, "also")) == 8);
    assert(SOL_AS_INT(global(&vm, "count")) == 2);
    sol_vm_free(&vm);
    printf("  an object that drew no line behaves exactly as before\n");
}

/* The list is a value the object holds, so the collector has to know about it.
   Under gc_stress every allocation sweeps, and the list is reachable from
   nothing but the object. */
static void test_the_export_list_survives_collection(void)
{
    SolVM vm;
    quiet_vm(&vm);
    vm.gc_stress = true;

    assert(run_source(&vm, COUNTER
                      "#200:repeat({ \"churn\":concat(\"more\") }).\n"
                      "still := counter:exports:size.\n"
                      "works := counter:total.\n") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "still")) == 2);
    assert(SOL_AS_INT(global(&vm, "works")) == 0);
    sol_vm_free(&vm);

    /* And the boundary still holds after all that. */
    quiet_vm(&vm);
    vm.gc_stress = true;
    assert(run_source(&vm, COUNTER
                      "#200:repeat({ \"churn\":concat(\"more\") }).\n"
                      "counter:n.\n") != SOL_OK);
    assert(strstr(vm.error_message.chars, "'n' is not exported") != NULL);
    sol_vm_free(&vm);
    printf("  the export list survives collection, and so does the boundary\n");
}

/* The list has to be symbols, and says so rather than quietly exporting
   nothing -- a boundary drawn from the wrong kind of list would be a boundary
   around everything. */
static void test_the_list_must_be_symbols(void)
{
    SolVM vm;
    quiet_vm(&vm);
    assert(run_source(&vm, "o := object:new.\no:exports('bump).\n") != SOL_OK);
    assert(strstr(vm.error_message.chars, "expects an array of symbols") != NULL);
    sol_vm_free(&vm);

    quiet_vm(&vm);
    assert(run_source(&vm, "o := object:new.\no:exports(['bump, \"total\"]).\n")
           != SOL_OK);
    assert(strstr(vm.error_message.chars, "element #2 is string") != NULL);
    sol_vm_free(&vm);
    printf("  an export list is symbols, and a wrong one says which element\n");
}

/* Written last because it is the one the feature exists for: the failure
   `ideas.md` named for years, now refused. */
static void test_the_documented_failure_is_refused(void)
{
    SolVM vm;
    quiet_vm(&vm);
    SolCode *code = sol_code_new(&vm);
    sol_gc_push_temp(&vm, &code->gc);
    SolSearchPath search = { 0 };
    const char *dirs[] = { "lib" };
    search.directories = (char **)dirs;
    search.count = 1;
    bool compiled = sol_compile_file("@include \"json.sol\".\n"
                                     "json:digits := \"abc\".\n",
                                     "test", &search, &code->chunk);
    sol_gc_pop_temp(&vm);
    assert(compiled);
    assert(sol_vm_run(&vm, &code->chunk) != SOL_OK);
    assert(strstr(vm.error_message.chars, "'digits' is not exported") != NULL);
    sol_vm_free(&vm);
    printf("  json:digits := \"abc\" from outside is refused\n");
}

int main(void)
{
    test_the_exports_work_and_the_inside_is_unchanged();
    test_every_way_out_is_shut();
    test_reflection_keeps_the_line();
    test_privacy_is_inherited_but_does_not_leak_sideways();
    test_an_object_without_a_boundary_is_unchanged();
    test_the_export_list_survives_collection();
    test_the_list_must_be_symbols();
    test_the_documented_failure_is_refused();

    printf("test_exports: ok\n");
    return 0;
}
