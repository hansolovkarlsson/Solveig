/* probe_host.c -- the smallest thing that could load an extension.
 *
 * Not a proposal for what the loader should look like. It exists to find out
 * what the path actually wants, which is what ideas.md asks for before any of
 * the design above it is taken seriously.
 *
 *   probe_host <bundle.so> <script.sol>
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

#include "solas/compiler.h"
#include "solum/embed.h"

typedef int (*SolExtensionInit)(SolVM *vm, int abi);

#define PROBE_ABI 1

static char *read_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); return NULL; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)n + 1);
    size_t got = fread(buf, 1, (size_t)n, f);
    buf[got] = '\0';
    fclose(f);
    return buf;
}

int main(int argc, char *argv[])
{
    if (argc < 2) { fprintf(stderr, "usage: probe_host [bundle ...] <script.sol>\n"); return 2; }

    SolVM vm;
    sol_vm_init(&vm);

    /* The load happens before the run, and after the built-ins: an extension
       hangs its global off the same root they used. */
    /* Every argument but the last is a bundle. This is the whole of the
       answer to "do I need a host per combination": they are independent
       dlopens into one machine, in any number and any order. */
    for (int i = 1; i < argc - 1; i++) {
        void *handle = dlopen(argv[i], RTLD_NOW | RTLD_LOCAL);
        if (!handle) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }

        SolExtensionInit init = (SolExtensionInit)dlsym(handle, "sol_extension_init");
        if (!init) { fprintf(stderr, "dlsym: %s\n", dlerror()); return 1; }

        if (init(&vm, PROBE_ABI) != 0) {
            fprintf(stderr, "probe_host: %s refused ABI %d\n", argv[i], PROBE_ABI);
            return 1;
        }
    }

    char *source = read_file(argv[argc - 1]);
    if (!source) return 1;

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add_defaults(&search, argv[0]);

    SolChunk chunk;
    sol_chunk_init(&chunk);
    if (!sol_compile_file(source, argv[argc - 1], &search, &chunk)) return 1;

    SolResult result = sol_vm_run(&vm, &chunk);

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    sol_search_path_free(&search);
    free(source);
    /* dlclose deliberately not called: see what the probe found. */
    return result == SOL_OK || result == SOL_EXIT ? 0 : 1;
}
