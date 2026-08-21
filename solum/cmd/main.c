/* solvm -- the virtual machine. Loads a compiled chunk and executes it.
 *
 * The program is `solvm` while its sources live under `solum/`: the two are the
 * same word, SOLVM being how *solum* was written before the alphabet split V
 * into two letters. */
#include <stdio.h>
#include <string.h>

#include "solum/common.h"
#include "solum/serialize.h"
#include "solum/vm.h"

#define NAME "solvm"

/* Name, version, and the `.sob` format this build speaks. The format number is
   here because it is the one that goes wrong in practice: a file from a build
   with a different one is refused rather than misread, and this is where you
   find out which number you are holding. */
static void version(void)
{
    printf("%s " SOLUM_VERSION " (.sob format %d)\n", NAME, SOL_SOB_VERSION);
}

/* stdout for `--help`, stderr for a mistake. See the note in solas. */
static void usage(FILE *out)
{
    fprintf(out,
        "usage: solvm [options] <file.sob> [arguments...]\n"
        "\n"
        "Loads a compiled chunk and runs it.\n"
        "\n"
        "  --dump       disassemble the chunk before running it\n"
        "  --version    show the version and the .sob format, and stop\n"
        "  --help, -h   show this and stop\n"
        "\n"
        "Everything after the .sob belongs to the program and is what\n"
        "system:arguments answers, so a program may take a --dump or a --help of\n"
        "its own without this one intercepting it. Which is why these options\n"
        "have to come first.\n");
}

int main(int argc, char *argv[])
{
    bool dump = false;

    /* Everything after the `.sob` belongs to the program, `system:arguments`
       answers it, and solvm does not look at any of it -- so a program may take
       a `--dump` of its own without this one intercepting it. Which is why the
       flags have to come first. */
    int at = 1;
    while (at < argc) {
        if (strcmp(argv[at], "--help") == 0 || strcmp(argv[at], "-h") == 0) {
            usage(stdout);
            return 0;
        }
        if (strcmp(argv[at], "--version") == 0) {
            version();
            return 0;
        }
        if (strcmp(argv[at], "--dump") != 0) break;
        dump = true;
        at++;
    }
    if (at >= argc) {
        usage(stderr);
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
