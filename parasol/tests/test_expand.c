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

#include "parasol/emit.h"
#include "parasol/expand.h"
#include "parasol/reader.h"
#include "parasol/unit.h"

static int failures = 0;
static int checks = 0;

/* What the last compile printed. A check on the *text* of a diagnostic is
 * worth having for exactly one class of defect: the message being right and
 * the position being wrong. POSTMORTEM.md 22 was that, and the check below it
 * -- `a form as an argument is checked as what it becomes` -- could not see it,
 * because asserting that something is rejected says nothing about where the
 * caret went. */
static char said[4096];

static char *compile(const char *text, int *errors)
{
    ParasolUnit unit;
    parasol_unit_init(&unit);

    const ParasolSource *source = parasol_unit_adopt(&unit, "<test>", text);

    FILE *sink = tmpfile();
    ParasolDiagnostics diag;
    parasol_diag_init(&diag, sink);

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
    *errors = diag.errors;

    char *out = NULL;
    if (module != NULL) {
        ParasolEmitter emitter;
        parasol_emitter_init(&emitter);
        parasol_emit(&emitter, module);
        const char *body = strstr(emitter.text, "\n\n");
        out = parasol_strndup(body + 2, strlen(body + 2));
        parasol_emitter_free(&emitter);
        parasol_node_free(module);
    }

    said[0] = '\0';
    rewind(sink);
    size_t n = fread(said, 1, sizeof said - 1, sink);
    said[n] = '\0';

    parasol_provenance_free(&provenance);
    parasol_dialect_free(&dialect);
    parasol_unit_free(&unit);
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

/* Rejected, and the first thing it said names this position. `<test>` is what
 * every source here is called, so `<test>:3:6` is a whole file-line-column. */
static void expect_rejected_at(const char *label, const char *text,
                               const char *where)
{
    checks++;
    int errors = 0;
    char *got = compile(text, &errors);
    if (got != NULL) {
        printf("  FAIL %s: compiled, and should not have\n", label);
        failures++;
        free(got);
        return;
    }
    if (strstr(said, where) == NULL) {
        printf("  FAIL %s\n    want a diagnostic at: %s\n    said: %s",
               label, where, said);
        failures++;
    }
}

/* Rejected, and it did *not* say this. A prescription that fires where it does
 * not apply is worse than none: it is a diagnostic the reader stops reading. */
static void expect_rejected_without(const char *label, const char *text,
                                    const char *absent)
{
    checks++;
    int errors = 0;
    char *got = compile(text, &errors);
    if (got != NULL) {
        printf("  FAIL %s: compiled, and should not have\n", label);
        failures++;
        free(got);
        return;
    }
    if (strstr(said, absent) != NULL) {
        printf("  FAIL %s\n    should not have said: %s\n    said: %s",
               label, absent, said);
        failures++;
    }
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

int main(void)
{
    /* Substitution, and the thing a form can do that a method cannot: the
       argument is not evaluated before it arrives, so the template may put it
       inside a block the caller never wrote. */
    expect("substitution",
           "@syntax twice(x) => x:add(x).\n"
           "a := twice(#2).\n",
           "a := #2:add(#2).\n");
    expect("an argument reaching inside a block",
           "@syntax unless(t, b) => t:not:ifTrue({ b }).\n"
           "unless(a, b:print).\n",
           "a:not:ifTrue({ b:print }).\n");
    expect("no arguments",
           "@syntax here => system:clock.\n"
           "a := here.\n",
           "a := system:clock.\n");

    /* A form may use the forms above it, and expansion therefore terminates:
       the highest index used strictly falls. */
    expect("a form using a form",
           "@syntax unless(t, b) => t:not:ifTrue({ b }).\n"
           "@syntax whenEmpty(c, b) => unless(c:isEmpty:not, b).\n"
           "whenEmpty(xs, y:print).\n",
           "xs:isEmpty:not:not:ifTrue({ y:print }).\n");

    /* Hygiene. The template binds `t`; the caller passes `t`. Asserted on the
       generated code, and the example is run for real in examples/forms.psol. */
    expect("a template binder cannot capture an argument",
           "@syntax hold(v) => { | t | t := v. t }:value.\n"
           "t := #1.\n"
           "a := hold(t).\n",
           "t := #1.\n"
           "a := { | t__1 |\n"
           "    t__1 := t.\n"
           "    t__1 }:value.\n");

    /* A generated name avoids every identifier in the module, so a caller who
       already has a `t__1` is not quietly broken by one. */
    expect("a fresh name is fresh against the whole module",
           "@syntax hold(v) => { | t | t := v. t }:value.\n"
           "t__1 := #9.\n"
           "a := hold(t__1).\n",
           "t__1 := #9.\n"
           "a := { | t__2 |\n"
           "    t__2 := t__1.\n"
           "    t__2 }:value.\n");

    /* Two expansions of one form do not share a name either. */
    expect("two expansions do not collide",
           "@syntax hold(v) => { | t | t }:value.\n"
           "a := hold(#1). b := hold(#2).\n",
           "a := { | t__1 | t__1 }:value.\n"
           "b := { | t__2 | t__2 }:value.\n");

    /* A name is only a form after it has been declared one, inside the header
       as much as after it. This is the whole of why expansion terminates: `g`
       below cannot reach `f`, so no form can reach itself, however the
       declarations are arranged. */
    expect("a template cannot see a form declared after it",
           "@syntax g(x) => f(x).\n"
           "@syntax f(y) => y:print.\n"
           "a := g(#1).\n",
           "a := #1:f.\n");

    /* What the reader can catch, it catches at the use, with the declaration
       pointed at. */
    expect_rejected("too few arguments",
                    "@syntax pair(a, b) => [a, b].\n" "c := pair(#1).\n");
    expect_rejected("too many arguments",
                    "@syntax pair(a, b) => [a, b].\n" "c := pair(#1, #2, #3).\n");
    expect_rejected("arguments to a form that takes none",
                    "@syntax here => system:clock.\n" "a := here(#1).\n");
    expect_rejected("declared twice",
                    "@syntax f(a) => a.\n@syntax f(b) => b.\nc := f(#1).\n");
    expect_rejected("no template", "@syntax f(a).\n");

    /* A template that binds a name the form already gave a meaning to is two
       things at once, and is refused where the author is. */
    expect_rejected("a template binding its own parameter",
                    "@syntax f(t) => { | t | t }:value.\n" "a := f(#1).\n");

    /* And what only the template and the use together can be wrong about. The
       trail is what makes this reportable; see the note in expand.c. */
    expect_rejected("assigning through a form",
                    "@syntax setTo(p, v) => p := v.\n" "setTo(#1, #2).\n");
    expect("assigning through a form, to a place",
           "@syntax setTo(p, v) => p := v.\n" "setTo(x, #2).\n",
           "x := #2.\n");

    /* Referential transparency: the other half of hygiene.
     *
     * A template's *free* reference means the global, and it may land inside a
     * frame that happens to bind that name. Solveig resolves a bare name to a
     * local before a global, so the form would quietly update the caller's
     * variable -- and the caller's local is what gives way, because reaching
     * the global is the whole of what the template meant. */
    expect("a caller's local cannot catch a template's free name",
           "@syntax bump(n) => total := total:add(n).\n"
           "run := { | total | total := #100. bump(#5). total }.\n",
           "run := { | total__1 |\n"
           "    total__1 := #100.\n"
           "    total := total:add(#5).\n"
           "    total__1 }.\n");

    /* The argument is the caller's code and follows the caller's local, which
       is what the same-origin rule is for: two identifiers spelled `total`, one
       renamed and one not, in one expression. */
    expect("an argument follows the local it named",
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
    expect("two frames deep",
           "@syntax bump(n) => total := total:add(n).\n"
           "run := { | total | { | total | bump(#1) }:value }.\n",
           "run := { | total__2 | { | total__1 | total := total:add(#1) }:value }.\n");

    /* A frame that binds the name and is not in the way is left alone: the
       reference is inside neither of them. */
    expect("a frame the form is not inside is untouched",
           "@syntax bump(n) => total := total:add(n).\n"
           "other := { | total | total := #1 }.\n"
           "bump(#2).\n",
           "other := { | total | total := #1 }.\n"
           "total := total:add(#2).\n");

    /* And a local the template meant to have is its own, not a capture. */
    expect("a template's own local is not renamed",
           "@syntax hold(v) => { | total | total := v. total }:value.\n"
           "run := { | total | total := #1. hold(#2) }.\n",
           "run := { | total |\n"
           "    total := #1.\n"
           "    { | total__1 |\n"
           "        total__1 := #2.\n"
           "        total__1 }:value }.\n");

    /* Patterns. A form that reads as a statement rather than as a call, which
       is what the parameter list could not say however it was spelled. */
    expect("a pattern",
           "@syntax unless <t> then <a> => t:not:ifTrue({ a }).\n"
           "unless x then y:print.\n",
           "x:not:ifTrue({ y:print }).\n");

    /* Two forms under one word, told apart by the token after the shorter one
       ends. This is the case the matcher exists for. */
#define IFS \
    "@syntax if <c> then <a> => c:ifTrue({ a }).\n" \
    "@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).\n"

    expect("the shorter of two patterns", IFS "if x then y:print.\n",
           "x:ifTrue({ y:print }).\n");
    expect("the longer of two patterns", IFS
           "if x then y:print else z:print.\n",
           "x:ifElse({ y:print }, { z:print }).\n");

    /* A word in a pattern is not a word anywhere else. Reserving `then` because
       some module used it in a form would make a dialect a tax on every file
       that never asked for it. */
    expect("a pattern word is not reserved", IFS
           "then := #1.\nelse := then.\n",
           "then := #1.\nelse := then.\n");

    /* Holes take the caller's code and the template puts the braces on, exactly
       as in the call shape -- a pattern changes how a form is written and
       nothing about what one is. */
    expect("a pattern is hygienic too",
           "@syntax hold <v> in <b> => { | t | t := v. b }:value.\n"
           "t := #1.\n"
           "a := hold t in t.\n",
           "t := #1.\n"
           "a := { | t__1 |\n"
           "    t__1 := t.\n"
           "    t }:value.\n");

    expect_rejected("a missing word", IFS "if x y:print.\n");
    expect_rejected("two holes in a row",
                    "@syntax f <a> <b> => a:g(b).\nx := #1.\n");
    expect_rejected("a hole that is never closed",
                    "@syntax f <a then <b> => a.\nx := #1.\n");
    expect_rejected("two patterns that cannot be told apart",
                    "@syntax on <w> do <b> => w:run(b).\n"
                    "@syntax on error do <b> => b:run.\nx := #1.\n");
    expect_rejected("a name that is both shapes",
                    "@syntax f(a) => a.\n"
                    "@syntax f <a> then <b> => a.\nx := #1.\n");
    expect_rejected("two patterns spelled the same way",
                    "@syntax f <a> to <b> => a.\n"
                    "@syntax f <c> to <d> => c.\nx := #1.\n");

    /* A hole may say what it will accept. All five kinds are decided by looking
       at what was parsed, so none of them needs an evaluator -- what they buy is
       the message, not the check. */
    expect("a place hole takes a name",
           "@syntax setTo <p: place> to <v> => p := v.\n"
           "setTo x to #1.\n",
           "x := #1.\n");
    expect("a place hole takes a slot",
           "@syntax setTo <p: place> to <v> => p := v.\n"
           "setTo r:x to #1.\n",
           "r:x := #1.\n");
    expect("a name hole",
           "@syntax define <n: name> as <v> => n := v.\n"
           "define x as #1.\n",
           "x := #1.\n");
    expect("a literal hole",
           "@syntax tag <l: literal> => l:asString.\n"
           "a := tag 'red.\n",
           "a := 'red:asString.\n");
    expect("a block hole",
           "@syntax repeat <n> times <b: block> => n:repeat(b).\n"
           "repeat #3 times { x:print }.\n",
           "#3:repeat({ x:print }).\n");

    /* Kinds are spelled the same way in the call shape, because a hole is a
       hole however the form around it is written. */
    expect("a kind in the call shape",
           "@syntax setTo(p: place, v) => p := v.\n"
           "setTo(x, #1).\n",
           "x := #1.\n");

    /* Saying nothing has to go on working, or every dialect written before
       kinds existed breaks at once. */
    expect("an untyped hole still takes anything",
           "@infix + 60 add.\n"
           "@syntax f(a) => a:print.\n"
           "f(#1 + #2).\n",
           "#1:add(#2):print.\n");

    /* An error inside a form's argument list leaves the `)` unconsumed, and
       until 0.6.0 the statement loop read it, failed, synchronised to it and
       read it again -- forever. Written the way it was found: this file had the
       `@infix` above missing, and `make test` stopped instead of failing. */
    expect_rejected("an error inside an argument list terminates",
                    "@syntax f(a) => a:print.\n"
                    "f(#1 % #2).\n");

    /* Checked after the argument is expanded, so a hole filled by another form
       is checked against what that form became rather than against a use of it. */
    expect("a form as an argument is checked as what it becomes",
           "@syntax alias <n: name> => n.\n"
           "@syntax setTo <p: place> to <v> => p := v.\n"
           "setTo alias x to #1.\n",
           "x := #1.\n");

    /* And reported where the argument was *written*, which is not where it
       ended up. `alias x` expands to the template's `n` on line 1, so until
       0.15.0 that is the position the error carried -- a caret inside a
       declaration, in the file a dialect came from rather than the one somebody
       is editing. POSTMORTEM.md 22.

       Both halves are here: the nested case, which was wrong, and the plain
       one beside it, which was always right and is what a fix could break. */
    expect_rejected_at("a form in a hole is reported where it was written",
                       "@syntax alias <n: name> => n.\n"
                       "@syntax hold <b: block> => b:value.\n"
                       "hold alias x.\n",
                       "<test>:3:6: error: 'hold' wants a block here");
    /* The severe shape, and the one POSTMORTEM.md 22 was reported as: the
       template *builds* the offending node -- `n:value` is a send this
       declaration made -- so the node's own span is inside the declaration.
       Unfixed, this names line 1 and puts a caret under `:value`, which in a
       real program is a file the reader has never opened. */
    expect_rejected_at("a template-built node is reported at the use, not the template",
                       "@syntax wrapped <n> => n:value.\n"
                       "@syntax hold <b: block> => b:value.\n"
                       "hold wrapped x.\n",
                       "<test>:3:6: error: 'hold' wants a block here");

    expect_rejected_at("a plain node in a hole is still reported at itself",
                       "@syntax hold <b: block> => b:value.\n"
                       "hold x.\n",
                       "<test>:2:6: error: 'hold' wants a block here");

    /* A diagnostic that points correctly and prescribes nothing is what both
       second-reader runs named as the next thing to fix, and neither reached:
       `lib/clike.psol` spends eleven lines at its own `else` declaration
       preventing the reader from ever seeing this message. That is the dialect
       author paying, once per dialect, for something the compiler can say once
       for all of them. See docs/second-reader.md, prediction 9. */
    expect_rejected_at("a block hole says how to satisfy it",
                       "@syntax hold <b: block> => b:value.\n"
                       "hold x.\n",
                       "note: wrap it in braces");
    /* And it prescribes only where a fix exists. Wrapping in braces makes a
       block out of anything; nothing makes a `place` out of `#1`, so the same
       note under a `place` failure would be advice that does not work. */
    expect_rejected_without("a place hole does not suggest braces",
                            "@syntax setTo <p: place> to <v> => p := v.\n"
                            "setTo #1 to #2.\n",
                            "wrap it in braces");
    expect_rejected("a literal where a place was wanted",
                    "@syntax setTo <p: place> to <v> => p := v.\n"
                    "setTo #1 to #2.\n");
    expect_rejected("an expression where a block was wanted",
                    "@syntax repeat <n> times <b: block> => n:repeat(b).\n"
                    "repeat #3 times x:print.\n");
    expect_rejected("a send where a name was wanted",
                    "@syntax define <n: name> as <v> => n := v.\n"
                    "define r:x as #1.\n");
    expect_rejected("a kind that is not one",
                    "@syntax f <a: banana> => a.\nx := #1.\n");
    expect_rejected("a colon with nothing after it",
                    "@syntax f <a: > => a.\nx := #1.\n");

    /* An operator may name a template rather than a message, which is the only
       way to declare one whose right-hand side must not be evaluated. Solveig's
       `and` takes a block; `@infix && 30 and` would compile to `a:and(b)` and
       be refused at run time. */
    expect("an infix template",
           "@infix && 30 => left:and({ right }).\n"
           "a := x && y.\n",
           "a := x:and({ y }).\n");
    expect("a prefix template",
           "@prefix ! => operand:not:not.\n"
           "a := !x.\n",
           "a := x:not:not.\n");

    /* Precedence and associativity are the operator's and are untouched by it
       having a template rather than a message. */
    expect("a template obeys precedence",
           "@infix + 60 add.\n"
           "@infix && 30 => left:and({ right }).\n"
           "a := x + y && z.\n",
           "a := x:add(y):and({ z }).\n");
    expect("a template groups to the left",
           "@infix && 30 => left:and({ right }).\n"
           "a := x && y && z.\n",
           "a := x:and({ y }):and({ z }).\n");

    /* And it is a form, so everything a form gets it gets: hygiene, and the
       refusal to bind what it was given. */
    expect("an operator template is hygienic",
           "@infix && 30 => { | t | t := left. t:and({ right }) }:value.\n"
           "t := true.\n"
           "a := t && t.\n",
           "t := true.\n"
           "a := { | t__1 |\n"
           "    t__1 := t.\n"
           "    t__1:and({ t }) }:value.\n");
    expect_rejected("a template binding an operand's name",
                    "@infix && 30 => { | left | left }:value.\n"
                    "a := x && y.\n");

    /* Naming a message still works, and is still the right answer when the
       message is one. */
    expect("an operator naming a message is unchanged",
           "@infix + 60 add.\n@prefix ~ not.\n"
           "a := ~x + y.\n",
           "a := x:not:add(y).\n");
    expect_rejected("an operator with neither a message nor a template",
                    "@infix + 60.\na := #1.\n");

    /* Two holes in a row, when the second is delimited. A block is a primary,
       consumed only where an operand may start, so an expression stops at the
       `{` and the split is exactly where a reader would put it. */
    expect("a hole then a block hole",
           "@syntax if <c> <t: block> => c:ifTrue(t).\n"
           "if (x) { y:print }.\n",
           "(x):ifTrue({ y:print }).\n");
    expect("and the condition may be any expression",
           "@infix < 40 lessThan.\n"
           "@syntax while <c> <b: block> => { c }:whileTrue(b).\n"
           "while (n < #5) { n:print }.\n",
           "{ (n:lessThan(#5)) }:whileTrue({ n:print }).\n");

    /* Undelimited stays refused, and the reason is greed rather than ambiguity:
       given `f x + y`, the first hole takes the sum and the second finds
       nothing. A `name` hole is mechanically findable too and is still refused,
       because "findable by knowing where the expression parser stops" is not
       the same as "where a reader would put it". */
    expect_rejected("two expression holes in a row",
                    "@syntax f <a> <b> => a.\nz := #1.\n");
    expect_rejected("a name hole after a hole",
                    "@syntax f <a> <b: name> => a.\nz := #1.\n");

    printf("%d checks, %d failed\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
