/* What Solas refuses, and what it promises about what it emits.
 *
 * The second half is the point. A temporary declared in a top-level group used
 * to be compiled into a frame slot the script does not have: the verifier
 * refused the result, so `solas` failed at the point of writing the file and
 * said the bytecode was inconsistent, while Solis -- which runs what it just
 * compiled, without verifying -- wrote the temporary over the bottom of the
 * expression stack and answered wrongly. One source mistake, reported as an
 * internal fault in one front end and not at all in the other.
 *
 * So this file checks the refusal, and then checks the invariant the bug broke:
 * whatever Solas accepts, the verifier accepts. That is what lets Solis trust
 * its own compiler.
 */
#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "solas/compiler.h"
#include "solum/bytecode.h"
#include "solum/serialize.h"
#include "solum/vm.h"

/* Compiles a program that must fail, and hands back what Solas printed. */
static void compile_error_of(const char *source, char *out, size_t size)
{
    char path[] = "/tmp/solum-compile-err-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);

    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    assert(saved >= 0);
    assert(dup2(fd, STDERR_FILENO) >= 0);

    SolChunk chunk;
    sol_chunk_init(&chunk);
    bool ok = sol_compile(source, &chunk);
    sol_chunk_free(&chunk);

    fflush(stderr);
    assert(dup2(saved, STDERR_FILENO) >= 0);
    close(saved);

    assert(lseek(fd, 0, SEEK_SET) == 0);
    ssize_t got = read(fd, out, size - 1);
    out[got > 0 ? (size_t)got : 0] = '\0';
    close(fd);
    remove(path);

    assert(!ok);
}

/* ---- a temporary needs a frame, and now the script has one ------------- */

/* This used to be the file's centrepiece and it has turned into its opposite.
   The top level of a script reserved no slots, so a temporary declared there
   was emitted against the bottom of the expression stack, and the compiler
   refused it at the `|` rather than let the verifier report an internal fault.

   `SolChunk` carries a slot count now and `sol_vm_run` reserves it, so there is
   somewhere for the temporary to live and nothing left to refuse. What the old
   test guarded -- that the emitted code addresses a slot the frame really has
   -- is guarded here by running it and by the verifier accepting it. */
