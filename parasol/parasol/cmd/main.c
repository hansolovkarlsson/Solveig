/* parasol -- the Parasol compiler. A .psol in, Solveig source out.
 *
 * It does not link Solveig and does not read its headers. What it produces is
 * text, and `solas` is what turns text into a `.sob` -- so the two projects
 * meet at a file format and a command line, which is the whole of the coupling
 * and is meant to stay that way.
 *
 * `--sob` does not move that line. It runs the command line: the `.sol` is
 * written as before, and then `solas` is run on it, the one beside this binary
 * or else the one on PATH, with `-o`, every `-I` and `--dump` handed through
 * and `--expr` never. What comes back is solas's own status and solas's own
 * diagnostics, naming lines in the `.sol`, which the map beside it turns into
 * lines in the `.psol`. The alternative -- linking libsol.a and calling
 * `sol_compile_options` on the emitted text, forty lines -- was scoped on
 * 2026-09-14 and put aside, because it would have made the Makefile's first
 * sentence false. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "parasol/common.h"
#include "parasol/diag.h"
#include "parasol/emit.h"
#include "parasol/expand.h"
#include "parasol/reader.h"
#include "parasol/unit.h"

#define NAME "parasol"

static void version(void)
{
    printf("%s " PARASOL_VERSION " (emits Solveig source; needs solas "
           PARASOL_SOLVEIG_MINIMUM " or later to compile it)\n", NAME);
}

static void usage(FILE *out)
{
    fprintf(out,
        "usage: parasol [options] <file.psol>\n"
        "\n"
        "Compiles a Parasol module to Solveig source, and with --sob on to\n"
        "bytecode.\n"
        "\n"
        "  -o <file>    where to write it; the default is the source name with\n"
        "               .sol in place of .psol, or .sob with --sob\n"
        "  -I <dir>     where a @use falls back to when the dialect file is not\n"
        "               beside the one using it; repeatable, first wins. With\n"
        "               --sob, handed to solas as well, for @include\n"
        "  --sob        run solas on the generated source, the one beside this\n"
        "               binary or else the one on PATH; the .sol is kept beside\n"
        "               the .sob, and @expr is never turned on\n"
        "  --dump       with --sob, have solas disassemble the chunk as well\n"
        "  --map        write the source map beside the output, as <output>.map\n"
        "  --tree       print the expanded tree and stop, writing nothing\n"
        "  --version    show the version and stop\n"
        "  --help, -h   show this and stop\n"
        "\n"
        "A @use is looked for beside the file using it first, then in each -I\n"
        "directory in order, then in PARASOL_PATH (colon-separated).\n"
        "\n"
        "The generated file is an artefact. Compile it with solas, or with\n"
        "--sob, and keep the map: it is what turns a position in the .sol back\n"
        "into the .psol line somebody actually wrote.\n");
}

/* "prog.psol" -> "prog.sol" for `from` ".psol" and `to` ".sol"; a name that
   does not end in `from` just gains `to`. Both carry their dot. */
static char *replace_extension(const char *source_path, const char *from,
                               const char *to)
{
    size_t length = strlen(source_path);
    size_t from_length = strlen(from);
    bool has_from = length > from_length &&
                    strcmp(source_path + length - from_length, from) == 0;
    size_t base = has_from ? length - from_length : length;
    size_t to_length = strlen(to);

    char *out = parasol_alloc(base + to_length + 1);
    memcpy(out, source_path, base);
    memcpy(out + base, to, to_length + 1);
    return out;
}

static char *map_path_for(const char *output_path)
{
    size_t length = strlen(output_path);
    char *out = parasol_alloc(length + 5);
    memcpy(out, output_path, length);
    memcpy(out + length, ".map", 5);
    return out;
}

/* The solas to run: the one beside this binary when argv[0] says where that
 * is and one is there, otherwise the one PATH finds. `bin/` holds all five
 * since 2026-09-13, so the first is the case that happens; the second is a
 * `parasol` reached off PATH, whose `argv[0]` names no directory and whose
 * `solas` is, on any install this repository makes, on the same PATH.
 *
 * Answers a string `execvp` does the right thing with: a name with a slash is
 * run as it stands, a bare name is looked up. */
static char *find_solas(const char *argv0)
{
    const char *slash = strrchr(argv0, '/');
    if (slash != NULL) {
        size_t directory = (size_t)(slash - argv0) + 1;
        char *beside = parasol_alloc(directory + 6);
        memcpy(beside, argv0, directory);
        memcpy(beside + directory, "solas", 6);
        if (access(beside, X_OK) == 0) return beside;
        free(beside);
    }
    return parasol_strndup("solas", 5);
}

/* Runs solas on `sol`, writing `sob`, and answers the status to leave with:
 * solas's own when it ran, 127 when it could not be run, 70 when it died.
 * Nothing is captured -- solas's diagnostics go where this program's go, and
 * name the `.sol`, which is what the map is for. */
static int run_solas(const char *argv0, const char *sol, const char *sob,
                     char **includes, int include_count, bool dump)
{
    char *solas = find_solas(argv0);

    /* solas, sol, -o, sob, (-I, dir)*, --dump, NULL */
    int count = 4 + 2 * include_count + (dump ? 1 : 0) + 1;
    char **argv = parasol_alloc((size_t)count * sizeof *argv);
    int n = 0;
    argv[n++] = solas;
    argv[n++] = (char *)sol;
    argv[n++] = "-o";
    argv[n++] = (char *)sob;
    for (int i = 0; i < include_count; i++) {
        argv[n++] = "-I";
        argv[n++] = includes[i];
    }
    if (dump) argv[n++] = "--dump";
    argv[n] = NULL;

    fflush(NULL);
    pid_t child = fork();
    if (child < 0) {
        perror(NAME ": fork");
        free(argv);
        free(solas);
        return 70;
    }
    if (child == 0) {
        execvp(solas, argv);
        fprintf(stderr, NAME ": cannot run %s: %s\n", solas, strerror(errno));
        _exit(127);
    }

    int status;
    if (waitpid(child, &status, 0) < 0) {
        perror(NAME ": waitpid");
        status = -1;
    }
    free(argv);
    free(solas);

    if (status != -1 && WIFEXITED(status)) return WEXITSTATUS(status);
    fprintf(stderr, NAME ": solas did not exit normally\n");
    return 70;
}

