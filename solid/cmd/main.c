/* solid -- the Solum interactive debugger.
 *
 * *sol-interactive-debugger*, and *solidus* is Latin for firm, whole, sound: a
 * debugger is the tool for finding out whether a program is sound, standing on
 * ground the language calls *solum*. See docs/ROADMAP.md 6.29.
 *
 * It runs a program on an ordinary VM with a hook set, so what it can show is
 * what the chunk carries -- the file and line of every frame, and what each
 * slot was called. Both were built for this before it existed.
 */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solid/debugger.h"
#include "solum/common.h"
#include "solum/extend.h"
#include "solum/serialize.h"
#include "solum/vm.h"

#define NAME "solid"

static void version(void)
{
    printf("%s " SOLUM_VERSION " (.sob format %d)\n", NAME, SOL_SOB_VERSION);
}

static void usage(FILE *out)
{
    fprintf(out,
        "usage: solid [options] <file.sol|file.sob> [arguments...]\n"
        "\n"
        "Runs a program and stops at the first line, ready for commands.\n"
        "\n"
        "  -I <dir>     where an @include falls back to; repeatable\n"
        "  --extension=PATH\n"
        "               load a C extension before the program runs, so that a\n"
        "               program which needs one can be stepped through. May be\n"
        "               given more than once, and loaded in the order written\n"
        "  --version    show the version and the .sob format, and stop\n"
        "  --help, -h   show this and stop\n"
        "\n"
        "An extension is named here rather than from inside the program: it runs\n"
        "as native code, past every limit, so granting that is the decision of\n"
        "whoever starts the program. Stepping stops inside Solum and never\n"
        "inside an extension, which is C and has no lines to stop on. See\n"
        "docs/extensions.md.\n"
        "\n"
        "Everything after the file belongs to the program, so a script may take\n"
        "options of its own. Which is why these have to come first.\n"
        "\n"
        "At the prompt, `help` lists what it understands.\n");
}

static bool is_bytecode(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (f == NULL) return false;

    char magic[4];
    bool yes = fread(magic, 1, sizeof magic, f) == sizeof magic &&
               memcmp(magic, SOL_SOB_MAGIC, sizeof magic) == 0;
    fclose(f);
    return yes;
}

int main(int argc, char *argv[])
{
    SolSearchPath search;
    sol_search_path_init(&search);

    /* Named before the machine exists, loaded once it does. Sized by argc,
       since every one of them came from an argument. */
    const char **extensions = NULL;
    int extension_count = 0;

    int at = 1;
    while (at < argc) {
        if (strcmp(argv[at], "--help") == 0 || strcmp(argv[at], "-h") == 0) {
            usage(stdout);
            free(extensions);
            sol_search_path_free(&search);
            return 0;
        }
        if (strcmp(argv[at], "--version") == 0) {
            version();
            free(extensions);
            sol_search_path_free(&search);
            return 0;
        }
        if (strncmp(argv[at], "--extension=", 12) == 0) {
            if (argv[at][12] == '\0') {
                fprintf(stderr, "solid: --extension= wants a path\n");
                free(extensions);
                sol_search_path_free(&search);
                return 64;
            }
            if (extensions == NULL) {
                extensions = malloc(sizeof *extensions * (size_t)argc);
                if (extensions == NULL) {
                    fprintf(stderr, "solid: out of memory\n");
                    sol_search_path_free(&search);
                    return 70;
                }
            }
            extensions[extension_count++] = argv[at] + 12;
            at++;
            continue;
        }
        if (strcmp(argv[at], "-I") != 0) break;
        if (at + 1 >= argc) {
            usage(stderr); free(extensions);
            sol_search_path_free(&search); return 64;
        }
        sol_search_path_add(&search, argv[at + 1]);
        at += 2;
    }
    sol_search_path_add_defaults(&search, argv[0]);

    if (at >= argc) {
        usage(stderr); free(extensions);
        sol_search_path_free(&search); return 64;
    }
    const char *path = argv[at++];

    SolChunk chunk;
    sol_chunk_init(&chunk);

    if (is_bytecode(path)) {
        SolSerResult result = sol_chunk_load(&chunk, path);
        if (result != SOL_SER_OK) {
            fprintf(stderr, "solid: cannot load '%s': %s\n", path,
                    sol_ser_message(result));
            sol_search_path_free(&search);
            return 65;
        }
    } else {
        char *source = sol_read_file(path);
        if (source == NULL) {
            fprintf(stderr, "solid: could not read '%s'\n", path);
            sol_search_path_free(&search);
            return 74;
        }
        bool compiled = sol_compile_file(source, path, &search, &chunk);
        free(source);
        if (!compiled) {
            sol_chunk_free(&chunk);
            sol_search_path_free(&search);
            return 65;
        }
    }

    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_arguments(&vm, argc - at, argv + at);

    /* Before the first line is reached, so that the program stops where it
       would have stopped rather than on an undefined name. */
    for (int i = 0; i < extension_count; i++) {
        char *why = NULL;
        if (!sol_extension_load(&vm, extensions[i], &why)) {
            fprintf(stderr, "solid: cannot load extension %s\n",
                    why != NULL ? why : extensions[i]);
            free(why);
            free(extensions);
            sol_vm_free(&vm);
            sol_chunk_free(&chunk);
            sol_search_path_free(&search);
            return 65;
        }
    }
    free(extensions);

    Solid solid;
    solid_init(&solid);
    vm.debug_hook = solid_stop;
    vm.debug_context = &solid;

    printf("solid " SOLUM_VERSION " -- `help` for commands, `quit` to leave\n");

    SolResult result = sol_vm_run(&vm, &chunk);
    int status = vm.exit_code;

    /* Leaving on purpose is not a failure of the program, whatever the VM was
       told to make it stop. */
    if (solid.quitting) status = 0;
    else if (result == SOL_EXIT) status = vm.exit_code;
    else if (result != SOL_OK) status = 70;
    else {
        printf("-- the program finished\n");
        status = 0;
    }

    solid_free(&solid);
    sol_vm_free(&vm);
    sol_chunk_free(&chunk);
    sol_search_path_free(&search);
    return status;
}