static void test_a_top_level_group_can_declare_a_temporary(void)
{
    static const struct { const char *source; int64_t answer; } accepted[] = {
        { "r := ( | t | t := #5. t ).",                          5  },
        { "r := ( | a, b | a := #2. b := #3. a:mul(b) ).",       6  },
        { "r := #1:add(( | t | t := #5. t )).",                  6  },
        { "( | t | t := #7. r := t ).",                          7  },
        /* one the enclosing expression would have overwritten before */
        { "r := #10:add(( | t | t := #1. t )):add(( | u | u := #2. u )).", 13 },
    };

    for (size_t i = 0; i < sizeof(accepted) / sizeof(accepted[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        sol_chunk_init(&chunk);

        assert(sol_compile(accepted[i].source, &chunk));
        assert(sol_chunk_verify(&chunk) == SOL_SER_OK);
        assert(chunk.slot_count >= 2);       /* slot 0, plus what was declared */
        assert(sol_vm_run(&vm, &chunk) == SOL_OK);

        SolSlot *slot = sol_object_lookup(vm.root, "r");
        assert(slot != NULL);
        assert(SOL_AS_INT(slot->value) == accepted[i].answer);

        sol_chunk_free(&chunk);
        sol_vm_free(&vm);
    }
    printf("  the top level declares temporaries, and they live in its frame\n");
}

/* A script that declares nothing still reserves the one unnameable slot, so a
   slot index means the same thing in every frame. */
static void test_a_script_without_temporaries_reserves_one_slot(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("x := #1. x:print.", &chunk));
    assert(chunk.slot_count == 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_OK);
    sol_chunk_free(&chunk);
    printf("  a script with no temporaries reserves slot 0 and no more\n");
}

/* And still works wherever there is a frame to hold it, which is what makes the
   refusal a statement about frames rather than about groups. */
static void test_a_frame_still_holds_its_temporaries(void)
{
    static const struct { const char *source; int64_t answer; } accepted[] = {
        { "r := { | t | t := #5. t }:value.",                          5  },
        { "r := { ( | t | t := #5. t ) }:value.",                      5  },
        { "r := { a | | t | t := a:add(#1). t }:value(#6).",           7  },
        { "integer:f := { ( | t | t := self:add(#1). t ) }. r := #41:f.", 42 },
        { "integer:g := { | t | t := #2. ( | u | u := t:mul(#3). u ) }. r := #0:g.", 6 },
    };

    for (size_t i = 0; i < sizeof(accepted) / sizeof(accepted[0]); i++) {
        SolChunk chunk;
        sol_chunk_init(&chunk);
        assert(sol_compile(accepted[i].source, &chunk));
        assert(sol_chunk_verify(&chunk) == SOL_SER_OK);

        SolVM vm;
        sol_vm_init(&vm);
        assert(sol_vm_run(&vm, &chunk) == SOL_OK);
        SolSlot *r = sol_object_lookup(vm.root, "r");
        assert(r != NULL && SOL_IS_INT(r->value));
        assert(SOL_AS_INT(r->value) == accepted[i].answer);
        sol_vm_free(&vm);
        sol_chunk_free(&chunk);
    }
    printf("  a block, a method, and a group inside either still declare\n");
}

/* The shape of the old bug, pinned: the temporary landed in stack slot 0, where
   the receiver of the enclosing send was sitting, so `#1:add(...)` answered #10
   instead of #6 -- silently, with no error anywhere. It cannot compile now, but
   what makes that a fix rather than a coincidence is the verifier: a top-level
   frame slot is out of range, and always was. */
static void test_the_old_form_would_not_have_verified(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    /* Hand-assembled `#5` into slot 0 of a chunk with no slots -- what the
       compiler used to emit for `( | t | t := #5. t )` at the top level. */
    int five = sol_chunk_add_constant(&chunk, SOL_INT_VAL(5));
    sol_chunk_write(&chunk, OP_CONST, 1);
    sol_chunk_write(&chunk, sol_u16_first((uint16_t)five), 1);
    sol_chunk_write(&chunk, sol_u16_second((uint16_t)five), 1);
    sol_chunk_write(&chunk, OP_SET_LOCAL, 1);
    sol_chunk_write(&chunk, 0, 1);
    sol_chunk_write(&chunk, OP_POP, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);

    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);
    printf("  a top-level frame slot is still refused by the verifier\n");
}

/* ---- what Solas emits, the verifier accepts --------------------------- */

/* `path` is the file the source came from, or NULL for a snippet written here.
   An example that includes another file needs it: an include resolves against
   the file it is written in. */
/* `lib` is on the search path, because an example that uses the shipped library
   writes `@include "control.sol"` the way a program would rather than reaching
   for it by a relative path nobody else would type. Tests run from the repo
   root, which is where `lib` is. */
static void must_verify(const char *what, const char *source, const char *path)
{
    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, "lib");

    SolChunk chunk;
    sol_chunk_init(&chunk);
    if (!sol_compile_file(source, path, &search, &chunk)) {
        printf("  did not compile: %s\n", what);
        assert(false);
    }
    SolSerResult result = sol_chunk_verify(&chunk);
    if (result != SOL_SER_OK) {
        printf("  emitted but does not verify: %s -- %s\n",
               what, sol_ser_message(result));
        assert(false);
    }
    sol_chunk_free(&chunk);
    sol_search_path_free(&search);
}

/* Every shipped .sol outside lib/, read from disk. They are the largest programs
   the project has, and they exercise the emitter far past what a snippet
   reaches.
 *
 * Two directories, and the split is the one the files already declared: a
 * demonstration is written to show a feature, a program is written to do a job
 * and uses whatever the language turned out to have. One list, because what
 * this file asks of them is the same question -- does it compile to bytecode
 * the verifier accepts -- and the directories below are what keeps the two
 * kinds apart for a reader. */
