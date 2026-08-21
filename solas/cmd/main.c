/* solas -- the Solum compiler. Source in, bytecode out. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/bytecode.h"
#include "solum/serialize.h"

static void usage(void)
{
    fprintf(stderr,
        "usage: solas [--dump] [-o out.sob] [-I dir]... <file.sol>\n"
        "  -I dir   where an @include falls back to when the file is not\n"
        "           beside the one including it; repeatable, first wins.\n"
        "           SOLUM_PATH and the library beside this binary are added\n"
        "           after any given here.\n");
}

/* "prog.sol" -> "prog.sob"; anything else just gains ".sob". */
static char *default_output_path(const char *source_path)
{
    size_t len = strlen(source_path);
    bool has_sol = len > 4 && strcmp(source_path + len - 4, ".sol") == 0;
    size_t base = has_sol ? len - 4 : len;

    char *out = malloc(base + 5);
    if (out == NULL) return NULL;
    memcpy(out, source_path, base);
    memcpy(out + base, ".sob", 5);
    return out;
}

int main(int argc, char *argv[])
{
    bool dump = false;
    const char *path = NULL;
    const char *output = NULL;

    SolSearchPath search;
    sol_search_path_init(&search);

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--dump") == 0) {
            dump = true;
        } else if (strcmp(argv[i], "-o") == 0) {
            if (++i >= argc) { usage(); sol_search_path_free(&search); return 64; }
            output = argv[i];
        } else if (strcmp(argv[i], "-I") == 0) {
            if (++i >= argc) { usage(); sol_search_path_free(&search); return 64; }
            sol_search_path_add(&search, argv[i]);
        } else if (path == NULL) {
            path = argv[i];
        } else {
            usage();
            sol_search_path_free(&search);
            return 64;
        }
    }
    if (path == NULL) { usage(); sol_search_path_free(&search); return 64; }

    /* After the -I arguments, so an explicit one wins over the shipped
       library. */
    sol_search_path_add_defaults(&search, argv[0]);

    char *source = sol_read_file(path);
    if (source == NULL) {
        fprintf(stderr, "solas: could not read '%s'\n", path);
        sol_search_path_free(&search);
        return 74;
    }

    SolChunk chunk;
    sol_chunk_init(&chunk);

    int status = 0;
    if (sol_compile_file(source, path, &search, &chunk)) {
        if (dump) sol_chunk_disassemble(&chunk, path);

        char *owned = NULL;
        const char *target = output;
        if (target == NULL) {
            owned = default_output_path(path);
            target = owned;
        }

        if (target == NULL) {
            fprintf(stderr, "solas: out of memory\n");
            status = 74;
        } else {
            SolSerResult result = sol_chunk_save(&chunk, target);
            if (result != SOL_SER_OK) {
                fprintf(stderr, "solas: could not write '%s': %s\n",
                        target, sol_ser_message(result));
                status = 74;
            }
        }
        free(owned);
    } else {
        status = 65;
    }

    sol_chunk_free(&chunk);
    free(source);
    sol_search_path_free(&search);
    return status;
}
