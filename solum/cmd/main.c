/* solvm -- the virtual machine. Loads a compiled chunk and executes it.
 *
 * The program is `solvm` while its sources live under `solum/`: the two are the
 * same word, SOLVM being how *solum* was written before the alphabet split V
 * into two letters. */
#include <stdio.h>
#include <string.h>

#include "solum/serialize.h"
#include "solum/vm.h"

static void usage(void)
{
    fprintf(stderr, "usage: solvm [--dump] <file.sob> [arguments...]\n");
}

int main(int argc, char *argv[])
{
    bool dump = false;

    /* Everything after the `.sob` belongs to the program, `system:arguments`
       answers it, and solvm does not look at any of it -- so a program may take
       a `--dump` of its own without this one intercepting it. Which is why the
       flags have to come first. */
    int at = 1;
    while (at < argc && strcmp(argv[at], "--dump") == 0) {
        dump = true;
        at++;
    }
    if (at >= argc) {
        usage();
        return 64;
    }
    const char *path = argv[at++];

    SolChunk chunk;
    SolSerResult loaded = sol_chunk_load(&chunk, path);
    if (loaded != SOL_SER_OK) {
        fprintf(stderr, "solvm: cannot load '%s': %s\n", path, sol_ser_message(loaded));
        return 65;
    }

    if (dump) sol_chunk_disassemble(&chunk, path);

    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_arguments(&vm, argc - at, argv + at);

    SolResult result = sol_vm_run(&vm, &chunk);
    int status = vm.exit_code;              /* read before the VM goes away */

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);

    if (result == SOL_EXIT) return status;
    return result == SOL_OK ? 0 : 70;
}