static const char *shipped[] = {
    "examples/hello.sol",      "examples/blocks.sol",
    "examples/arrays.sol",     "examples/strings.sol",
    "examples/methods.sol",    "examples/objects.sol",
    "examples/reflect.sol",    "examples/symbols.sol",
    "examples/numbers.sol",    "examples/format.sol",
    "examples/values.sol",     "examples/stock.sol",
    "examples/library.sol",    "examples/include.sol",
    "examples/system.sol",     "examples/reading.sol",
    "examples/files.sol",      "examples/binding.sol",
    "examples/strictness.sol", "examples/dictionaries.sol",
    "examples/loops.sol",      "examples/errors.sol",
    "examples/walk.sol",       "examples/time.sol",
    "examples/keys.sol",      "examples/random.sol",
    "examples/scanning.sol", "examples/commands.sol",
    "examples/matching.sol",

    "programs/log.sol",        "programs/evaluator.sol",
    "programs/manifest.sol",   "programs/page.sol",
    "programs/mirror.sol",     "programs/tools.sol",
    "programs/serve.sol",      "programs/disasm.sol",
    "programs/expect.sol",     "programs/bench.sol",
    "programs/basic.sol",       "programs/edit.sol",
    "programs/sola.sol",
};
#define SHIPPED_COUNT (sizeof(shipped) / sizeof(shipped[0]))

static void test_every_example_verifies(void)
{
    for (size_t i = 0; i < SHIPPED_COUNT; i++) {
        FILE *f = fopen(shipped[i], "rb");
        assert(f != NULL);                    /* tests run from the repo root */
        assert(fseek(f, 0, SEEK_END) == 0);
        long size = ftell(f);
        assert(size > 0);
        rewind(f);

        char *source = malloc((size_t)size + 1);
        assert(source != NULL);
        assert(fread(source, 1, (size_t)size, f) == (size_t)size);
        source[size] = '\0';
        fclose(f);

        must_verify(shipped[i], source, shipped[i]);
        free(source);
    }
    printf("  all %zu examples and programs compile to bytecode the verifier "
           "accepts\n", SHIPPED_COUNT);
}

/* ---- what the examples cover ------------------------------------------- *
 *
 * The examples were written alongside whatever was being built at the time
 * rather than against what a reader needs, so an audit found what they did not
 * reach. These two keep that from happening again by asking the question the
 * audit asked, every build.
 */

static char *slurp(const char *path)
{
    FILE *f = fopen(path, "rb");
    assert(f != NULL);                        /* tests run from the repo root */

    assert(fseek(f, 0, SEEK_END) == 0);
    long size = ftell(f);
    assert(size > 0);
    rewind(f);

    char *text = malloc((size_t)size + 1);
    assert(text != NULL);
    assert(fread(text, 1, (size_t)size, f) == (size_t)size);
    text[size] = '\0';
    fclose(f);
    return text;
}

/* Blanks out `;` comments in place, so a message that only appears in one is
   not counted as covered. A `;` inside a string is not a comment -- and there
   is one, in files.sol, which is why this tracks quotes rather than taking the
   first semicolon on the line. */
static void blank_out_comments(char *source)
{
    bool in_string = false;
    for (char *at = source; *at != '\0'; at++) {
        if (in_string) {
            if (*at == '\\' && at[1] != '\0') at++;
            else if (*at == '"') in_string = false;
            continue;
        }
        if (*at == '"') { in_string = true; continue; }
        if (*at == ';') {
            while (*at != '\0' && *at != '\n') *at++ = ' ';
            if (*at == '\0') break;
        }
    }
}

/* Is `:name` sent anywhere in `text`? */
static bool is_sent(const char *text, const char *name)
{
    size_t length = strlen(name);
    for (const char *at = strchr(text, ':'); at != NULL; at = strchr(at + 1, ':')) {
        if (strncmp(at + 1, name, length) != 0) continue;

        char after = at[1 + length];
        bool ends = !((after >= 'a' && after <= 'z') || (after >= 'A' && after <= 'Z') ||
                      (after >= '0' && after <= '9') || after == '_');
        if (ends) return true;
    }
    return false;
}

/* Every built-in message is sent by at least one file in examples/.
 *
 * The selectors come out of the registrations in builtins.c, so there is no
 * list here to fall behind: a primitive installed without an example to show it
 * fails this. When the audit ran, exactly one message had never been sent in an
 * example -- `lessOrEqual`.
 *
 * **examples/ only, deliberately.** A program in programs/ is written to do a
 * job and reaches for whatever it needs; counting it here would let a message
 * be "covered" by appearing incidentally in the middle of two hundred lines of
 * log parsing, which is not what someone looking up a message wants to find.
 * The demonstration has to exist.
 *
 * The split found four that only a program showed -- `values`, and `modeOf`,
 * `setMode` and `setModifiedAt` from mirror.sol. Each went into the example it
 * belonged in, which is why this can ask for the stricter thing. */
