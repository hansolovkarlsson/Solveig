/* The documents, held against the implementation they describe.
 *
 * Two checks and one idea: a sentence in this repository is a claim, and a
 * claim that nothing runs is one somebody looked at once. `expect.sol` runs
 * the claims in `examples/` and the documents; the grammar sweep holds
 * `solum.bnf` to what `solas` actually accepts.
 *
 * **They were in test_cli.c until 2026-09-03**, because they run the binaries
 * as a shell would and that is what that file does. What made the filing worth
 * correcting is that they are not a check of a command line: they are a check
 * of the repository, and they are most of what `make test` costs. Measured on
 * the day they moved, `test_cli` was 79.75 seconds of an 84-second suite, and
 * 54 of those were this file's first function -- at 41% CPU, because it
 * compiles and runs each claim in a process of its own. Two thirds of the
 * suite was the documentation checker, filed under the command line.
 *
 * Nothing about either check changed in the move: same assertions, same
 * floors, same order. */
#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DIR "build/tests/documents"

/* Runs `command` and answers its exit status, copying up to `size` bytes of
   whatever it wrote to `out`. Only one stream is captured per call, so the
   caller redirects the one it does not want. The twin of test_cli.c's, and
   deliberately a copy: a header shared by two test files would be a third
   place to look for a nine-line function. */
