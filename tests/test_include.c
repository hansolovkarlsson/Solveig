/* `include`: compiling one file into another, and the rules that come with it. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "solas/compiler.h"
#include "solum/vm.h"

#define DIR "build/tests/inc"
#define LIB DIR "/lib"

static void make_directories(void)
{
    mkdir("build/tests", 0777);      /* make test creates this; be sure anyway */
    mkdir(DIR, 0777);
    mkdir(LIB, 0777);
}

static void write_file(const char *path, const char *text)
{
    FILE *f = fopen(path, "wb");
    assert(f != NULL);
    assert(fwrite(text, 1, strlen(text), f) == strlen(text));
    fclose(f);
}

/* Compiles the file at `path` the way solas does. */
static bool compile_file(const char *path, SolChunk *chunk)
{
    char *source = sol_read_file(path);
    assert(source != NULL);

    sol_chunk_init(chunk);
    bool ok = sol_compile_source(source, path, chunk);
    free(source);
    return ok;
}

static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

/* Runs a file and hands back the VM, so a test can read what it left behind. */
static void run_file(SolVM *vm, SolChunk *chunk, const char *path)
{
    assert(compile_file(path, chunk));
    assert(sol_vm_run(vm, chunk) == SOL_OK);
}

/* Compiles a file that must fail, and hands back what Solas printed. */
static void compile_error_of(const char *path, char *out, size_t size)
{
    char temp[] = "/tmp/solum-include-err-XXXXXX";
    int fd = mkstemp(temp);
    assert(fd >= 0);

    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    assert(saved >= 0);
    assert(dup2(fd, STDERR_FILENO) >= 0);

    SolChunk chunk;
    bool ok = compile_file(path, &chunk);
    sol_chunk_free(&chunk);

    fflush(stderr);
    assert(dup2(saved, STDERR_FILENO) >= 0);
    close(saved);

    assert(lseek(fd, 0, SEEK_SET) == 0);
    ssize_t got = read(fd, out, size - 1);
    out[got > 0 ? (size_t)got : 0] = '\0';
    close(fd);
    remove(temp);

    assert(!ok);
}

/* An included file's definitions are the includer's: one flat namespace, and
   the text lands where the include stands. */