static void test_every_builtin_message_has_an_example(void)
{
    char *builtins = slurp("solum/src/builtins.c");

    char *covered = NULL;
    size_t length = 0;
    for (size_t i = 0; i < SHIPPED_COUNT; i++) {
        if (strncmp(shipped[i], "examples/", 9) != 0) continue;

        char *source = slurp(shipped[i]);
        blank_out_comments(source);

        size_t add = strlen(source);
        covered = realloc(covered, length + add + 2);
        assert(covered != NULL);
        memcpy(covered + length, source, add);
        covered[length + add] = '\n';
        covered[length + add + 1] = '\0';
        length += add + 1;
        free(source);
    }

    int checked = 0;
    for (char *line = strtok(builtins, "\n"); line != NULL; line = strtok(NULL, "\n")) {
        if (strstr(line, "instance(vm,") == NULL &&
            strstr(line, "any_receiver(vm,") == NULL) {
            continue;
        }

        const char *open = strchr(line, '"');
        assert(open != NULL);                 /* every registration names one */
        const char *close = strchr(open + 1, '"');
        assert(close != NULL);

        char name[64];
        size_t n = (size_t)(close - open - 1);
        assert(n > 0 && n < sizeof name);
        memcpy(name, open + 1, n);
        name[n] = '\0';

        if (!is_sent(covered, name)) {
            printf("\n'%s' is a built-in message that nothing in examples/ "
                   "sends\n", name);
            assert(false);
        }
        checked++;
    }

    assert(checked > 60);                     /* it found the registrations */
    free(covered);
    free(builtins);
    printf("  every built-in message is sent by an example (%d registrations)\n",
           checked);
}

/* The reference's message index lists every built-in, and this is what keeps it
   that way. A reference that has fallen behind the thing it describes is worse
   than no reference, and the way an index falls behind is one message at a
   time -- so the same check that makes every message appear in an example makes
   every message appear in the index.
 *
   It checks presence rather than what is said about it. Which types answer a
   message is prose, and prose is not something a test can hold to; that the
   message is *there to look up* is. */
static void test_every_builtin_message_is_in_the_index(void)
{
    char *reference = slurp("docs/REFERENCE.md");
    const char *index = strstr(reference, "## Message index");
    assert(index != NULL);

    char *builtins = slurp("solum/src/builtins.c");
    int checked = 0;

    /* And the two numbers the index states about itself, which are prose and so
       outside what programs/expect.sol can reach -- see ROADMAP 3.16. They said
       215 registrations where there are 216, and the count of distinct names is
       arrived at here for the same reason: this is the only place that already
       knows it. */
    static char names[512][80];
    int name_count = 0;

    for (char *line = strtok(builtins, "\n"); line != NULL; line = strtok(NULL, "\n")) {
        if (strstr(line, "instance(vm,") == NULL &&
            strstr(line, "any_receiver(vm,") == NULL) {
            continue;
        }

        const char *open = strchr(line, '"');
        assert(open != NULL);
        const char *close = strchr(open + 1, '"');
        assert(close != NULL);

        /* The index writes each one as `name` in a table cell, so the backticks
           are part of what is looked for -- otherwise `add` would be found
           inside `makeDirectory` and the check would pass on nothing. */
        char wanted[80];
        size_t n = (size_t)(close - open - 1);
        assert(n > 0 && n + 3 < sizeof wanted);
        wanted[0] = '`';
        memcpy(wanted + 1, open + 1, n);
        wanted[n + 1] = '`';
        wanted[n + 2] = '\0';

        if (strstr(index, wanted) == NULL) {
            printf("\n%s is a built-in message and the reference's index does "
                   "not list it\n", wanted);
            assert(false);
        }
        checked++;

        bool seen = false;
        for (int i = 0; i < name_count; i++) {
            if (strcmp(names[i], wanted) == 0) { seen = true; break; }
        }
        if (!seen) {
            assert(name_count < (int)(sizeof names / sizeof names[0]));
            snprintf(names[name_count++], sizeof names[0], "%s", wanted);
        }
    }

    char sentence[80];
    snprintf(sentence, sizeof sentence, "%d messages across %d registrations.",
             name_count, checked);
    if (strstr(reference, sentence) == NULL) {
        printf("\nthe reference should say: %s\n", sentence);
        assert(false);
    }

    free(builtins);
    free(reference);
    printf("  the index lists every built-in message, and says how many "
           "(%d across %d)\n", name_count, checked);
}