int main(int argc, char *argv[])
{
    const char *path = NULL;
    const char *output = NULL;
    bool want_map = false;
    bool want_tree = false;
    bool want_sob = false;
    bool want_dump = false;

    /* The -I directories, kept apart from the unit's list because the unit
       also takes PARASOL_PATH, which is not solas's to search. */
    char **includes = NULL;
    int include_count = 0;

    ParasolUnit unit;
    parasol_unit_init(&unit);

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(stdout);
            return 0;
        }
        if (strcmp(argv[i], "--version") == 0) { version(); return 0; }
        if (strcmp(argv[i], "--map") == 0)  { want_map = true;  continue; }
        if (strcmp(argv[i], "--tree") == 0) { want_tree = true; continue; }
        if (strcmp(argv[i], "--sob") == 0)  { want_sob = true;  continue; }
        if (strcmp(argv[i], "--dump") == 0) { want_dump = true; continue; }
        if (strcmp(argv[i], "-I") == 0) {
            if (++i >= argc) {
                fprintf(stderr, NAME ": -I needs a directory\n");
                return 64;
            }
            parasol_unit_add_directory(&unit, argv[i]);
            includes = parasol_realloc(includes,
                                       (size_t)(include_count + 1) * sizeof *includes);
            includes[include_count++] = argv[i];
            continue;
        }
        if (strcmp(argv[i], "-o") == 0) {
            if (++i >= argc) {
                fprintf(stderr, NAME ": -o needs a file name\n");
                return 64;
            }
            output = argv[i];
            continue;
        }
        if (argv[i][0] == '-' && argv[i][1] != '\0') {
            fprintf(stderr, NAME ": unknown option '%s'\n", argv[i]);
            usage(stderr);
            return 64;
        }
        if (path != NULL) {
            fprintf(stderr, NAME ": one file at a time\n");
            return 64;
        }
        path = argv[i];
    }

    if (path == NULL) { usage(stderr); return 64; }
    if (want_dump && !want_sob) {
        fprintf(stderr, NAME ": --dump is solas's, and needs --sob\n");
        return 64;
    }

    /* After the flags, so that -I beats the environment. */
    parasol_unit_add_environment(&unit);

    const ParasolSource *source = parasol_unit_read(&unit, path);
    if (source == NULL) {
        fprintf(stderr, NAME ": cannot read %s\n", path);
        parasol_unit_free(&unit);
        return 66;
    }

    ParasolDiagnostics diag;
    parasol_diag_init(&diag, stderr);

    ParasolDialect dialect;
    parasol_dialect_init(&dialect);

    ParasolProvenance provenance;
    parasol_provenance_init(&provenance);

    ParasolNode *module = parasol_read(source, &unit, &dialect, &diag);
    if (module != NULL &&
        !parasol_expand(module, &unit, &dialect, &diag, &provenance)) {
        parasol_node_free(module);
        module = NULL;
    }

    if (module == NULL) {
        fprintf(stderr, NAME ": %s -- %d error%s\n",
                path, diag.errors, diag.errors == 1 ? "" : "s");
        /* After the last diagnostic, because a diagnostic walks it. */
        parasol_provenance_free(&provenance);
        parasol_dialect_free(&dialect);
        parasol_unit_free(&unit);
        free(includes);
        return 65;
    }

    if (want_tree) {
        parasol_node_dump(module, stdout, 0);
        parasol_node_free(module);
        parasol_provenance_free(&provenance);
        parasol_dialect_free(&dialect);
        parasol_unit_free(&unit);
        free(includes);
        return 0;
    }

    /* Where the two files go. Without --sob, `-o` names the .sol. With it,
       `-o` names the .sob and the .sol goes beside it with the extension
       swapped: the pair is the output, and the map, which points into the
       .sol, is beside the .sol. */
    char *sob = NULL;
    char *sol = NULL;
    if (want_sob) {
        sob = output != NULL ? parasol_strndup(output, strlen(output))
                             : replace_extension(path, ".psol", ".sob");
        sol = replace_extension(sob, ".sob", ".sol");
    } else {
        sol = output != NULL ? parasol_strndup(output, strlen(output))
                             : replace_extension(path, ".psol", ".sol");
    }

    ParasolEmitter emitter;
    parasol_emitter_init(&emitter);
    parasol_emit(&emitter, module);

    int status = 0;
    if (!parasol_emit_write(&emitter, sol)) {
        fprintf(stderr, NAME ": cannot write %s\n", sol);
        status = 74;
    } else if (want_map) {
        char *map = map_path_for(sol);
        if (!parasol_emit_map_write(&emitter, map, source, sol)) {
            fprintf(stderr, NAME ": cannot write %s\n", map);
            status = 74;
        }
        free(map);
    }

    if (status == 0 && want_sob) {
        status = run_solas(argv[0], sol, sob, includes, include_count, want_dump);
    }

    parasol_emitter_free(&emitter);
    free(sol);
    free(sob);
    free(includes);
    parasol_node_free(module);
    parasol_provenance_free(&provenance);
    parasol_dialect_free(&dialect);
    parasol_unit_free(&unit);
    return status;
}
