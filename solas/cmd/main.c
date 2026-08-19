/* solas -- the Solum compiler. Source in, bytecode out. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/bytecode.h"
#include "solum/serialize.h"

static void usage(void)
{
    fprintf(stderr, "usage: solas [--dump] [-o out.sob] <file.sol>\n");
}

/* Reads a whole file into a NUL-terminated heap buffer, or NULL on failure. */
static char *read_file(const char *path)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "solas: could not open '%s'\n", path);
        return NULL;
    }
    fseek(file, 0L, SEEK_END);
    long size = ftell(file);
    rewind(file);

    char *buffer = malloc((size_t)size + 1);
    if (buffer == NULL) {
        fprintf(stderr, "solas: not enough memory to read '%s'\n", path);
        fclose(file);
        return NULL;
    }
    size_t read = fread(buffer, 1, (size_t)size, file);
    buffer[read] = '\0';
    fclose(file);
    return buffer;
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

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--dump") == 0) {
            dump = true;
        } else if (strcmp(argv[i], "-o") == 0) {
            if (++i >= argc) { usage(); return 64; }
            output = argv[i];
        } else if (path == NULL) {
            path = argv[i];
        } else {
            usage();
            return 64;
        }
    }
    if (path == NULL) { usage(); return 64; }

    char *source = read_file(path);
    if (source == NULL) return 74;

    SolChunk chunk;
    sol_chunk_init(&chunk);

    int status = 0;
    if (sol_compile(source, &chunk)) {
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
    return status;
}
