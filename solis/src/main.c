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

        SolChunk chunk;
        sol_chunk_init(&chunk);
        if (sol_compile(line, &chunk)) {
            /* Each line is its own chunk, but shares the VM, so objects bound
               on one line stay reachable on the next. */
            sol_vm_run(vm, &chunk);
        }
        sol_chunk_free(&chunk);
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
