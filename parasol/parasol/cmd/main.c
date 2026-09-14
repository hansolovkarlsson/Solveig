/* parasol -- the Parasol compiler. A .psol in, Solveig source out.
 *
 * It does not link Solveig and does not read its headers. What it produces is
 * text, and `solas` is what turns text into a `.sob` -- so the two projects
 * meet at a file format and a command line, which is the whole of the coupling
 * and is meant to stay that way. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
        "Compiles a Parasol module to Solveig source.\n"
        "\n"
        "  -o <file>    where to write it; the default is the source name with\n"
        "               .sol in place of .psol\n"
        "  -I <dir>     where a @use falls back to when the dialect file is not\n"
        "               beside the one using it; repeatable, first wins\n"
        "  --map        write the source map beside the output, as <output>.map\n"
        "  --tree       print the expanded tree and stop, writing nothing\n"
        "  --version    show the version and stop\n"
        "  --help, -h   show this and stop\n"
        "\n"
        "A @use is looked for beside the file using it first, then in each -I\n"
        "directory in order, then in PARASOL_PATH (colon-separated).\n"
        "\n"
        "The generated file is an artefact. Compile it with solas and keep the\n"
        "map: it is what turns a position in the .sol back into the .psol line\n"
        "somebody actually wrote.\n");
}

/* "prog.psol" -> "prog.sol"; anything else just gains ".sol". */
static char *default_output_path(const char *source_path)
{
    size_t length = strlen(source_path);
    bool has_psol = length > 5 && strcmp(source_path + length - 5, ".psol") == 0;
    size_t base = has_psol ? length - 5 : length;

    char *out = parasol_alloc(base + 5);
    memcpy(out, source_path, base);
    memcpy(out + base, ".sol", 5);
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

int main(int argc, char *argv[])
{
    const char *path = NULL;
    const char *output = NULL;
    bool want_map = false;
    bool want_tree = false;

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
        if (strcmp(argv[i], "-I") == 0) {
            if (++i >= argc) {
                fprintf(stderr, NAME ": -I needs a directory\n");
                return 64;
            }
            parasol_unit_add_directory(&unit, argv[i]);
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
        return 65;
    }

    if (want_tree) {
        parasol_node_dump(module, stdout, 0);
        parasol_node_free(module);
        parasol_provenance_free(&provenance);
        parasol_dialect_free(&dialect);
        parasol_unit_free(&unit);
        return 0;
    }

    char *chosen = output != NULL ? NULL : default_output_path(path);
    const char *destination = output != NULL ? output : chosen;

    ParasolEmitter emitter;
    parasol_emitter_init(&emitter);
    parasol_emit(&emitter, module);

    int status = 0;
    if (!parasol_emit_write(&emitter, destination)) {
        fprintf(stderr, NAME ": cannot write %s\n", destination);
        status = 74;
    } else if (want_map) {
        char *map = map_path_for(destination);
        if (!parasol_emit_map_write(&emitter, map, source, destination)) {
            fprintf(stderr, NAME ": cannot write %s\n", map);
            status = 74;
        }
        free(map);
    }

    parasol_emitter_free(&emitter);
    free(chosen);
    parasol_node_free(module);
    parasol_provenance_free(&provenance);
    parasol_dialect_free(&dialect);
    parasol_unit_free(&unit);
    return status;
}