/* The cheatsheet is the one-page list of everything the language answers, so it
   goes stale the same way the index does and is held to the same standard: every
   built-in message must appear in it.
 *
   It differs from the index in how a message is written. The index lists bare
   names in a column; the cheatsheet lists them the way they are called, so `add`
   appears as `add(n)` and `fromSeconds` appears as `time:fromSeconds(f)`. So the
   name is looked for where a listing would put it -- straight after a backtick
   or a receiver's colon, and straight before an open paren or the closing
   backtick. That accepts every shape a table cell uses and refuses a bare
   mention in a sentence or a use inside an example, which is the point: being
   *used* on the page is not being *listed* on it. */
static bool is_listed(const char *page, const char *name)
{
    size_t n = strlen(name);
    for (const char *at = strstr(page, name); at != NULL; at = strstr(at + 1, name)) {
        if (at == page) continue;
        char before = at[-1], after = at[n];
        if ((before == '`' || before == ':') && (after == '(' || after == '`')) {
            return true;
        }
    }
    return false;
}

static void test_every_builtin_message_is_in_the_cheatsheet(void)
{
    char *page = slurp("docs/CHEATSHEET.md");
    char *builtins = slurp("solum/src/builtins.c");
    int checked = 0;

    for (char *line = strtok(builtins, "\n"); line != NULL; line = strtok(NULL, "\n")) {
        if (strstr(line, "instance(vm,") == NULL &&
            strstr(line, "any_receiver(vm,") == NULL) {
            continue;
        }

        const char *open = strchr(line, '"');
        assert(open != NULL);
        const char *close = strchr(open + 1, '"');
        assert(close != NULL);

        char name[64];
        size_t n = (size_t)(close - open - 1);
        assert(n > 0 && n < sizeof name);
        memcpy(name, open + 1, n);
        name[n] = '\0';

        if (!is_listed(page, name)) {
            printf("\n'%s' is a built-in message and docs/CHEATSHEET.md does "
                   "not list it\n", name);
            assert(false);
        }
        checked++;
    }

    assert(checked > 60);
    free(builtins);
    free(page);
    printf("  every built-in message is on the cheatsheet (%d registrations)\n",
           checked);
}

/* And nothing ships unverified: every .sol in either directory is in the list
   above, so adding one without adding it here is caught rather than silently
   skipped. `library.sol` and the rest are all included, being ordinary files.
 *
 * Both directories are walked and the total is compared against the list, so a
 * file cannot hide by being moved from one to the other either. */
static int count_listed_in(const char *directory)
{
    DIR *dir = opendir(directory);
    assert(dir != NULL);                      /* tests run from the repo root */

    int found = 0;
    for (struct dirent *entry = readdir(dir); entry != NULL; entry = readdir(dir)) {
        const char *name = entry->d_name;
        size_t length = strlen(name);
        if (length < 5 || strcmp(name + length - 4, ".sol") != 0) continue;

        /* The return value is used, which is both how truncation becomes a
           failure here rather than a quietly shortened path, and what tells
           GCC the call was not careless -- d_name may be 255 bytes and it
           says so. */
        char path[256];
        int written = snprintf(path, sizeof path, "%s/%s", directory, name);
        assert(written > 0 && (size_t)written < sizeof path);

        bool listed = false;
        for (size_t i = 0; i < SHIPPED_COUNT; i++) {
            if (strcmp(shipped[i], path) == 0) { listed = true; break; }
        }
        if (!listed) {
            printf("\n%s is not in the list this file checks\n", path);
            assert(false);
        }
        found++;
    }
    closedir(dir);
    return found;
}

