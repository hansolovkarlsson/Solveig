/* test_use.c -- a dialect that lives in a file, and several of them meeting.
 *
 * On disk rather than in memory, because `@use` is about files: where one is
 * looked for, what happens when two are the same, and what a cycle does. A
 * fixture that faked the filesystem would be testing the fake. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "proto/emit.h"
#include "proto/expand.h"
#include "proto/reader.h"
#include "proto/unit.h"

static int failures = 0;
static int checks = 0;
static char directory[256];

static void write_file(const char *name, const char *text)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s", directory, name);
    FILE *file = fopen(path, "wb");
    if (file == NULL) { perror(path); exit(1); }
    fputs(text, file);
    fclose(file);
}

static void remove_file(const char *name)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s", directory, name);
    unlink(path);
}

/* Compiles `name` out of the temporary directory. */
static char *compile(const char *name, int *errors, int *warnings)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s", directory, name);

    ProtoUnit unit;
    proto_unit_init(&unit);

    FILE *sink = tmpfile();
    ProtoDiagnostics diag;
    proto_diag_init(&diag, sink);

    ProtoDialect dialect;
    proto_dialect_init(&dialect);

    ProtoProvenance provenance;
    proto_provenance_init(&provenance);

    const ProtoSource *source = proto_unit_read(&unit, path);
    ProtoNode *module = NULL;
    if (source == NULL) {
        diag.errors++;
    } else {
        module = proto_read(source, &unit, &dialect, &diag);
        if (module != NULL &&
            !proto_expand(module, &unit, &dialect, &diag, &provenance)) {
            proto_node_free(module);
            module = NULL;
        }
    }
    *errors = diag.errors;
    *warnings = diag.warnings;

    char *out = NULL;
    if (module != NULL) {
        ProtoEmitter emitter;
        proto_emitter_init(&emitter);
        proto_emit(&emitter, module);
        const char *body = strstr(emitter.text, "\n\n");
        out = proto_strndup(body + 2, strlen(body + 2));
        proto_emitter_free(&emitter);
        proto_node_free(module);
    }

    proto_provenance_free(&provenance);
    proto_dialect_free(&dialect);
    proto_unit_free(&unit);
    fclose(sink);
    return out;
}

static void expect(const char *label, const char *name,
                   const char *want, int want_warnings)
{
    checks++;
    int errors = 0, warnings = 0;
    char *got = compile(name, &errors, &warnings);

    if (got == NULL) {
        printf("  FAIL %s: did not compile (%d error%s)\n",
               label, errors, errors == 1 ? "" : "s");
        failures++;
        return;
    }
    if (strcmp(got, want) != 0) {
        printf("  FAIL %s\n    want: %s    got:  %s", label, want, got);
        failures++;
    } else if (warnings != want_warnings) {
        printf("  FAIL %s: wanted %d warning%s, got %d\n",
               label, want_warnings, want_warnings == 1 ? "" : "s", warnings);
        failures++;
    }
    free(got);
}

static void expect_rejected(const char *label, const char *name)
{
    checks++;
    int errors = 0, warnings = 0;
    char *got = compile(name, &errors, &warnings);
    if (got != NULL) {
        printf("  FAIL %s: compiled, and should not have\n", label);
        failures++;
        free(got);
        return;
    }
    if (errors < 1) {
        printf("  FAIL %s: rejected without saying why\n", label);
        failures++;
    }
}

