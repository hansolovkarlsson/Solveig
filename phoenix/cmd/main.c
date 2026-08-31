/* phoenix -- the Phoenix compiler. A .phx in, Solveig source out.
 *
 * It does not link Solveig and does not read its headers. What it produces is
 * text, and `solas` is what turns text into a `.sob` -- so the two projects
 * meet at a file format and a command line, which is the whole of the coupling
 * and is meant to stay that way. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "phoenix/common.h"
#include "phoenix/diag.h"
#include "phoenix/emit.h"
#include "phoenix/expand.h"
#include "phoenix/reader.h"

#define NAME "phoenix"

static void version(void)
{
    printf("%s " PHOENIX_VERSION " (emits Solveig source; needs solas "
           PHOENIX_SOLVEIG_MINIMUM " or later to compile it)\n", NAME);
}

static void usage(FILE *out)
{
    fprintf(out,
        "usage: phoenix [options] <file.phx>\n"
        "\n"
        "Compiles a Phoenix module to Solveig source.\n"
        "\n"
        "  -o <file>    where to write it; the default is the source name with\n"
        "               .sol in place of .phx\n"
        "  --map        write the source map beside the output, as <output>.map\n"
        "  --tree       print the expanded tree and stop, writing nothing\n"
        "  --version    show the version and stop\n"
        "  --help, -h   show this and stop\n"
        "\n"
        "The generated file is an artefact. Compile it with solas and keep the\n"
        "map: it is what turns a position in the .sol back into the .phx line\n"
        "somebody actually wrote.\n");
}

/* "prog.phx" -> "prog.sol"; anything else just gains ".sol". */
static char *default_output_path(const char *source_path)
{
    size_t length = strlen(source_path);
    bool has_phx = length > 4 && strcmp(source_path + length - 4, ".phx") == 0;
    size_t base = has_phx ? length - 4 : length;

    char *out = phx_alloc(base + 5);
    memcpy(out, source_path, base);
    memcpy(out + base, ".sol", 5);
    return out;
}

static char *map_path_for(const char *output_path)
{
    size_t length = strlen(output_path);
    char *out = phx_alloc(length + 5);
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

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(stdout);
            return 0;
        }
        if (strcmp(argv[i], "--version") == 0) { version(); return 0; }
        if (strcmp(argv[i], "--map") == 0)  { want_map = true;  continue; }
        if (strcmp(argv[i], "--tree") == 0) { want_tree = true; continue; }
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

    PhxSource source;
    if (!phx_source_read(&source, path)) {
        fprintf(stderr, NAME ": cannot read %s\n", path);
        return 66;
    }

    PhxDiagnostics diag;
    phx_diag_init(&diag, &source, stderr);

    PhxDialect dialect;
    phx_dialect_init(&dialect);

    PhxProvenance provenance;
    phx_provenance_init(&provenance);

    PhxNode *module = phx_read(&source, &dialect, &diag);
    if (module != NULL &&
        !phx_expand(module, &source, &dialect, &diag, &provenance)) {
        phx_node_free(module);
        module = NULL;
    }

    if (module == NULL) {
        fprintf(stderr, NAME ": %s -- %d error%s\n",
                path, diag.errors, diag.errors == 1 ? "" : "s");
        /* After the last diagnostic, because a diagnostic walks it. */
        phx_provenance_free(&provenance);
        phx_dialect_free(&dialect);
        phx_source_free(&source);
        return 65;
    }

    if (want_tree) {
        phx_node_dump(module, stdout, 0);
        phx_node_free(module);
        phx_provenance_free(&provenance);
        phx_dialect_free(&dialect);
        phx_source_free(&source);
        return 0;
    }

    char *chosen = output != NULL ? NULL : default_output_path(path);
    const char *destination = output != NULL ? output : chosen;

    PhxEmitter emitter;
    phx_emitter_init(&emitter);
    phx_emit(&emitter, module);

    int status = 0;
    if (!phx_emit_write(&emitter, destination)) {
        fprintf(stderr, NAME ": cannot write %s\n", destination);
        status = 74;
    } else if (want_map) {
        char *map = map_path_for(destination);
        if (!phx_emit_map_write(&emitter, map, &source, destination)) {
            fprintf(stderr, NAME ": cannot write %s\n", map);
            status = 74;
        }
        free(map);
    }

    phx_emitter_free(&emitter);
    free(chosen);
    phx_node_free(module);
    phx_provenance_free(&provenance);
    phx_dialect_free(&dialect);
    phx_source_free(&source);
    return status;
}
