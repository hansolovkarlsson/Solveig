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

    /* Patterns. A form that reads as a statement rather than as a call, which
       is what the parameter list could not say however it was spelled. */
    expect("a pattern", LANG
           "@syntax unless <t> then <a> => t:not:ifTrue({ a }).\n"
           "unless x then y:print.\n",
           "x:not:ifTrue({ y:print }).\n");

    /* Two forms under one word, told apart by the token after the shorter one
       ends. This is the case the matcher exists for. */
#define IFS \
    "@syntax if <c> then <a> => c:ifTrue({ a }).\n" \
    "@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).\n"

    expect("the shorter of two patterns", LANG IFS "if x then y:print.\n",
           "x:ifTrue({ y:print }).\n");
    expect("the longer of two patterns", LANG IFS
           "if x then y:print else z:print.\n",
           "x:ifElse({ y:print }, { z:print }).\n");

    /* A word in a pattern is not a word anywhere else. Reserving `then` because
       some module used it in a form would make a dialect a tax on every file
       that never asked for it. */
    expect("a pattern word is not reserved", LANG IFS
           "then := #1.\nelse := then.\n",
           "then := #1.\nelse := then.\n");

    /* Holes take the caller's code and the template puts the braces on, exactly
       as in the call shape -- a pattern changes how a form is written and
       nothing about what one is. */
    expect("a pattern is hygienic too", LANG
           "@syntax hold <v> in <b> => { | t | t := v. b }:value.\n"
           "t := #1.\n"
           "a := hold t in t.\n",
           "t := #1.\n"
           "a := { | t__1 |\n"
           "    t__1 := t.\n"
           "    t }:value.\n");

    expect_rejected("a missing word", LANG IFS "if x y:print.\n");
    expect_rejected("two holes in a row", LANG
                    "@syntax f <a> <b> => a:g(b).\nx := #1.\n");
    expect_rejected("a hole that is never closed", LANG
                    "@syntax f <a then <b> => a.\nx := #1.\n");
    expect_rejected("two patterns that cannot be told apart", LANG
                    "@syntax on <w> do <b> => w:run(b).\n"
                    "@syntax on error do <b> => b:run.\nx := #1.\n");
    expect_rejected("a name that is both shapes", LANG
                    "@syntax f(a) => a.\n"
                    "@syntax f <a> then <b> => a.\nx := #1.\n");
    expect_rejected("two patterns spelled the same way", LANG
                    "@syntax f <a> to <b> => a.\n"
                    "@syntax f <c> to <d> => c.\nx := #1.\n");

    /* A hole may say what it will accept. All five kinds are decided by looking
       at what was parsed, so none of them needs an evaluator -- what they buy is
       the message, not the check. */
    expect("a place hole takes a name", LANG
           "@syntax setTo <p: place> to <v> => p := v.\n"
           "setTo x to #1.\n",
           "x := #1.\n");
    expect("a place hole takes a slot", LANG
           "@syntax setTo <p: place> to <v> => p := v.\n"
           "setTo r:x to #1.\n",
           "r:x := #1.\n");
    expect("a name hole", LANG
           "@syntax define <n: name> as <v> => n := v.\n"
           "define x as #1.\n",
           "x := #1.\n");
    expect("a literal hole", LANG
           "@syntax tag <l: literal> => l:asString.\n"
           "a := tag 'red.\n",
           "a := 'red:asString.\n");
    expect("a block hole", LANG
           "@syntax repeat <n> times <b: block> => n:repeat(b).\n"
           "repeat #3 times { x:print }.\n",
           "#3:repeat({ x:print }).\n");

    /* Kinds are spelled the same way in the call shape, because a hole is a
       hole however the form around it is written. */
    expect("a kind in the call shape", LANG
           "@syntax setTo(p: place, v) => p := v.\n"
           "setTo(x, #1).\n",
           "x := #1.\n");

    /* Saying nothing has to go on working, or every dialect written before
       kinds existed breaks at once. */
    expect("an untyped hole still takes anything", LANG
           "@infix + 60 add.\n"
           "@syntax f(a) => a:print.\n"
           "f(#1 + #2).\n",
           "#1:add(#2):print.\n");

    /* An error inside a form's argument list leaves the `)` unconsumed, and
       until 0.6.0 the statement loop read it, failed, synchronised to it and
       read it again -- forever. Written the way it was found: this file had the
       `@infix` above missing, and `make test` stopped instead of failing. */
    expect_rejected("an error inside an argument list terminates", LANG
                    "@syntax f(a) => a:print.\n"
                    "f(#1 % #2).\n");

    /* Checked after the argument is expanded, so a hole filled by another form
       is checked against what that form became rather than against a use of it. */
    expect("a form as an argument is checked as what it becomes", LANG
           "@syntax alias <n: name> => n.\n"
           "@syntax setTo <p: place> to <v> => p := v.\n"
           "setTo alias x to #1.\n",
           "x := #1.\n");

    expect_rejected("a literal where a place was wanted", LANG
                    "@syntax setTo <p: place> to <v> => p := v.\n"
                    "setTo #1 to #2.\n");
    expect_rejected("an expression where a block was wanted", LANG
                    "@syntax repeat <n> times <b: block> => n:repeat(b).\n"
                    "repeat #3 times x:print.\n");
    expect_rejected("a send where a name was wanted", LANG
                    "@syntax define <n: name> as <v> => n := v.\n"
                    "define r:x as #1.\n");
    expect_rejected("a kind that is not one", LANG
                    "@syntax f <a: banana> => a.\nx := #1.\n");
    expect_rejected("a colon with nothing after it", LANG
                    "@syntax f <a: > => a.\nx := #1.\n");

    printf("%d checks, %d failed\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
