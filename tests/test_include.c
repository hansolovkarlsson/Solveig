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

    printf("test_include: ok\n");
    return 0;
}
