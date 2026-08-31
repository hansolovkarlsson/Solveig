/* test_use.c -- a dialect that lives in a file, and several of them meeting.
 *
 * On disk rather than in memory, because `@use` is about files: where one is
 * looked for, what happens when two are the same, and what a cycle does. A
 * fixture that faked the filesystem would be testing the fake. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "phoenix/emit.h"
#include "phoenix/expand.h"
#include "phoenix/reader.h"
#include "phoenix/unit.h"

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

    PhxUnit unit;
    phx_unit_init(&unit);

    FILE *sink = tmpfile();
    PhxDiagnostics diag;
    phx_diag_init(&diag, sink);

    PhxDialect dialect;
    phx_dialect_init(&dialect);

    PhxProvenance provenance;
    phx_provenance_init(&provenance);

    const PhxSource *source = phx_unit_read(&unit, path);
    PhxNode *module = NULL;
    if (source == NULL) {
        diag.errors++;
    } else {
        module = phx_read(source, &unit, &dialect, &diag);
        if (module != NULL &&
            !phx_expand(module, &unit, &dialect, &diag, &provenance)) {
            phx_node_free(module);
            module = NULL;
        }
    }
    *errors = diag.errors;
    *warnings = diag.warnings;

    char *out = NULL;
    if (module != NULL) {
        PhxEmitter emitter;
        phx_emitter_init(&emitter);
        phx_emit(&emitter, module);
        const char *body = strstr(emitter.text, "\n\n");
        out = phx_strndup(body + 2, strlen(body + 2));
        phx_emitter_free(&emitter);
        phx_node_free(module);
    }

    phx_provenance_free(&provenance);
    phx_dialect_free(&dialect);
    phx_unit_free(&unit);
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
    char template[] = "/tmp/phoenix-test-XXXXXX";
    if (mkdtemp(template) == NULL) { perror("mkdtemp"); return 1; }
    snprintf(directory, sizeof directory, "%s", template);

    /* A dialect file is directives and nothing else, and what it declares
       belongs to whoever uses it. */
    write_file("arith.phx", "@infix + 60 add.\n@infix * 70 mul.\n");
    write_file("p1.phx",
               "@language solveig.\n@use \"arith.phx\".\na := #1 + #2 * #3.\n");
    expect("a dialect in a file", "p1.phx",
           "a := #1:add(#2:mul(#3)).\n", 0);

    /* A dialect may use a dialect, and the whole chain is read before the
       first statement of the module is. */
    write_file("control.phx",
               "@use \"arith.phx\".\n"
               "@syntax unless(t, b) => t:not:ifTrue({ b }).\n");
    write_file("p2.phx",
               "@language solveig.\n@use \"control.phx\".\n"
               "unless(a > b, c:print).\n");
    write_file("arith.phx",
               "@infix + 60 add.\n@infix * 70 mul.\n@infix > 40 greaterThan.\n");
    expect("a dialect using a dialect", "p2.phx",
           "a:greaterThan(b):not:ifTrue({ c:print }).\n", 0);

    /* A diamond is harmless: both sides use arith, and arith is read once, so
       its declarations do not collide with themselves. */
    write_file("more.phx", "@use \"arith.phx\".\n@infix - 60 sub.\n");
    write_file("p3.phx",
               "@language solveig.\n@use \"control.phx\".\n@use \"more.phx\".\n"
               "a := #3 - #1 + #2.\n");
    expect("a diamond is read once", "p3.phx",
           "a := #3:sub(#1):add(#2).\n", 0);

    /* Two dialects claiming one spelling. Neither author knew about the other,
       so the later wins and the compiler says so -- Solveig's rule for two
       files claiming one global, applied to syntax. */
    write_file("other.phx", "@infix + 55 concat.\n");
    write_file("p4.phx",
               "@language solveig.\n@use \"arith.phx\".\n@use \"other.phx\".\n"
               "a := #1 + #2.\n");
    expect("two dialects collide", "p4.phx", "a := #1:concat(#2).\n", 1);

    /* The module's own declaration over an imported one is deliberate, local,
       and both lines are in the file being edited. Nothing to warn about. */
    write_file("p5.phx",
               "@language solveig.\n@use \"arith.phx\".\n@infix + 60 concat.\n"
               "a := #1 + #2.\n");
    expect("this module overriding a dialect", "p5.phx",
           "a := #1:concat(#2).\n", 0);

    /* The other order is almost certainly the @use wanting to be above the
       declaration, so it is worth saying. */
    write_file("p6.phx",
               "@language solveig.\n@infix + 60 concat.\n@use \"arith.phx\".\n"
               "a := #1 + #2.\n");
    expect("a dialect overriding this module", "p6.phx",
           "a := #1:add(#2).\n", 1);

    /* A file still being read is a file using itself. */
    write_file("x.phx", "@use \"y.phx\".\n");
    write_file("y.phx", "@use \"x.phx\".\n");
    write_file("p7.phx", "@language solveig.\n@use \"x.phx\".\na := #1.\n");
    expect_rejected("a cycle", "p7.phx");

    write_file("p8.phx", "@language solveig.\n@use \"nope.phx\".\na := #1.\n");
    expect_rejected("a dialect that is not there", "p8.phx");

    /* A dialect provides syntax; Solveig's own @include provides code. There is
       no third thing for a .phx to be. */
    write_file("code.phx", "@infix + 60 add.\nq := #1.\n");
    write_file("p9.phx", "@language solveig.\n@use \"code.phx\".\na := #1.\n");
    expect_rejected("a statement in a dialect file", "p9.phx");

    /* A form out of a dialect keeps its own binders out of the caller's way,
       and the generated name is fresh against every file -- including the one
       the template came from, which the module never mentions. */
    write_file("hold.phx", "@syntax hold(v) => { | t | t := v. t }:value.\n");
    write_file("p10.phx",
               "@language solveig.\n@use \"hold.phx\".\n"
               "t := #1.\na := hold(t).\n");
    expect("hygiene across a file boundary", "p10.phx",
           "t := #1.\n"
           "a := { | t__1 |\n"
           "    t__1 := t.\n"
           "    t__1 }:value.\n", 0);

    printf("%d checks, %d failed\n", checks, failures);

    const char *files[] = { "arith.phx", "control.phx", "more.phx", "other.phx",
                            "code.phx", "hold.phx", "x.phx", "y.phx",
                            "p1.phx", "p2.phx", "p3.phx", "p4.phx", "p5.phx",
                            "p6.phx", "p7.phx", "p8.phx", "p9.phx", "p10.phx" };
    for (size_t i = 0; i < sizeof files / sizeof *files; i++)
        remove_file(files[i]);
    rmdir(directory);

    return failures == 0 ? 0 : 1;
}
