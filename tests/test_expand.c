/* test_expand.c -- declared forms: what they stand for, and what they cannot
 * reach.
 *
 * The hygiene checks are the ones worth reading. Each is written so that it
 * fails if the renaming is removed -- a template that binds `t` is handed a
 * caller's `t`, and the assertion is on the value that comes out rather than on
 * the name that goes in. A test that only checked for `t__1` would pass for a
 * compiler that renamed correctly and for one that renamed everything. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "phoenix/emit.h"
#include "phoenix/expand.h"
#include "phoenix/reader.h"
#include "phoenix/unit.h"

static int failures = 0;
static int checks = 0;

static char *compile(const char *text, int *errors)
{
    PhxUnit unit;
    phx_unit_init(&unit);

    const PhxSource *source = phx_unit_adopt(&unit, "<test>", text);

    FILE *sink = tmpfile();
    PhxDiagnostics diag;
    phx_diag_init(&diag, sink);

    PhxDialect dialect;
    phx_dialect_init(&dialect);

    PhxProvenance provenance;
    phx_provenance_init(&provenance);

    PhxNode *module = phx_read(source, &unit, &dialect, &diag);
    if (module != NULL &&
        !phx_expand(module, &unit, &dialect, &diag, &provenance)) {
        phx_node_free(module);
        module = NULL;
    }
    *errors = diag.errors;

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

static void expect(const char *label, const char *text, const char *want)
{
    checks++;
    int errors = 0;
    char *got = compile(text, &errors);
    if (got == NULL) {
        printf("  FAIL %s: did not compile (%d error%s)\n",
               label, errors, errors == 1 ? "" : "s");
        failures++;
        return;
    }
    if (strcmp(got, want) != 0) {
        printf("  FAIL %s\n    want: %s    got:  %s", label, want, got);
        failures++;
    }
    free(got);
}

static void expect_rejected(const char *label, const char *text)
{
    checks++;
    int errors = 0;
    char *got = compile(text, &errors);
    if (got != NULL) {
        printf("  FAIL %s: compiled, and should not have\n    got:  %s",
               label, got);
        failures++;
        free(got);
        return;
    }
    if (errors < 1) {
        printf("  FAIL %s: rejected without saying why\n", label);
        failures++;
    }
}

#define LANG "@language solveig.\n"

int main(void)
{
    /* Substitution, and the thing a form can do that a method cannot: the
       argument is not evaluated before it arrives, so the template may put it
       inside a block the caller never wrote. */
    expect("substitution", LANG
           "@syntax twice(x) => x:add(x).\n"
           "a := twice(#2).\n",
           "a := #2:add(#2).\n");
    expect("an argument reaching inside a block", LANG
           "@syntax unless(t, b) => t:not:ifTrue({ b }).\n"
           "unless(a, b:print).\n",
           "a:not:ifTrue({ b:print }).\n");
    expect("no arguments", LANG
           "@syntax here => system:clock.\n"
           "a := here.\n",
           "a := system:clock.\n");

    /* A form may use the forms above it, and expansion therefore terminates:
       the highest index used strictly falls. */
    expect("a form using a form", LANG
           "@syntax unless(t, b) => t:not:ifTrue({ b }).\n"
           "@syntax whenEmpty(c, b) => unless(c:isEmpty:not, b).\n"
           "whenEmpty(xs, y:print).\n",
           "xs:isEmpty:not:not:ifTrue({ y:print }).\n");

    /* Hygiene. The template binds `t`; the caller passes `t`. Asserted on the
       generated code, and the example is run for real in examples/forms.phx. */
    expect("a template binder cannot capture an argument", LANG
           "@syntax hold(v) => { | t | t := v. t }:value.\n"
           "t := #1.\n"
           "a := hold(t).\n",
           "t := #1.\n"
           "a := { | t__1 |\n"
           "    t__1 := t.\n"
           "    t__1 }:value.\n");

    /* A generated name avoids every identifier in the module, so a caller who
       already has a `t__1` is not quietly broken by one. */
    expect("a fresh name is fresh against the whole module", LANG
           "@syntax hold(v) => { | t | t := v. t }:value.\n"
           "t__1 := #9.\n"
           "a := hold(t__1).\n",
           "t__1 := #9.\n"
           "a := { | t__2 |\n"
           "    t__2 := t__1.\n"
           "    t__2 }:value.\n");

    /* Two expansions of one form do not share a name either. */
    expect("two expansions do not collide", LANG
           "@syntax hold(v) => { | t | t }:value.\n"
           "a := hold(#1). b := hold(#2).\n",
           "a := { | t__1 | t__1 }:value.\n"
           "b := { | t__2 | t__2 }:value.\n");

    /* A name is only a form after it has been declared one, inside the header
       as much as after it. This is the whole of why expansion terminates: `g`
       below cannot reach `f`, so no form can reach itself, however the
       declarations are arranged. */
    expect("a template cannot see a form declared after it", LANG
           "@syntax g(x) => f(x).\n"
           "@syntax f(y) => y:print.\n"
           "a := g(#1).\n",
           "a := #1:f.\n");

    /* What the reader can catch, it catches at the use, with the declaration
       pointed at. */
    expect_rejected("too few arguments", LANG
                    "@syntax pair(a, b) => [a, b].\n" "c := pair(#1).\n");
    expect_rejected("too many arguments", LANG
                    "@syntax pair(a, b) => [a, b].\n" "c := pair(#1, #2, #3).\n");
    expect_rejected("arguments to a form that takes none", LANG
                    "@syntax here => system:clock.\n" "a := here(#1).\n");
    expect_rejected("declared twice", LANG
                    "@syntax f(a) => a.\n@syntax f(b) => b.\nc := f(#1).\n");
    expect_rejected("no template", LANG "@syntax f(a).\n");

    /* A template that binds a name the form already gave a meaning to is two
       things at once, and is refused where the author is. */
    expect_rejected("a template binding its own parameter", LANG
                    "@syntax f(t) => { | t | t }:value.\n" "a := f(#1).\n");

    /* And what only the template and the use together can be wrong about. The
       trail is what makes this reportable; see the note in expand.c. */
    expect_rejected("assigning through a form", LANG
                    "@syntax setTo(p, v) => p := v.\n" "setTo(#1, #2).\n");
    expect("assigning through a form, to a place", LANG
           "@syntax setTo(p, v) => p := v.\n" "setTo(x, #2).\n",
           "x := #2.\n");

    /* Referential transparency: the other half of hygiene.
     *
     * A template's *free* reference means the global, and it may land inside a
     * frame that happens to bind that name. Solveig resolves a bare name to a
     * local before a global, so the form would quietly update the caller's
     * variable -- and the caller's local is what gives way, because reaching
     * the global is the whole of what the template meant. */
    expect("a caller's local cannot catch a template's free name", LANG
           "@syntax bump(n) => total := total:add(n).\n"
           "run := { | total | total := #100. bump(#5). total }.\n",
           "run := { | total__1 |\n"
           "    total__1 := #100.\n"
           "    total := total:add(#5).\n"
           "    total__1 }.\n");

    /* The argument is the caller's code and follows the caller's local, which
       is what the same-origin rule is for: two identifiers spelled `total`, one
       renamed and one not, in one expression. */
    expect("an argument follows the local it named", LANG
           "@syntax bump(n) => total := total:add(n).\n"
           "run := { | total | total := #1. bump(total). total }.\n",
           "run := { | total__1 |\n"
           "    total__1 := #1.\n"
           "    total := total:add(total__1).\n"
           "    total__1 }.\n");

    /* Every enclosing frame that binds the name, not only the innermost --
       renaming one would otherwise hand the capture to the next one out. The
       inner frame is renamed first because the search runs outward from the
       reference, which is why it holds the lower number. */
    expect("two frames deep", LANG
           "@syntax bump(n) => total := total:add(n).\n"
           "run := { | total | { | total | bump(#1) }:value }.\n",
           "run := { | total__2 | { | total__1 | total := total:add(#1) }:value }.\n");

    /* A frame that binds the name and is not in the way is left alone: the
       reference is inside neither of them. */
    expect("a frame the form is not inside is untouched", LANG
           "@syntax bump(n) => total := total:add(n).\n"
           "other := { | total | total := #1 }.\n"
           "bump(#2).\n",
           "other := { | total | total := #1 }.\n"
           "total := total:add(#2).\n");

    /* And a local the template meant to have is its own, not a capture. */
    expect("a template's own local is not renamed", LANG
           "@syntax hold(v) => { | total | total := v. total }:value.\n"
           "run := { | total | total := #1. hold(#2) }.\n",
           "run := { | total |\n"
           "    total := #1.\n"
           "    { | total__1 |\n"
           "        total__1 := #2.\n"
           "        total__1 }:value }.\n");

    printf("%d checks, %d failed\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
