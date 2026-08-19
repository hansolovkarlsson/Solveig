/* solum -- the virtual machine. Loads a compiled chunk and executes it. */
#include <stdio.h>
#include <string.h>

#include "solum/serialize.h"
#include "solum/vm.h"

int main(int argc, char *argv[])
{
    bool dump = false;
    const char *path = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--dump") == 0) {
            dump = true;
        } else if (path == NULL) {
            path = argv[i];
        } else {
            fprintf(stderr, "usage: solum [--dump] <file.sob>\n");
            return 64;
        }
    }
    if (path == NULL) {
        fprintf(stderr, "usage: solum [--dump] <file.sob>\n");
        return 64;
    }

    SolChunk chunk;
    SolSerResult loaded = sol_chunk_load(&chunk, path);
    if (loaded != SOL_SER_OK) {
        fprintf(stderr, "solum: cannot load '%s': %s\n", path, sol_ser_message(loaded));
        return 65;
    }

    if (dump) sol_chunk_disassemble(&chunk, path);

    SolVM vm;
    sol_vm_init(&vm);
    SolResult result = sol_vm_run(&vm, &chunk);
    sol_vm_free(&vm);
    sol_chunk_free(&chunk);

    return result == SOL_OK ? 0 : 70;
}