static void test_an_include_brings_in_definitions(void)
{
    write_file(LIB "/greet.sol",
        "greeter := object:new.\n"
        "greeter:who := \"world\".\n"
        "greeter:hello := { \"hello, {}\":fill([self:who]) }.\n");
    write_file(DIR "/uses.sol",
        "@include \"lib/greet.sol\".\n"
        "g := greeter:new.\n"
        "g:who := \"Solveig\".\n"
        "said := g:hello.\n");

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    run_file(&vm, &chunk, DIR "/uses.sol");

    assert(strcmp(SOL_AS_STRING(global(&vm, "said"))->chars, "hello, Solveig") == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  an included file's definitions are in scope\n");
}

/* Resolution is against the including file, not the working directory. These
   tests run from the repo root, where "greet.sol" is nothing at all. */
static void test_a_file_is_found_beside_the_one_including_it(void)
{
    write_file(LIB "/neighbour.sol", "beside := #7.\n");
    write_file(LIB "/inner.sol",
        "@include \"neighbour.sol\".\n"
        "found := beside.\n");
    write_file(DIR "/outer.sol", "@include \"lib/inner.sol\".\n");

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    run_file(&vm, &chunk, DIR "/outer.sol");

    assert(SOL_AS_INT(global(&vm, "found")) == 7);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  an include resolves against the file it is written in\n");
}

/* Two paths to one file compile it once. The counter is what says so: compiled
   twice, the second copy would run again and leave two. */
static void test_a_file_is_compiled_once(void)
{
    write_file(LIB "/shared.sol", "times := times:add(#1).\n");
    write_file(LIB "/one.sol", "@include \"shared.sol\".\n");
    write_file(LIB "/two.sol", "@include \"shared.sol\".\n");
    write_file(DIR "/diamond.sol",
        "times := #0.\n"
        "@include \"lib/one.sol\".\n"
        "@include \"lib/two.sol\".\n"
        "@include \"lib/shared.sol\".\n");

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    run_file(&vm, &chunk, DIR "/diamond.sol");

    assert(SOL_AS_INT(global(&vm, "times")) == 1);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  a file reached twice is compiled once\n");
}

/* The same rule is what stops a cycle: the second visit finds the file already
   compiled and does nothing, rather than recurring until the stack runs out. */
static void test_a_cycle_ends(void)
{
    write_file(DIR "/left.sol",
        "@include \"right.sol\".\n"
        "left := #1.\n");
    write_file(DIR "/right.sol",
        "@include \"left.sol\".\n"
        "right := #2.\n");

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    run_file(&vm, &chunk, DIR "/left.sol");

    assert(SOL_AS_INT(global(&vm, "left")) == 1);
    assert(SOL_AS_INT(global(&vm, "right")) == 2);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  a cycle of includes ends instead of recurring\n");
}

/* A file that is not there is a compile error naming it, not a silent nothing. */
static void test_a_missing_file_is_an_error(void)
{
    write_file(DIR "/missing.sol", "@include \"nowhere.sol\".\n");

    char output[1024];
    compile_error_of(DIR "/missing.sol", output, sizeof output);

    assert(strstr(output, "cannot read the included file") != NULL);
    assert(strstr(output, "nowhere.sol") != NULL);
    printf("  a missing file is reported where it is named\n");
}

/* An error inside an included file is reported against that file, and the chain
   that reached it is printed after -- otherwise there is no saying how the
   compiler got there. */
static void test_an_error_inside_an_include_names_both_files(void)
{
    write_file(LIB "/broken.sol", "x := #1.\ny := :.\n");
    write_file(DIR "/includes_broken.sol", "@include \"lib/broken.sol\".\n");

    char output[1024];
    compile_error_of(DIR "/includes_broken.sol", output, sizeof output);

    assert(strstr(output, LIB "/broken.sol:2:") != NULL);   /* where it went wrong */
    assert(strstr(output, "... included from " DIR "/includes_broken.sol") != NULL);
    printf("  an error in an included file names the file and the chain\n");
}

/* An include is a directive and compiles a file in at that point, so there is
   nowhere for it to go inside an expression. Better a compile error than a send
   that fails at run time. */
static void test_an_include_must_stand_alone(void)
{
    write_file(DIR "/buried.sol", "x := (@include \"lib/greet.sol\").\n");

    char output[1024];
    compile_error_of(DIR "/buried.sol", output, sizeof output);

    assert(strstr(output, "must stand alone") != NULL);
    printf("  an include buried in an expression is refused\n");
}

/* With no file to be relative to -- the prompt, or a test like this one -- the
   working directory is what an include resolves against. */
static void test_source_without_a_file_resolves_against_the_directory(void)
{
    write_file(LIB "/plain.sol", "plain := #11.\n");

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("@include \"" LIB "/plain.sol\". seen := plain.", &chunk));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "seen")) == 11);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  source with no file of its own includes from the directory\n");
}

/* A directive is `@include`: one token, '@' and all. Which leaves the bare word
   free -- it was never reserved, and now it could not be, since no identifier
   can collide with a token that has to begin with a character an identifier
   cannot contain. */
static void test_include_is_an_ordinary_name_elsewhere(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("box := object:new. box:include := { #5 }. got := box:include.",
                       &chunk));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "got")) == 5);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    printf("  'include' is still an ordinary slot name\n");
}

/* '@' opens a space, and the compiler owns all of it. A name in that space it
   does not know is a mistake now rather than something that might turn out to
   mean something later. */
static void test_an_unknown_directive_is_refused(void)
{
    write_file(DIR "/unknown.sol", "@compile \"lib/greet.sol\".\n");

    char output[1024];
    compile_error_of(DIR "/unknown.sol", output, sizeof output);

    assert(strstr(output, "unknown directive") != NULL);
    assert(strstr(output, "@compile") != NULL);        /* underlined in the source */
    printf("  an unknown directive is refused by name\n");
}