static int run(const char *command, char *out, size_t size)
{
    out[0] = '\0';
    FILE *pipe = popen(command, "r");
    assert(pipe != NULL);

    size_t filled = 0;
    size_t n;
    while (filled + 1 < size &&
           (n = fread(out + filled, 1, size - filled - 1, pipe)) > 0) {
        filled += n;
    }
    out[filled] = '\0';

    int status = pclose(pipe);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/* Everything this repository writes down about what it prints.
 *
 * Two notations, one job. `examples/` carries about four hundred claims in
 * comments -- `#2:add(#3):print.  ; #5` -- and the documents carry two hundred
 * more inside ``` fences, in the same notation. Nothing checked either until
 * programs/expect.sol existed: the rest of this suite compiles every example
 * and never ran one, so those comments were true because somebody looked, once.
 *
 * Checking them found two things wrong: the guide showed a stack trace in a
 * format that predates 6.27 adding the filename, and class-and-instance.md said
 * `integer` has 24 slots where it has 38.
 *
 * A block that will not run is a failure, and the escape is a word after the
 * fence: a `text` tag for a session or a sketch, `sh` for a shell transcript.
 * That
 * used to be a count instead, and the count hid 54 claims in 42 blocks --
 * including the guide's `point:slots` answering slots that page never defined,
 * the reference using an `integer:poly` that appears nowhere else in it, and
 * class-and-instance.md's `#45:new(#1):print. ; #1`, which the language stopped
 * doing at some point without the document noticing.
 *
 * CHANGELOG.md is the one document whose *blocks* are skipped: it records what
 * was true at each release, so its snippets describe past states on purpose.
 * Its headings are read all the same, for the commit hash each one names. */
static void test_everything_written_down_is_true(void)
{
    char out[64 * 1024];

    assert(run("bin/solas programs/expect.sol -o " DIR "/expect.sob 2>&1",
               out, sizeof out) == 0);

    int status = run("bin/solvm " DIR "/expect.sob"
                     " examples docs README.md index.md extensions 2>/dev/null",
                     out, sizeof out);
    if (status != 0 || strstr(out, "every claim holds") == NULL) {
        printf("\n%s\n", out);
        assert(false);
    }

    /* And the count, so that a checker which quietly stopped finding anything
       to check fails too. It was 589 across 40 files when this went in and 729
       across 41 once blocks began to be read on the page they were written
       under; the floor is there to catch a collapse, not to be updated for
       every example that gains a line. */
    int claims = 0;
    const char *at = strstr(out, "claims checked");
    assert(at != NULL);
    while (at > out && *at != ',') at--;
    assert(sscanf(at, ", %d claims checked", &claims) == 1);
    assert(claims >= 700);

    /* And the counts the prose states about this repository, which are neither
       a comment on a printing line nor a fenced block, and so went stale in
       three documents at once for three releases. A marker in the sentence says
       what the number counts and the checker recounts it -- so a floor here
       catches the other direction, a run that quietly stops finding any. */
    int counts = 0;
    at = strstr(out, "counts stated in prose");
    assert(at != NULL);
    while (at > out && at[-1] != '\n') at--;
    assert(sscanf(at, "%d counts stated in prose", &counts) == 1);
    assert(counts >= 15);

    int placed = 0;
    at = strstr(out, "programs say where they come in the order");
    assert(at != NULL);
    while (at > out && at[-1] != '\n') at--;
    assert(sscanf(at, "%d programs say where they come", &placed) == 1);
    assert(placed >= 8);

    /* The other language in these documents. `docs/SOLABASIC*.md` define a
       BASIC dialect, ship a compiler for it, and had been checking their own
       examples by eye -- a fenced block naming a language was skipped here.
       A block followed by the output it prints is now compiled and run, so the
       floor catches a run that quietly stops compiling any of them. */
    int basic = 0, basicChecked = 0;
    at = strstr(out, "SolaBasic block");
    assert(at != NULL);
    while (at > out && at[-1] != '\n') at--;
    assert(sscanf(at, "%d SolaBasic block%*[s] %d checked", &basic,
                  &basicChecked) == 2 ||
           sscanf(at, "%d SolaBasic blocks, %d checked", &basic,
                  &basicChecked) == 2);
    assert(basic >= 60);
    assert(basicChecked >= 20);

    /* docs/GRAMMAR.md opens by saying it is the same grammar as solum.bnf, and
       that is the largest claim on the page: everything else there is one
       production and that sentence is all of them at once. Compared character
       for character, so a floor here catches a run that quietly stops
       comparing any. */
    int agree = 0;
    at = strstr(out, "GRAMMAR.md and solum.bnf agree on");
    assert(at != NULL);
    assert(sscanf(at, "GRAMMAR.md and solum.bnf agree on %d production", &agree) == 1);
    assert(agree >= 20);

    /* Every changelog entry names the commit it landed in, and that hash is put
       there by a *second* commit -- a commit cannot carry its own hash, so the
       entry goes in saying `pending` and a follow-up substitutes the real one.
       Nothing asked whether the substitution had worked, and once it had not:
       the PRINT USING entry of 2026-08-26 carried a literal `%s` through every
       run of this test for two days, and was found by a person reading the page
       while cutting 0.35.0. ROADMAP 3.21. A floor here for the same reason as
       the others: a guard that stops finding hashes to check is a guard that
       has stopped. */
    int hashes = 0;
    at = strstr(out, "changelog entr");
    assert(at != NULL);
    while (at > out && at[-1] != '\n') at--;
    assert(sscanf(at, "%d changelog entr", &hashes) == 1);
    assert(hashes >= 240);

    /* Every markdown link that names a heading, held against the headings that
       are there -- the one cross-reference nothing read, in a repository whose
       filing system is moving a heading between files when an entry closes. The
       fences are tracked because a heading inside one is not an anchor on the
       page, and the count of those is asserted too: it is 1 today, it was 12
       while a paragraph in CHANGELOG.md was wrapped so that ``` began a line,
       and a ceiling is what makes that visible here rather than only in the
       report. A floor on the links for the same reason as every other one. */
    int links = 0, named = 0, fenced = 0;
    at = strstr(out, "links in");
    assert(at != NULL);
    while (at > out && at[-1] != '\n') at--;
    assert(sscanf(at, "%d links in %*d files, %d of them naming a heading",
                  &links, &named) == 2);
    assert(links >= 2000);
    assert(named >= 1000);

    /* Absent when it is nought, which is the good direction and not a
       failure -- the report leaves a count of nothing unsaid. */
    at = strstr(out, "inside a fenced block");
    if (at != NULL) {
        while (at > out && at[-1] != '\n') at--;
        assert(sscanf(at, "%d heading", &fenced) == 1);
    }
    assert(fenced <= 4);

    printf("  everything written down is true (%d claims, %d counts, %d "
           "positions, %d of %d SolaBasic blocks, %d productions, %d commit "
           "hashes, %d of %d links)\n",
           claims, counts, placed, basicChecked, basic, agree, hashes,
           named, links);
}

/* The grammar against the compiler, one construct at a time.
 *
 * **Nothing had ever held solum.bnf to solas.** expect.sol checks GRAMMAR.md
 * against solum.bnf -- two documents written by hand from one understanding,
 * which is the shape this repository calls "not a comparison" everywhere else.
 * An outside user reading the grammar to build a front end asked whether it was
 * current on 2026-09-01, and answering it took a sweep nobody had run.
 *
 * The failure that matters is a construct added to the language and not to the
 * grammar. It has been close twice: `@expr{...}` landed on 2026-08-29 and
 * `#["key" = value]` on 2026-08-30, and both went into the grammar in the same
 * commit -- by discipline, with nothing checking.
 *
 * **Every file in programs/check_syntax/syntax/ must be accepted by both.** They
 * are one construct each and a few lines long, so this costs about two seconds
 * where the full sweep over everything that ships costs forty-four -- almost all
 * of it one 196 KB file, since the grammar itself parses in 0.046 s. The sweep
 * is programs/check_syntax/sweep.sh, run when somebody wants to know.
 *
 * **Valid programs only, and that is deliberate.** The two are allowed to
 * disagree the other way: a grammar cannot carry a scope rule, so `self := #1`
 * is an ordinary identifier being assigned as far as solum.bnf is concerned and
 * an error to solas. Those belong in a document, not in a corpus that asserts
 * agreement. */
static void test_the_grammar_matches_the_compiler(void)
{
    char out[64 * 1024];

    assert(run("bin/solas programs/check_syntax.sol -o " DIR "/cs.sob 2>&1",
               out, sizeof out) == 0);

    /* The sweep is a shell loop rather than `opendir`, because `DIR` is already
       a macro for the build directory in this file -- and because running the
       binaries as a shell would is what the rest of this suite does. */
    int status = run(
        "n=0; for f in programs/check_syntax/syntax/*.sol; do "
        "  bin/solas \"$f\" -o " DIR "/one.sob >/dev/null 2>&1 || "
        "    { echo \"solas refuses $f\"; exit 1; }; "
        "  bin/solvm " DIR "/cs.sob programs/check_syntax/solum.bnf \"$f\" "
        "    >/dev/null 2>&1 || "
        "    { echo \"the grammar refuses $f\"; exit 1; }; "
        "  n=$((n + 1)); "
        "done; echo \"checked $n\"",
        out, sizeof out);

    if (status != 0) {
        printf("\n%s\na construct is in the language and not in the grammar,\n"
               "or a construct file stopped compiling\n", out);
        assert(false);
    }

    int checked = 0;
    const char *at = strstr(out, "checked ");
    assert(at != NULL);
    assert(sscanf(at, "checked %d", &checked) == 1);

    /* A floor, for the same reason every other count here has one: a sweep that
       quietly stops finding files to check is a sweep that has stopped. */
    assert(checked >= 12);
    printf("  the grammar accepts every construct the compiler does (%d)\n",
           checked);
}

int main(void)
{
    assert(system("mkdir -p " DIR) == 0);
    test_everything_written_down_is_true();
    test_the_grammar_matches_the_compiler();
    printf("test_documents: ok\n");
    return 0;
}
