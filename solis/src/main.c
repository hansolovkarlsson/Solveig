/* solis -- the interactive Solum. Compiles and executes one line at a time. */
#include <stdio.h>
#include <stdlib.h>

#include "solas/compiler.h"
#include "solum/vm.h"

#define SOLIS_LINE_MAX 1024

/* Every chunk compiled this session, kept alive until it ends.
 *
 * A method is owned by the chunk that compiled it, and a class holds only a
 * pointer, so freeing a line's chunk would leave any method it defined
 * dangling. The REPL therefore accumulates chunks rather than freeing each one
 * after it runs. A real fix needs the collector to own methods. */
typedef struct {
    int       count;
    int       capacity;
    SolChunk *chunks;
} ChunkList;

static SolChunk *chunk_list_add(ChunkList *list)
{
    if (list->capacity < list->count + 1) {
        int capacity = list->capacity < 8 ? 8 : list->capacity * 2;
        SolChunk *grown = realloc(list->chunks, sizeof(SolChunk) * (size_t)capacity);
        if (grown == NULL) {
            fprintf(stderr, "solis: out of memory\n");
            exit(1);
        }
        list->chunks = grown;
        list->capacity = capacity;
    }
    SolChunk *chunk = &list->chunks[list->count++];
    sol_chunk_init(chunk);
    return chunk;
}

static void chunk_list_free(ChunkList *list)
{
    for (int i = 0; i < list->count; i++) sol_chunk_free(&list->chunks[i]);
    free(list->chunks);
    list->chunks = NULL;
    list->count = list->capacity = 0;
}

static void repl(SolVM *vm, ChunkList *chunks)
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

        /* Each line is its own chunk, but they share the VM, so globals and
           methods bound on one line are there on the next. */
        SolChunk *chunk = chunk_list_add(chunks);
        if (sol_compile(line, chunk)) {
            sol_vm_run(vm, chunk);
        }
    }
}

int main(int argc, char *argv[])
{
    (void)argv;
    if (argc != 1) {
        fprintf(stderr, "usage: solis\n");
        return 64;
    }

    ChunkList chunks = { 0, 0, NULL };
    SolVM vm;
    sol_vm_init(&vm);
    repl(&vm, &chunks);
    sol_vm_free(&vm);
    chunk_list_free(&chunks);
    return 0;
}
