/* solis -- the interactive Solum. Compiles and executes one line at a time. */
#include <stdio.h>

#include "solas/compiler.h"
#include "solum/vm.h"

#define SOLIS_LINE_MAX 1024

static void repl(SolVM *vm)
{
    char line[SOLIS_LINE_MAX];

    printf("solis " SOLUM_VERSION " -- ctrl-d to exit\n");
    for (;;) {
        printf("> ");
        fflush(stdout);

        if (fgets(line, sizeof(line), stdin) == NULL) {
            printf("\n");
            break;
        }

        /* Each line is its own chunk, handed to the collector rather than freed
           here: a block defined on one line outlives the line, and a slot holds
           only a pointer to the code the chunk owns. The chunk is reclaimed once
           nothing refers to it, which for most lines is immediately.

           The temporary root covers the window before the first frame refers to
           it, so a collection triggered while compiling could not sweep it. */
        SolCode *code = sol_code_new(vm);
        sol_gc_push_temp(vm, &code->gc);

        if (sol_compile(line, &code->chunk)) {
            sol_vm_run(vm, &code->chunk);
        }
        sol_gc_pop_temp(vm);

        /* They share the VM, so globals and methods bound on one line are there
           on the next. */
    }
}

int main(int argc, char *argv[])
{
    (void)argv;
    if (argc != 1) {
        fprintf(stderr, "usage: solis\n");
        return 64;
    }

    SolVM vm;
    sol_vm_init(&vm);
    repl(&vm);
    sol_vm_free(&vm);
    return 0;
}