/* The scanner will not make a directive out of a bare '@', for the same reason
   it will not make a symbol out of a bare quote. */
static void test_an_at_sign_needs_a_name(void)
{
    write_file(DIR "/bare_at.sol", "@ \"lib/greet.sol\".\n");

    char output[1024];
    compile_error_of(DIR "/bare_at.sol", output, sizeof output);

    assert(strstr(output, "expected a name after '@'") != NULL);
    printf("  a bare '@' is not a directive\n");
}

/* An include takes a file name and nothing else stands in for one. */
static void test_an_include_needs_a_file_name(void)
{
    write_file(DIR "/nameless.sol", "@include.\n");

    char output[1024];
    compile_error_of(DIR "/nameless.sol", output, sizeof output);

    assert(strstr(output, "needs a file name in quotes") != NULL);
    printf("  an include with no file name is refused\n");
}

/* ---- the search path ---------------------------------------------------- *
 *
 * An include is found beside the file including it, and failing that on the
 * search path. That is C's rule for a quoted include, and it is what lets a
 * shipped library be reached without every program saying where it lives.
 */
#define LIBDIR DIR "/elsewhere"

static bool compile_with_path(const char *path, const SolSearchPath *search,
                              SolChunk *chunk)
{
    char *source = sol_read_file(path);
    assert(source != NULL);

    sol_chunk_init(chunk);
    bool ok = sol_compile_file(source, path, search, chunk);
    free(source);
    return ok;
}

static void test_the_search_path_finds_what_is_not_beside_you(void)
{
    mkdir(LIBDIR, 0777);
    write_file(LIBDIR "/faraway.sol", "faraway := #77.\n");
    write_file(DIR "/needs_faraway.sol", "@include \"faraway.sol\". seen := faraway.\n");

    /* Without it, the file is simply not there. */
    SolChunk chunk;
    assert(compile_with_path(DIR "/needs_faraway.sol", NULL, &chunk) == false);
    sol_chunk_free(&chunk);

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, LIBDIR);

    SolVM vm; sol_vm_init(&vm);
    assert(compile_with_path(DIR "/needs_faraway.sol", &search, &chunk));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 77);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    sol_search_path_free(&search);
    printf("  the search path finds a file that is not beside the includer\n");
}

/* Beside first, path second -- so your own file wins over a library one of the
   same name, which is the whole point of the order. */