int main(void)
{
    char template[] = "/tmp/proto-test-XXXXXX";
    if (mkdtemp(template) == NULL) { perror("mkdtemp"); return 1; }
    snprintf(directory, sizeof directory, "%s", template);

    /* A dialect file is directives and nothing else, and what it declares
       belongs to whoever uses it. */
    write_file("arith.pro", "@infix + 60 add.\n@infix * 70 mul.\n");
    write_file("p1.pro",
               "@use \"arith.pro\".\na := #1 + #2 * #3.\n");
    expect("a dialect in a file", "p1.pro",
           "a := #1:add(#2:mul(#3)).\n", 0);

    /* A dialect may use a dialect, and the whole chain is read before the
       first statement of the module is. */
    write_file("control.pro",
               "@use \"arith.pro\".\n"
               "@syntax unless(t, b) => t:not:ifTrue({ b }).\n");
    write_file("p2.pro",
               "@use \"control.pro\".\n"
               "unless(a > b, c:print).\n");
    write_file("arith.pro",
               "@infix + 60 add.\n@infix * 70 mul.\n@infix > 40 greaterThan.\n");
    expect("a dialect using a dialect", "p2.pro",
           "a:greaterThan(b):not:ifTrue({ c:print }).\n", 0);

    /* A diamond is harmless: both sides use arith, and arith is read once, so
       its declarations do not collide with themselves. */
    write_file("more.pro", "@use \"arith.pro\".\n@infix - 60 sub.\n");
    write_file("p3.pro",
               "@use \"control.pro\".\n@use \"more.pro\".\n"
               "a := #3 - #1 + #2.\n");
    expect("a diamond is read once", "p3.pro",
           "a := #3:sub(#1):add(#2).\n", 0);

    /* Two dialects claiming one spelling. Neither author knew about the other,
       so the later wins and the compiler says so -- Solveig's rule for two
       files claiming one global, applied to syntax. */
    write_file("other.pro", "@infix + 55 concat.\n");
    write_file("p4.pro",
               "@use \"arith.pro\".\n@use \"other.pro\".\n"
               "a := #1 + #2.\n");
    expect("two dialects collide", "p4.pro", "a := #1:concat(#2).\n", 1);

    /* The module's own declaration over an imported one is deliberate, local,
       and both lines are in the file being edited. Nothing to warn about. */
    write_file("p5.pro",
               "@use \"arith.pro\".\n@infix + 60 concat.\n"
               "a := #1 + #2.\n");
    expect("this module overriding a dialect", "p5.pro",
           "a := #1:concat(#2).\n", 0);

    /* The other order is almost certainly the @use wanting to be above the
       declaration, so it is worth saying. */
    write_file("p6.pro",
               "@infix + 60 concat.\n@use \"arith.pro\".\n"
               "a := #1 + #2.\n");
    expect("a dialect overriding this module", "p6.pro",
           "a := #1:add(#2).\n", 1);

    /* A file still being read is a file using itself. */
    write_file("x.pro", "@use \"y.pro\".\n");
    write_file("y.pro", "@use \"x.pro\".\n");
    write_file("p7.pro", "@use \"x.pro\".\na := #1.\n");
    expect_rejected("a cycle", "p7.pro");

    write_file("p8.pro", "@use \"nope.pro\".\na := #1.\n");
    expect_rejected("a dialect that is not there", "p8.pro");

    /* A dialect provides syntax; Solveig's own @include provides code. There is
       no third thing for a .pro to be. */
    write_file("code.pro", "@infix + 60 add.\nq := #1.\n");
    write_file("p9.pro", "@use \"code.pro\".\na := #1.\n");
    expect_rejected("a statement in a dialect file", "p9.pro");

    /* A form out of a dialect keeps its own binders out of the caller's way,
       and the generated name is fresh against every file -- including the one
       the template came from, which the module never mentions. */
    write_file("hold.pro", "@syntax hold(v) => { | t | t := v. t }:value.\n");
    write_file("p10.pro",
               "@use \"hold.pro\".\n"
               "t := #1.\na := hold(t).\n");
    expect("hygiene across a file boundary", "p10.pro",
           "t := #1.\n"
           "a := { | t__1 |\n"
           "    t__1 := t.\n"
           "    t__1 }:value.\n", 0);

    printf("%d checks, %d failed\n", checks, failures);

    const char *files[] = { "arith.pro", "control.pro", "more.pro", "other.pro",
                            "code.pro", "hold.pro", "x.pro", "y.pro",
                            "p1.pro", "p2.pro", "p3.pro", "p4.pro", "p5.pro",
                            "p6.pro", "p7.pro", "p8.pro", "p9.pro", "p10.pro" };
    for (size_t i = 0; i < sizeof files / sizeof *files; i++)
        remove_file(files[i]);
    rmdir(directory);

    return failures == 0 ? 0 : 1;
}