static void test_no_example_is_left_out(void)
{
    int examples = count_listed_in("examples");
    int programs = count_listed_in("programs");

    /* And none listed that is gone from both. */
    assert(examples + programs == (int)SHIPPED_COUNT);
    printf("  every .sol in examples/ (%d) and programs/ (%d) is checked\n",
           examples, programs);
}

/* The shipped library, the same way. It is two files now rather than one, and
   the second is a real program's worth of code, so leaving it unverified would
   be leaving the largest thing on the search path unchecked. */
static const char *library[] = {
    "lib/control.sol", "lib/text.sol", "lib/json.sol", "lib/shell.sol",
    "lib/html.sol", "lib/math.sol", "lib/scan.sol", "lib/pattern.sol",
};
#define LIBRARY_COUNT (sizeof(library) / sizeof(library[0]))

static void test_every_library_file_verifies(void)
{
    for (size_t i = 0; i < LIBRARY_COUNT; i++) {
        char *source = slurp(library[i]);
        must_verify(library[i], source, library[i]);
        free(source);
    }
    printf("  all %zu library files compile to bytecode the verifier accepts\n",
           LIBRARY_COUNT);
}

/* ---- a warning nobody fails on is a comment ----------------------------- *
 *
 * `solas` has warnings, and both were added because the failure they describe
 * surfaces a long way from its cause: a file that includes a library of its own
 * name (6.22), and two libraries binding one name (6.21). Until this existed
 * nothing in the build failed on either. The check above asks each shipped file
 * one question -- does it compile to bytecode the verifier accepts -- and never
 * looks at what the compiler said on the way.
 *
 * That is not hypothetical. `examples/scanning.sol` was written as
 * `examples/scan.sol`, which includes itself; the warning fired, named the
 * shadowed file exactly, and the file compiled and would have shipped. Only
 * running it found the problem, which is precisely what the warning exists to
 * make unnecessary.
 *
 * `experiment/` is deliberately not here. It is parked and expected to fall
 * behind the language, so holding it to this would make it a maintenance
 * burden rather than a proof. */
static bool compiles_saying_nothing(const char *path, char *said, size_t size)
{
    char temp[] = "build/tests/solum-warn-XXXXXX";
    int fd = mkstemp(temp);
    assert(fd >= 0);

    char *source = slurp(path);
    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, "lib");

    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    assert(saved >= 0);
    assert(dup2(fd, STDERR_FILENO) >= 0);

    SolChunk chunk;
    sol_chunk_init(&chunk);
    bool ok = sol_compile_file(source, path, &search, &chunk);

    fflush(stderr);
    assert(dup2(saved, STDERR_FILENO) >= 0);
    close(saved);

    sol_chunk_free(&chunk);
    sol_search_path_free(&search);
    free(source);

    assert(lseek(fd, 0, SEEK_SET) == 0);
    ssize_t got = read(fd, said, size - 1);
    said[got > 0 ? (size_t)got : 0] = '\0';
    close(fd);
    remove(temp);
    return ok;
}

static void test_nothing_shipped_compiles_with_a_warning(void)
{
    static char said[4096];
    size_t checked = 0;

    for (size_t i = 0; i < SHIPPED_COUNT; i++) {
        assert(compiles_saying_nothing(shipped[i], said, sizeof said));
        if (said[0] != '\0') {
            printf("\n%s compiles, and says so on the way:\n%s", shipped[i], said);
            assert(false);
        }
        checked++;
    }

    for (size_t i = 0; i < LIBRARY_COUNT; i++) {
        assert(compiles_saying_nothing(library[i], said, sizeof said));
        if (said[0] != '\0') {
            printf("\n%s compiles, and says so on the way:\n%s", library[i], said);
            assert(false);
        }
        checked++;
    }

    printf("  %zu shipped files compile without the compiler saying anything\n",
           checked);
}

