/* solvm -- the virtual machine. Loads a compiled chunk and executes it.
 *
 * The program is `solvm` while its sources live under `solum/`: the two are the
 * same word, SOLVM being how *solum* was written before the alphabet split V
 * into two letters. */
#include <stdio.h>
#include <stdlib.h>
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
        "  --trace      write the call tree to stderr as it runs\n"
        "  --trace=N    the same, following calls only N deep\n"
        "  --steps=N    stop the program after N instructions\n"
        "  --memory=N   stop it if it holds more than N bytes; K, M and G\n"
        "               may be used, so --memory=64M\n"
        "  --version    show the version and the .sob format, and stop\n"
        "  --help, -h   show this and stop\n"
        "\n"
        "Everything after the .sob belongs to the program and is what\n"
        "system:arguments answers, so a program may take a --dump or a --help of\n"
        "its own without this one intercepting it. Which is why these options\n"
        "have to come first.\n"
        "\n"
        "A program stopped by --steps or --memory exits with status 124, which is\n"
        "neither the 0 of finishing nor the 70 of failing: it did not finish, and\n"
        "nothing it did was wrong. Neither limit can be caught from inside the\n"
        "program, and there is no message that reads or changes them.\n");
}

/* A byte count for --memory, with K, M or G if the number is unwieldy without
   one. Powers of 1024, since the thing being measured is memory. */
static bool parse_size(const char *text, size_t *out)
{
    char *end;
    unsigned long long n = strtoull(text, &end, 10);
    if (end == text) return false;

    unsigned long long scale = 1;
    if      (*end == 'K' || *end == 'k') { scale = 1024ULL; end++; }
    else if (*end == 'M' || *end == 'm') { scale = 1024ULL * 1024; end++; }
    else if (*end == 'G' || *end == 'g') { scale = 1024ULL * 1024 * 1024; end++; }

    if (*end != '\0' || n == 0) return false;
    if (n > (unsigned long long)SIZE_MAX / scale) return false;

    *out = (size_t)(n * scale);
    return true;
}

int main(int argc, char *argv[])
{
    bool dump = false;
    bool trace = false;
    int  trace_depth = 0;

    /* Zero is no limit, which is what a person running their own program at a
       terminal wants: they have a ctrl-c, and a budget chosen in advance by
       somebody who did not know what the program was going to do. */
    unsigned long long steps = 0;
    size_t memory = 0;

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
        if (strcmp(argv[at], "--trace") == 0) {
            trace = true;
            at++;
            continue;
        }
        if (strncmp(argv[at], "--trace=", 8) == 0) {
            char *end;
            long depth = strtol(argv[at] + 8, &end, 10);
            if (*end != '\0' || depth < 1 || depth > 64) {
                fprintf(stderr, "solvm: --trace=N wants a depth from 1 to 64\n");
                return 64;
            }
            trace = true;
            trace_depth = (int)depth;
            at++;
            continue;
        }
        if (strncmp(argv[at], "--steps=", 8) == 0) {
            char *end;
            steps = strtoull(argv[at] + 8, &end, 10);
            if (*end != '\0' || end == argv[at] + 8 || steps == 0) {
                fprintf(stderr, "solvm: --steps=N wants a count of 1 or more\n");
                return 64;
            }
            at++;
            continue;
        }
        if (strncmp(argv[at], "--memory=", 9) == 0) {
            if (!parse_size(argv[at] + 9, &memory)) {
                fprintf(stderr, "solvm: --memory=N wants a size, such as 64M\n");
                return 64;
            }
            at++;
            continue;
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
    vm.trace = trace;
    vm.trace_depth = trace_depth;
    sol_vm_set_step_limit(&vm, steps);
    sol_vm_set_memory_limit(&vm, memory);
    sol_vm_set_arguments(&vm, argc - at, argv + at);

    SolResult result = sol_vm_run(&vm, &chunk);
    int status = vm.exit_code;              /* read before the VM goes away */

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);

    if (result == SOL_EXIT) return status;

    /* 124, which is what `timeout` answers, and for the same reason: the
       program was taken away rather than finishing or failing, and a host that
       treats that as an ordinary failure will go looking for a bug that is not
       there. */
    if (result == SOL_STOPPED) return 124;

    return result == SOL_OK ? 0 : 70;
}
