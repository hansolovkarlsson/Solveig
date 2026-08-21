/* solis -- the interactive Solum.
 *
 * Reads until the input could compile, then compiles and runs it. What decides
 * "could compile" is in solis/src/input.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solis/input.h"
#include "solis/line.h"
#include "solum/common.h"
#include "solum/serialize.h"
#include "solum/vm.h"

/* Each submission is its own chunk, handed to the collector rather than freed
   here: a block defined now outlives the input it was written in, and a slot
   holds only a pointer to the code the chunk owns. The chunk is reclaimed once
   nothing refers to it, which for most input is immediately.

   The temporary root covers the window before the first frame refers to it, so
   a collection triggered while compiling could not sweep it. */
static SolResult submit(SolVM *vm, const SolSearchPath *search, const char *source)
{
    SolResult result = SOL_COMPILE_ERROR;
    SolCode *code = sol_code_new(vm);
    sol_gc_push_temp(vm, &code->gc);

    /* NULL for the path: the prompt is not a file, so a relative include
       resolves against the working directory -- and then against the search
       path, so `@include "control.sol"` reaches the library from here too. */
    if (sol_compile_file(source, NULL, search, &code->chunk)) {
        result = sol_vm_run(vm, &code->chunk);
    }
    sol_gc_pop_temp(vm);

    /* They share the VM, so globals and methods bound by one submission are
       there for the next. */
    return result;
}

/* Answers the status to leave with. `system:exit` works at the prompt for the
   same reason it works in a program: it is a message, and the prompt runs the
   same machine. */
static int repl(SolVM *vm, const SolSearchPath *search)
{
    int status = 0;
    SolisInput input = { NULL, 0, 0 };
    SolisScan  state;
    size_t     scanned = 0;

    /* Editing and history when there is a terminal to do them on; a pipe or a
       file reads as it always did, which is what keeps `solis < script` and the
       tests working. */
    SolisHistory history = { NULL, 0, 0 };
    bool editing = sol_line_editing_available();

    /* Kept between sessions, and only when there is a session to keep it for:
       reading from a pipe has no history to write and no prompt to recall it
       at. `SOLIS_HISTORY_MAX` is what the file is trimmed to on the way out. */
    char history_file[4096];
    const char *history_path = editing ? sol_history_path(history_file,
                                                          sizeof history_file)
                                       : NULL;
    if (history_path != NULL) sol_history_load(&history, history_path);

    sol_scan_reset(&state);
    printf("solis " SOLUM_VERSION " -- ctrl-d to exit\n");

    for (;;) {
        const char *prompt = input.length == 0 ? "> " : ".. ";
        bool read;

        if (editing) {
            read = sol_line_read(&input, &history, prompt);
        } else {
            printf("%s", prompt);
            fflush(stdout);
            read = sol_input_read_line(&input, stdin);
        }

        if (!read) {
            /* End of input. Anything half-typed is still compiled rather than
               dropped, so input that stops mid-expression says why. */
            if (input.length > 0 && submit(vm, search, input.text) == SOL_EXIT) {
                status = vm->exit_code;
            }
            printf("\n");
            break;
        }

        sol_scan(&state, input.text + scanned);
        scanned = input.length;
        if (sol_scan_wants_more(&state)) continue;

        if (submit(vm, search, input.text) == SOL_EXIT) {
            status = vm->exit_code;
            break;
        }
        sol_input_clear(&input);
        sol_scan_reset(&state);
        scanned = 0;
    }

    sol_input_free(&input);
    if (history_path != NULL) {
        sol_history_save(&history, history_path, SOLIS_HISTORY_MAX);
    }
    sol_history_free(&history);
    return status;
}

/* Is this a compiled chunk rather than source? Asked of the bytes rather than
   the name, so a script with no extension at all -- which is what a `#!` line
   is for -- is read as what it is. */
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

/* Runs a file and answers the status to leave with: a `.sob` is loaded, and
   anything else is compiled first. Either way what runs is one program rather
   than a prompt, so `system:arguments` is what came after the file. */
static int run_file(const char *path, const SolSearchPath *search,
                    int argc, char **args)
{
    SolChunk chunk;
    bool loaded = false;

    if (is_bytecode(path)) {
        SolSerResult result = sol_chunk_load(&chunk, path);
        if (result != SOL_SER_OK) {
            fprintf(stderr, "solis: cannot load '%s': %s\n",
                    path, sol_ser_message(result));
            return 65;
        }
        loaded = true;
    } else {
        char *source = sol_read_file(path);
        if (source == NULL) {
            fprintf(stderr, "solis: could not read '%s'\n", path);
            return 74;
        }
        sol_chunk_init(&chunk);
        loaded = sol_compile_file(source, path, search, &chunk);
        free(source);
        if (!loaded) {
            sol_chunk_free(&chunk);
            return 65;
        }
    }

    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_arguments(&vm, argc, args);

    SolResult result = sol_vm_run(&vm, &chunk);
    int status = vm.exit_code;              /* read before the VM goes away */

    sol_vm_free(&vm);
    sol_chunk_free(&chunk);

    if (result == SOL_EXIT) return status;
    return result == SOL_OK ? 0 : 70;
}

#define NAME "solis"

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
        "usage: solis [options] [file [arguments...]]\n"
        "\n"
        "With no file, reads from the prompt. A file is Solum source, or bytecode\n"
        "if it begins with \"SOLB\" -- decided by the bytes rather than the name,\n"
        "so a script with a #! line and no extension runs as what it is.\n"
        "\n"
        "  -I <dir>     where an @include falls back to; repeatable\n"
        "  --version    show the version and the .sob format, and stop\n"
        "  --help, -h   show this and stop\n"
        "\n"
        "Everything after the file belongs to the program, so a script may take a\n"
        "-I or a --help of its own. Which is why these options have to come first.\n"
        "\n"
        "A file made executable runs directly with a first line of:\n"
        "    #!/usr/bin/env solis\n");
}

int main(int argc, char *argv[])
{
    SolSearchPath search;
    sol_search_path_init(&search);

    int at = 1;
    while (at < argc) {
        if (strcmp(argv[at], "--help") == 0 || strcmp(argv[at], "-h") == 0) {
            usage(stdout);
            sol_search_path_free(&search);
            return 0;
        }
        if (strcmp(argv[at], "--version") == 0) {
            version();
            sol_search_path_free(&search);
            return 0;
        }
        if (strcmp(argv[at], "-I") != 0) break;
        if (at + 1 >= argc) { usage(stderr); sol_search_path_free(&search); return 64; }
        sol_search_path_add(&search, argv[at + 1]);
        at += 2;
    }
    sol_search_path_add_defaults(&search, argv[0]);

    /* Everything after the file belongs to the program, so a script may take a
       `-I` of its own without this one intercepting it -- which is why the
       flags have to come first. */
    if (at < argc) {
        const char *path = argv[at++];
        int status = run_file(path, &search, argc - at, argv + at);
        sol_search_path_free(&search);
        return status;
    }

    SolVM vm;
    sol_vm_init(&vm);
    int status = repl(&vm, &search);
    sol_vm_free(&vm);
    sol_search_path_free(&search);
    return status;
}