static void test_no_library_file_is_left_out(void)
{
    DIR *dir = opendir("lib");
    assert(dir != NULL);

    int found = 0;
    for (struct dirent *entry = readdir(dir); entry != NULL; entry = readdir(dir)) {
        const char *name = entry->d_name;
        size_t length = strlen(name);
        if (length < 5 || strcmp(name + length - 4, ".sol") != 0) continue;

        char path[256];
        int written = snprintf(path, sizeof path, "lib/%s", name);
        assert(written > 0 && (size_t)written < sizeof path);

        bool listed = false;
        for (size_t i = 0; i < LIBRARY_COUNT; i++) {
            if (strcmp(library[i], path) == 0) { listed = true; break; }
        }
        if (!listed) {
            printf("\n%s is not in the list this file checks\n", path);
            assert(false);
        }
        found++;
    }
    closedir(dir);

    assert(found == (int)LIBRARY_COUNT);
    printf("  every .sol in lib/ is checked (%d of them)\n", found);
}

/* And the corners an example does not happen to reach. Anything the compiler
   accepts belongs here as it is added: this is the invariant, not a sample. */
static void test_every_accepted_form_verifies(void)
{
    static const char *sources[] = {
        "a := #1.",
        "a := 1.5e-3. b := \"s\". c := 'sym. d := [#1, a].",
        "a := ( #1. #2. #3 ).",
        "a := (#1:add((#2:mul(#3)))).",
        "true:ifTrue({ #1 }).",
        "true:ifFalse({ #1 }).",
        "true:ifElse({ #1 }, { #2 }).",
        "b := { #1 }. true:ifElse(b, b).",
        "i := #0. { i:lessThan(#3) }:whileTrue({ i := i:add(#1) }).",
        "c := { true }. c:whileTrue({ #1 }).",
        "i := #0. { i:lessThan(#3) }:whileTrue({ "
        "    i:equals(#1):ifElse({ i := i:add(#2) }, { i := i:add(#1) }) }).",
        "o := object:new. o:m := { | t | t := self. t }. o:m.",
        "o := object:new. o:n := { a, b | | t | t := a:add(b). t }. o:n(#1, #2).",
        "o := object:new. o:x := #1. o:y := o:x.",
        "p := object:new. q := p:new. q:z := { self:via(p):asString }.",
        "f := { a | { b | { c | a:add(b):add(c) } } }. f:value(#1):value(#2):value(#3).",
        "integer:fact := { self:lessThan(#2):ifElse({ #1 }, "
        "    { self:mul(self:sub(#1):fact) }) }. #5:fact:print.",
        "[#1, #2, #3]:collect({ e | e:mul(#2) }):select({ e | e:greaterThan(#2) }).",
        "[#3, #1]:sorted({ a, b | b:lessThan(a) }):print.",
        "\"{} and {}\":fill([#1, 'two]):display.",
        "#255:asBase(#16):asString(\"08\"):print.",
        "x := #1\n:add(#2).",
        "a := #1. a:perform('add, #2):print.",
        "true:and({ false }).",
        "false:or({ true }).",
        "b := { true }. true:and(b). false:or(b).",
        "x := #3. x:greaterThan(#0):and({ x:lessThan(#10) }):ifTrue({ x:print }).",
        "true:and({ true:or({ false }) }).",
        "{ true:and({ false }) }:whileTrue({ #1 }).",
    };

    for (size_t i = 0; i < sizeof(sources) / sizeof(sources[0]); i++) {
        must_verify(sources[i], sources[i], NULL);
    }
    printf("  %zu accepted forms, all verifiable\n",
           sizeof(sources) / sizeof(sources[0]));
}

/* ---- where the error is (5.4) -------------------------------------------
 *
 * A line number alone leaves the reader scanning it. These check the column
 * and the caret line, which are what turn "somewhere on line 3" into a place.
 */

/* The reported line and column, and the caret sitting under the right column
   of the line that is echoed back. */
