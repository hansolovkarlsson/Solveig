/* test_map.c -- that a position in the generated file names the position in the
 * .phx that caused it.
 *
 * This is the test the whole design leans on. A compiler whose syntax arrives
 * with the file has one characteristic failure -- the programmer writes one
 * thing, is shown an error about another, and cannot get from the second back
 * to the first -- and the map is the only thing standing in front of it. So the
 * map is checked here rather than assumed to be correct because it was written
 * down. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "phoenix/emit.h"
#include "phoenix/reader.h"

static int failures = 0;
static int checks = 0;

static PhxSource source;
static PhxEmitter emitter;

/* That the generated position `line:column` came from the source text `want` --
   compared by looking at the source at the offset the map answers, which is the
   question somebody actually asks of it. */
static void expect_from(const char *label, int line, int column,
                        const char *want)
{
    checks++;
    const PhxMapping *mapping = phx_emit_lookup(&emitter, line, column);
    if (mapping == NULL) {
        printf("  FAIL %s: %d:%d maps to nothing\n", label, line, column);
        failures++;
        return;
    }
    const char *at = source.text + mapping->offset;
    if (strncmp(at, want, strlen(want)) != 0) {
        int source_line, source_column;
        phx_source_position(&source, mapping->offset,
                            &source_line, &source_column);
        printf("  FAIL %s: generated %d:%d maps to %d:%d, which is \"%.12s\", "
               "wanted \"%s\"\n",
               label, line, column, source_line, source_column, at, want);
        failures++;
    }
}

int main(void)
{
    /*        1234567890123456789012345 */
    const char *text =
        "@language solveig.\n"          /* line 1 */
        "@infix + 60 add.\n"            /* line 2 */
        "@infix * 70 mul.\n"            /* line 3 */
        "\n"
        "total := #2 + #3 * #4.\n"      /* line 5 */
        "total:print.\n";               /* line 6 */

    /* Which generates, after the two-line banner:
     *
     *   3 | total := #2:add(#3:mul(#4)).
     *   4 | total:print.
     *
     * The interesting part is that `#3` sits at generated column 17 and at
     * source column 16, and nothing about either number is derivable from the
     * other: the operators moved. */

    source.path = "<test>";
    source.text = phx_strndup(text, strlen(text));
    source.length = strlen(text);

    FILE *sink = tmpfile();
    PhxDiagnostics diag;
    phx_diag_init(&diag, &source, sink);

    PhxDialect dialect;
    phx_dialect_init(&dialect);

    PhxNode *module = phx_read(&source, &dialect, &diag);
    if (module == NULL) {
        printf("  FAIL: the fixture did not compile\n");
        return 1;
    }

    phx_emitter_init(&emitter);
    phx_emit(&emitter, module);

    expect_from("the statement",        3,  1, "total := #2");
    expect_from("the first operand",    3, 10, "#2");
    expect_from("the second operand",   3, 17, "#3");
    expect_from("the third operand",    3, 24, "#4");
    expect_from("the second statement", 4,  1, "total:print");

    /* A position inside a token maps to that token rather than to the next one,
       which is what makes a column somebody reports off a stack trace usable
       rather than nearly usable. */
    expect_from("inside a token",       3, 18, "#3");

    printf("%d checks, %d failed\n", checks, failures);

    phx_emitter_free(&emitter);
    phx_node_free(module);
    phx_dialect_free(&dialect);
    phx_source_free(&source);
    fclose(sink);
    return failures == 0 ? 0 : 1;
}
