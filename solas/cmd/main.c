/* solas -- the Solum compiler. Source in, bytecode out. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/bytecode.h"

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
            fprintf(stderr, "usage: solas [--dump] <file.sol>\n");
            return 64;
        }
    }
    if (path == NULL) {
        fprintf(stderr, "usage: solas [--dump] <file.sol>\n");
        return 64;
    }

    char *source = read_file(path);
    if (source == NULL) return 74;

    SolChunk chunk;
    sol_chunk_init(&chunk);

    int status = 0;
    if (sol_compile(source, &chunk)) {
        if (dump) sol_chunk_disassemble(&chunk, path);
        /* TODO: serialise `chunk` to a .sob file for solum to load. The format
           is undecided -- see docs/design.md, Open questions. */
    } else {
        status = 65;
    }

    sol_chunk_free(&chunk);
    free(source);
    return status;
}