static void test_an_error_names_a_line_and_a_column(void)
{
    static const struct {
        const char *source;
        const char *position;   /* the "[line L:C]" it must report */
        int         column;     /* where the caret must start */
        const char *carets;     /* and how much it must underline */
    } cases[] = {
        { "a := #1.\nb := #2 , .\n",            "[line 2:9]",  9,  "^" },
        { "a := #1.\nfrobnicate frobnicate.\n",  "[line 2:12]", 12, "^^^^^^^^^^" },
        { "b := @.\n",                          "[line 1:6]",  6,  "^" },
        { "a := (\n",                           "[line 2:1]",  1,  "^" },
        /* A string spanning lines is reported where it opened, not where the
           scanner gave up. */
        { "a := #1.\nb := \"one\ntwo\n",         "[line 2:6]",  6,  "^^^^" },
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        char out[1024];
        compile_error_of(cases[i].source, out, sizeof(out));

        assert(strstr(out, cases[i].position) != NULL);

        /* The caret line is the last, indented by two and then padded out to
           the column -- which is the assertion that matters, since a caret in
           the wrong place is worse than none at all. */
        char expected[256];
        int at = snprintf(expected, sizeof(expected), "\n  ");
        for (int pad = 1; pad < cases[i].column; pad++) expected[at++] = ' ';
        snprintf(expected + at, sizeof(expected) - (size_t)at, "%s\n",
                 cases[i].carets);
        assert(strstr(out, expected) != NULL);
    }
    printf("  %zu errors, each naming a column and pointing at it\n",
           sizeof(cases) / sizeof(cases[0]));
}

/* The caret has to land under the token in the line that was echoed, which is
   the whole point -- an off-by-one here is worse than no column at all. */
static void test_the_caret_lands_under_the_token(void)
{
    char out[1024];
    compile_error_of("value := #1.\nvalue value.\n", out, sizeof(out));

    /* Find the echoed source line and the caret line after it. */
    const char *echo = strstr(out, "\n  value value.\n  ");
    assert(echo != NULL);

    const char *line = echo + 3;                       /* past "\n  " */
    const char *carets = strstr(line, "\n  ") + 3;     /* past the next "\n  " */
    size_t indent = strspn(carets, " ");

    /* "value value." -- the second `value` starts at index 6. */
    assert(indent == 6);
    assert(carets[indent] == '^');
    assert(strncmp(carets + indent, "^^^^^", 5) == 0);

    printf("  the caret sits under the token, not beside it\n");
}

/* A tab before the token is echoed as a tab in the pad, so the two line up
   whatever width the terminal gives it. */
static void test_a_tab_is_padded_with_a_tab(void)
{
    char out[1024];
    compile_error_of("f := {\n\t| t |\n\tt := , .\n\tt\n}.\n", out, sizeof(out));

    assert(strstr(out, "[line 3:7]") != NULL);
    assert(strstr(out, "\n  \tt := , .\n  \t     ^") != NULL);

    printf("  a tab in the source is a tab in the pad\n");
}

/* A line has no length limit -- Solis reads one of any size -- so a long one is
   windowed rather than spilled whole down the terminal. */
static void test_a_long_line_is_windowed(void)
{
    char source[4096];
    int at = snprintf(source, sizeof(source), "a := [");
    for (int i = 1; i < 40; i++) {
        at += snprintf(source + at, sizeof(source) - (size_t)at, "#%d, ", i);
    }
    snprintf(source + at, sizeof(source) - (size_t)at, ", ].\n");

    char out[2048];
    compile_error_of(source, out, sizeof(out));

    /* The echoed line is elided at the front and is not the whole source line. */
    assert(strstr(out, "\n  ...") != NULL);
    const char *echo = strstr(out, "\n  ...");
    const char *end = strchr(echo + 1, '\n');
    assert(end != NULL);
    assert((size_t)(end - echo) < 100);

    printf("  a long line is windowed around the token, not spilled\n");
}

int main(void)
{
    test_a_top_level_group_can_declare_a_temporary();
    test_a_script_without_temporaries_reserves_one_slot();
    test_a_frame_still_holds_its_temporaries();
    test_the_old_form_would_not_have_verified();
    test_every_example_verifies();
    test_every_builtin_message_has_an_example();
    test_every_builtin_message_is_in_the_index();
    test_every_builtin_message_is_in_the_cheatsheet();
    test_no_example_is_left_out();
    test_every_library_file_verifies();
    test_no_library_file_is_left_out();
    test_nothing_shipped_compiles_with_a_warning();
    test_every_accepted_form_verifies();
    test_an_error_names_a_line_and_a_column();
    test_the_caret_lands_under_the_token();
    test_a_tab_is_padded_with_a_tab();
    test_a_long_line_is_windowed();
    printf("test_compile: ok\n");
    return 0;
}
