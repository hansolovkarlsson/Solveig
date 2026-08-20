/* solis -- the interactive Solum.
 *
 * Reads until the input could compile, then compiles and runs it. What decides
 * "could compile" is in solis/src/input.c. */
#include <stdio.h>

#include "solas/compiler.h"
#include "solis/input.h"
#include "solum/vm.h"

/* Each submission is its own chunk, handed to the collector rather than freed
   here: a block defined now outlives the input it was written in, and a slot
   holds only a pointer to the code the chunk owns. The chunk is reclaimed once
   nothing refers to it, which for most input is immediately.

   The temporary root covers the window before the first frame refers to it, so
   a collection triggered while compiling could not sweep it. */
static SolResult submit(SolVM *vm, const char *source)
{
    SolResult result = SOL_COMPILE_ERROR;
    SolCode *code = sol_code_new(vm);
    sol_gc_push_temp(vm, &code->gc);

    if (sol_compile(source, &code->chunk)) {
        result = sol_vm_run(vm, &code->chunk);
    }
    sol_gc_pop_temp(vm);

    /* They share the VM, so globals and methods bound by one submission are
       there for the next. */
    return result;
}

/* Answers the status to leave with. `system:exit` works at the prompt for the
   same reason it works in a program: it is a message, and the prompt runs the
   same machine. */
static int repl(SolVM *vm)
{
    int status = 0;
    SolisInput input = { NULL, 0, 0 };
    SolisScan  state;
    size_t     scanned = 0;

    sol_scan_reset(&state);
    printf("solis " SOLUM_VERSION " -- ctrl-d to exit\n");

    for (;;) {
        printf(input.length == 0 ? "> " : ".. ");
        fflush(stdout);

        if (!sol_input_read_line(&input, stdin)) {
            /* End of input. Anything half-typed is still compiled rather than
               dropped, so input that stops mid-expression says why. */
            if (input.length > 0 && submit(vm, input.text) == SOL_EXIT) {
                status = vm->exit_code;
            }
            printf("\n");
            break;
        }

        sol_scan(&state, input.text + scanned);
        scanned = input.length;
        if (sol_scan_wants_more(&state)) continue;

        if (submit(vm, input.text) == SOL_EXIT) {
            status = vm->exit_code;
            break;
        }
        sol_input_clear(&input);
        sol_scan_reset(&state);
        scanned = 0;
    }

    sol_input_free(&input);
    return status;
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
    int status = repl(&vm);
    sol_vm_free(&vm);
    return status;
}
