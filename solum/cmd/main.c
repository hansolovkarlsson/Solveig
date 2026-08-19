/* solum -- the virtual machine. Loads a compiled chunk and executes it. */
#include <stdio.h>

#include "solum/vm.h"

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "usage: solum <file.sob>\n");
        return 64;
    }

    /* TODO: load argv[1] into a SolChunk once the bytecode file format exists.
       Until then solis is the way to run code: it compiles and executes
       in-memory, with no serialisation step in between. */
    fprintf(stderr, "solum " SOLUM_VERSION ": cannot load '%s' yet -- "
                    "the bytecode file format is not defined\n", argv[1]);
    return 70;
}