static void test_beside_beats_the_search_path(void)
{
    mkdir(LIBDIR, 0777);
    write_file(LIBDIR "/both.sol", "which := \"library\".\n");
    write_file(DIR "/both.sol", "which := \"beside\".\n");
    write_file(DIR "/needs_both.sol", "@include \"both.sol\".\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, LIBDIR);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(compile_with_path(DIR "/needs_both.sol", &search, &chunk));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    SolValue which = global(&vm, "which");
    assert(SOL_IS_STRING(which));
    assert(strcmp(SOL_AS_STRING(which)->chars, "beside") == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    sol_search_path_free(&search);
    printf("  a file beside the includer wins over one on the path\n");
}

/* The first directory holding it wins, so an earlier -I shadows a later one. */
static void test_the_first_directory_wins(void)
{
    mkdir(LIBDIR, 0777);
    mkdir(DIR "/first", 0777);
    write_file(DIR "/first/ranked.sol", "rank := \"first\".\n");
    write_file(LIBDIR "/ranked.sol", "rank := \"second\".\n");
    write_file(DIR "/needs_ranked.sol", "@include \"ranked.sol\".\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, DIR "/first");
    sol_search_path_add(&search, LIBDIR);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(compile_with_path(DIR "/needs_ranked.sol", &search, &chunk));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);
    assert(strcmp(SOL_AS_STRING(global(&vm, "rank"))->chars, "first") == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    sol_search_path_free(&search);
    printf("  the first directory on the path wins\n");
}

/* An absolute name is taken as it stands, so the path is not consulted and a
   library file of the same name cannot be picked up by accident. */
static void test_an_absolute_name_searches_nothing(void)
{
    mkdir(LIBDIR, 0777);
    write_file(LIBDIR "/absolute.sol", "reached := #1.\n");
    write_file(DIR "/needs_absolute.sol", "@include \"/no/such/absolute.sol\".\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, LIBDIR);

    SolChunk chunk;
    assert(compile_with_path(DIR "/needs_absolute.sol", &search, &chunk) == false);

    sol_chunk_free(&chunk);
    sol_search_path_free(&search);
    printf("  an absolute name does not consult the path\n");
}

/* And the error says the path was looked at, so a missing library file does not
   read as a missing local one. */
static void test_not_found_anywhere_says_so(void)
{
    mkdir(LIBDIR, 0777);
    write_file(DIR "/needs_nothing.sol", "@include \"nowhere-at-all.sol\".\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, LIBDIR);

    char output[1024];
    /* compile_error_of uses the pathless entry point, so this repeats its
       plumbing rather than reaching for it. */
    char temp[] = "/tmp/solum-search-err-XXXXXX";
    int fd = mkstemp(temp);
    assert(fd >= 0);
    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    assert(dup2(fd, STDERR_FILENO) >= 0);

    SolChunk chunk;
    bool ok = compile_with_path(DIR "/needs_nothing.sol", &search, &chunk);
    sol_chunk_free(&chunk);

    fflush(stderr);
    assert(dup2(saved, STDERR_FILENO) >= 0);
    close(saved);
    assert(lseek(fd, 0, SEEK_SET) == 0);
    ssize_t got = read(fd, output, sizeof output - 1);
    output[got > 0 ? (size_t)got : 0] = '\0';
    close(fd);
    remove(temp);

    assert(!ok);
    assert(strstr(output, "not on the search path") != NULL);
    sol_search_path_free(&search);
    printf("  a file found nowhere says the path was searched too\n");
}

/* Compiles and answers what went to stderr, which for a warning is the whole of
   what there is to check: the file still compiles, so the return value says
   nothing about whether anything was said. */
static bool compile_capturing_stderr(const char *path, const SolSearchPath *search,
                                     char *output, size_t size)
{
    char temp[] = "/tmp/solum-warn-XXXXXX";
    int fd = mkstemp(temp);
    assert(fd >= 0);
    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    assert(dup2(fd, STDERR_FILENO) >= 0);

    SolChunk chunk;
    bool ok = compile_with_path(path, search, &chunk);
    sol_chunk_free(&chunk);

    fflush(stderr);
    assert(dup2(saved, STDERR_FILENO) >= 0);
    close(saved);
    assert(lseek(fd, 0, SEEK_SET) == 0);
    ssize_t got = read(fd, output, size - 1);
    output[got > 0 ? (size_t)got : 0] = '\0';
    close(fd);
    remove(temp);
    return ok;
}

/* A file that includes a library of its own name finds itself, and since a file
   is compiled once the include then does nothing. The program compiles cleanly
   and fails at run time with an undefined name, a long way from the line that
   caused it -- so the compiler says so where the line is. It is a warning
   rather than an error: shadowing is the rule and stays, and the file is still
   compiled. */
static void test_a_file_including_itself_warns(void)
{
    write_file(LIBDIR "/twin.sol", "fromLibrary := #1.\n");
    write_file(DIR "/twin.sol", "@include \"twin.sol\".\nlocal := #2.\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, LIBDIR);

    char output[1024];
    bool ok = compile_capturing_stderr(DIR "/twin.sol", &search, output, sizeof output);

    assert(ok);                                       /* still compiles */
    assert(strstr(output, "warning:") != NULL);
    assert(strstr(output, "includes itself") != NULL);
    /* And names what it shadowed, which is the file the reader was expecting. */
    assert(strstr(output, "twin.sol") != NULL);
    assert(strstr(output, LIBDIR) != NULL);

    sol_search_path_free(&search);
    printf("  a file including itself is warned about, and names what it shadowed\n");
}

/* With nothing of that name on the path there is nothing to name, and the
   warning still has the useful half. */
static void test_a_lone_self_include_still_warns(void)
{
    write_file(DIR "/only.sol", "@include \"only.sol\".\nx := #1.\n");

    SolSearchPath search;
    sol_search_path_init(&search);

    char output[1024];
    bool ok = compile_capturing_stderr(DIR "/only.sol", &search, output, sizeof output);

    assert(ok);
    assert(strstr(output, "includes itself") != NULL);
    assert(strstr(output, "search path") == NULL);    /* nothing to point at */

    sol_search_path_free(&search);
    printf("  a self-include with no library behind it still says so\n");
}

/* The two shapes that are not mistakes, and must stay silent. A file reached
   twice by different routes is the ordinary reason include-once exists, and two
   files including each other is a cycle it ends on purpose. */
static void test_the_ordinary_repeats_are_silent(void)
{
    write_file(LIBDIR "/base.sol", "base := #1.\n");
    write_file(LIBDIR "/left.sol", "@include \"base.sol\".\n");
    write_file(LIBDIR "/right.sol", "@include \"base.sol\".\n");
    write_file(DIR "/diamond.sol",
        "@include \"left.sol\".\n@include \"right.sol\".\n@include \"base.sol\".\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, LIBDIR);

    char output[1024];
    assert(compile_capturing_stderr(DIR "/diamond.sol", &search, output, sizeof output));
    assert(output[0] == '\0');

    /* And the cycle. */
    write_file(DIR "/ping.sol", "@include \"pong.sol\".\nping := #1.\n");
    write_file(DIR "/pong.sol", "@include \"ping.sol\".\npong := #2.\n");
    assert(compile_capturing_stderr(DIR "/ping.sol", &search, output, sizeof output));
    assert(output[0] == '\0');

    sol_search_path_free(&search);
    printf("  a diamond and a cycle are not mistakes, and say nothing\n");
}

/* The library that ships with the language. It is a file like any other, and
   this is the same bargain the examples struck: it is compiled by the test
   suite, so it cannot quietly stop being valid Solum. */
static void test_the_shipped_library_works(void)
{
    write_file(DIR "/uses_library.sol",
        "@include \"control.sol\".\n"
        "ticks := #0. #3:repeat({ ticks := ticks:add(#1) }).\n"
        "tocks := #0. { tocks := tocks:add(#1) }:repeat(#2).\n"
        "once := #0. { once := once:add(#1) }:doUntil({ true }).\n"
        "counted := array:new. #1:toDo(#3, { n | counted:add(n) }).\n"
        "stepped := array:new. #1:toByDo(#10, #3, { n | stepped:add(n) }).\n"
        "down := array:new. #3:toByDo(#1, #0:sub(#1), { n | down:add(n) }).\n"
        "squares := #4:timesCollect({ n | n:mul(n) }).\n"
        "empty := #5:toDo(#1, { n | n }).\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, "lib");        /* tests run from the repo root */

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(compile_with_path(DIR "/uses_library.sol", &search, &chunk));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "ticks")) == 3);
    assert(SOL_AS_INT(global(&vm, "tocks")) == 2);
    assert(SOL_AS_INT(global(&vm, "once")) == 1);   /* the body runs before the test */
    assert(SOL_AS_ARRAY(global(&vm, "counted"))->count == 3);
    assert(SOL_AS_ARRAY(global(&vm, "stepped"))->count == 4);   /* 1 4 7 10 */
    assert(SOL_AS_ARRAY(global(&vm, "down"))->count == 3);
    assert(SOL_AS_ARRAY(global(&vm, "squares"))->count == 4);
    assert(SOL_AS_INT(SOL_AS_ARRAY(global(&vm, "squares"))->items[3]) == 16);
    assert(SOL_IS_NIL(global(&vm, "empty")));       /* toDo answers nil */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    sol_search_path_free(&search);
    printf("  the shipped library compiles and its loops work\n");
}

/* The JSON library, end to end, and the reason this is here rather than in a
   Solum example: an example checks that a program runs, and this checks what it
   answered. It is also the test that would have caught the `\u` gap being only
   half closed -- reading an escape and building the bytes are two things, and
   the second one is what `asByte` and `asCharacter` (6.12) made possible. */
static void test_the_json_library_reads_and_writes(void)
{
    write_file(DIR "/uses_json.sol",
        "@include \"json.sol\".\n"
        "v := json:read(\"{\\\"a\\\": [1, 2.5, true, null], \\\"b\\\": \\\"x\\\"}\").\n"
        "size := v:size.\n"
        "b := v:at(\"b\").\n"
        "text := v:asJson.\n"
        "again := json:read(text):asJson.\n"
        "same := again:equals(text).\n"
        /* A code point above ASCII, which needed a table before and needs
           arithmetic now, and one above U+FFFF, which arrives as a pair. */
        "acute := json:read(\"\\\"\\\\u00e9\\\"\").\n"
        "acuteSize := acute:size.\n"
        "raw := json:read(\"\\\"\xc3\xa9\\\"\").\n"
        "escapedMatchesRaw := acute:equals(raw).\n"
        "pair := json:read(\"\\\"\\\\ud83d\\\\ude00\\\"\").\n"
        "pairSize := pair:size.\n"
        /* And out again: a control byte becomes \u00XX, which also needs the
           number of a byte. */
        "control := array:of(#0:asCharacter:concat(\"x\")):asJson.\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, "lib");

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(compile_with_path(DIR "/uses_json.sol", &search, &chunk));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "size")) == 2);
    assert(SOL_IS_STRING(global(&vm, "b")));
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);

    /* Two bytes for é, four for the emoji: the counts are the point, since a
       wrong encoding would still be a string and still compare equal to itself. */
    assert(SOL_AS_INT(global(&vm, "acuteSize")) == 2);
    assert(SOL_AS_INT(global(&vm, "pairSize")) == 4);
    /* The escaped form and the raw UTF-8 form are the same string. */
    assert(SOL_AS_BOOL(global(&vm, "escapedMatchesRaw")) == true);

    const SolString *control = SOL_AS_STRING(global(&vm, "control"));
    assert(strstr(control->chars, "\\u0000") != NULL);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    sol_search_path_free(&search);
    printf("  the json library reads and writes, escapes included\n");
}

/* Whether a value is exactly this text. test_convert.c has the same three
   lines; they are three lines. */
static bool is_text(SolValue value, const char *expected)
{
    if (!SOL_IS_STRING(value)) return false;
    const SolString *s = SOL_AS_STRING(value);
    return s->length == (int)strlen(expected) &&
           memcmp(s->chars, expected, (size_t)s->length) == 0;
}

/* The HTML library, end to end. The assertion that matters is the last one: the
   reader is built on a stack rather than on recursion, so the frame limit that
   stops a recursive-descent parser at 28 levels of nesting (ROADMAP 3.5) does
   not reach it. A thousand levels here is not a stress test, it is the claim. */
static void test_the_html_library_reads_and_recovers(void)
{
    write_file(DIR "/uses_html.sol",
        "@include \"html.sol\".\n"
        /* Implied end tags, an entity, a void element, and a stray end tag --
           the tree survives all four and the complaint is kept. */
        "page := html:read(\"<ul><li>one<li>two</ul><p>a &amp; b<br>c</i>\").\n"
        "items := page:findAll(\"li\"):size.\n"
        "first := page:find(\"li\"):text.\n"
        "text := page:text.\n"
        "complaints := html:complaints:size.\n"
        "stray := html:complaints:at(#1).\n"
        /* A `<` that starts no tag is text, and a script's contents are not
           markup -- the two ways a parser swallows a page. */
        "raw := html:read(\"<script>if (a < b) { x }</script><p>after\"):text.\n"
        "bare := html:read(\"5 < 6\"):text.\n"
        /* Attributes in all three spellings, and a missing one answering nil. */
        "tag := html:read(\"<a href=x title='y' hidden>z</a>\"):find(\"a\").\n"
        "href := tag:attribute(\"href\").\n"
        "hidden := tag:attribute(\"hidden\").\n"
        "absent := tag:attribute(\"nope\"):isNil.\n"
        /* Deep, and then walked back down. Both are iterative. */
        "deep := \"\". i := #0.\n"
        "{ i:lessThan(#1000) }:whileTrue({ deep := deep:concat(\"<div>\").\n"
        "    i := i:add(#1) }).\n"
        "tree := html:read(deep:concat(\"bottom\")).\n"
        "divs := tree:findAll(\"div\"):size.\n"
        "bottom := tree:text.\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, "lib");

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(compile_with_path(DIR "/uses_html.sol", &search, &chunk));
    assert(sol_vm_run(&vm, &chunk) == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "items")) == 2);      /* <li>one<li>two */
    assert(is_text(global(&vm, "first"), "one"));
    assert(is_text(global(&vm, "text"), "onetwoa & bc"));
    assert(SOL_AS_INT(global(&vm, "complaints")) == 2); /* stray </i>, unclosed <p> */
    assert(strstr(SOL_AS_STRING(global(&vm, "stray"))->chars, "closes nothing") != NULL);

    assert(is_text(global(&vm, "raw"), "if (a < b) { x }after"));
    assert(is_text(global(&vm, "bare"), "5 < 6"));

    assert(is_text(global(&vm, "href"), "x"));
    assert(is_text(global(&vm, "hidden"), ""));         /* present, no value */
    assert(SOL_AS_BOOL(global(&vm, "absent")) == true);

    /* The claim: a thousand levels, built and walked, with 62 frames. */
    assert(SOL_AS_INT(global(&vm, "divs")) == 1000);
    assert(is_text(global(&vm, "bottom"), "bottom"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    sol_search_path_free(&search);
    printf("  the html library reads, recovers, and nests past the frame limit\n");
}

/* A library binds names and prints nothing. One that announced itself when you
   included it would be a poor guest, and this is the check that it does not. */
static void test_the_library_is_silent_when_included(void)
{
    write_file(DIR "/just_include.sol", "@include \"control.sol\".\n");

    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add(&search, "lib");

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(compile_with_path(DIR "/just_include.sol", &search, &chunk));

    char temp[] = "/tmp/solum-library-out-XXXXXX";
    int fd = mkstemp(temp);
    assert(fd >= 0);
    fflush(stdout);
    int saved = dup(STDOUT_FILENO);
    assert(dup2(fd, STDOUT_FILENO) >= 0);

    SolResult result = sol_vm_run(&vm, &chunk);

    fflush(stdout);
    assert(dup2(saved, STDOUT_FILENO) >= 0);
    close(saved);
    assert(lseek(fd, 0, SEEK_END) == 0);        /* it wrote nothing at all */
    close(fd);
    remove(temp);

    assert(result == SOL_OK);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
    sol_search_path_free(&search);
    printf("  including the library prints nothing\n");
}

int main(void)
{
    make_directories();

    test_an_include_brings_in_definitions();
    test_a_file_is_found_beside_the_one_including_it();
    test_a_file_is_compiled_once();
    test_a_cycle_ends();
    test_a_missing_file_is_an_error();
    test_an_error_inside_an_include_names_both_files();
    test_an_include_must_stand_alone();
    test_source_without_a_file_resolves_against_the_directory();
    test_include_is_an_ordinary_name_elsewhere();
    test_an_unknown_directive_is_refused();
    test_an_at_sign_needs_a_name();
    test_an_include_needs_a_file_name();
    test_the_search_path_finds_what_is_not_beside_you();
    test_beside_beats_the_search_path();
    test_the_first_directory_wins();
    test_an_absolute_name_searches_nothing();
    test_not_found_anywhere_says_so();
    test_a_file_including_itself_warns();
    test_a_lone_self_include_still_warns();
    test_the_ordinary_repeats_are_silent();
    test_the_shipped_library_works();
    test_the_json_library_reads_and_writes();
    test_the_html_library_reads_and_recovers();
    test_the_library_is_silent_when_included();

    printf("test_include: ok\n");
    return 0;
}
