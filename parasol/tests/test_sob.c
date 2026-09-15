/* test_sob.c -- `parasol --sob`, which runs solas rather than linking it.
 *
 * The other files here link libparasol.a and call in. This one runs the
 * binary as a shell would, because what `--sob` does is run *another* binary,
 * and the things that can go wrong are all at that boundary: which solas is
 * run, what it is handed, where the two files land, and whose status comes
 * back. None of that is reachable from inside the library, and a test that
 * faked the fork would be testing the fake.
 *
 * `PARASOL_BIN` names the directory holding parasol, solas and solvm; the
 * Makefile sets it to $(BIN). Absent, `../bin` is assumed, which is where
 * `make` puts them when this directory is Solveig's parasol/. */
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static int failures = 0;
static int checks = 0;
static char directory[256];
static const char *bin;

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

static bool exists(const char *name)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s", directory, name);
    struct stat st;
    return stat(path, &st) == 0;
}

/* Whole files, for the one comparison that matters here: that the bytecode
   the driver wrote is the bytecode solas writes. */
static char *slurp(const char *name, size_t *size)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s", directory, name);
    FILE *file = fopen(path, "rb");
    if (file == NULL) return NULL;
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *text = malloc((size_t)length + 1);
    if (fread(text, 1, (size_t)length, file) != (size_t)length) { free(text); text = NULL; }
    else text[length] = '\0';
    fclose(file);
    if (size != NULL) *size = (size_t)length;
    return text;
}

/* Runs `command` in the temporary directory, with `bin` on PATH and nothing
   else, and answers its exit status; what it wrote to both streams lands in
   `out`. PATH is *only* `bin` so that the fallback case below can take it
   away and be sure nothing else supplies a solas. */
static int run(const char *command, char *out, size_t size)
{
    char line[2048];
    snprintf(line, sizeof line, "cd '%s' && PATH='%s' %s 2>&1",
             directory, bin, command);
    out[0] = '\0';
    FILE *pipe = popen(line, "r");
    if (pipe == NULL) { perror("popen"); exit(1); }
    size_t filled = 0, n;
    while (filled + 1 < size &&
           (n = fread(out + filled, 1, size - filled - 1, pipe)) > 0)
        filled += n;
    out[filled] = '\0';
    int status = pclose(pipe);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static void check(const char *label, bool ok, const char *saw)
{
    checks++;
    if (ok) return;
    failures++;
    printf("  FAIL %s\n", label);
    if (saw != NULL && saw[0] != '\0') printf("    saw: %s", saw);
}

int main(void)
{
    char template[] = "/tmp/parasol-sob-XXXXXX";
    if (mkdtemp(template) == NULL) { perror("mkdtemp"); return 1; }
    snprintf(directory, sizeof directory, "%s", template);

    bin = getenv("PARASOL_BIN");
    if (bin == NULL || bin[0] == '\0') bin = "../bin";
    char absolute[512];
    if (bin[0] != '/') {
        char cwd[256];
        if (getcwd(cwd, sizeof cwd) == NULL) { perror("getcwd"); return 1; }
        snprintf(absolute, sizeof absolute, "%s/%s", cwd, bin);
        bin = absolute;
    }

    char out[8192];
    int status;

    /* The plain case: both files, and the .sob is solas's own byte for byte.
       The comparison is against solas run on the very .sol the driver wrote,
       so the only thing it can differ in is what the driver handed over. */
    write_file("v.psol", "@infix + 60 add.\n(#2 + #3):print.\n");
    status = run("parasol --sob v.psol", out, sizeof out);
    check("--sob exits 0", status == 0, out);
    check("--sob writes the .sol", exists("v.sol"), NULL);
    check("--sob writes the .sob", exists("v.sob"), NULL);
    status = run("solas v.sol -o two.sob", out, sizeof out);
    check("solas accepts the .sol", status == 0, out);
    {
        size_t a_size = 0, b_size = 0;
        char *a = slurp("v.sob", &a_size);
        char *b = slurp("two.sob", &b_size);
        check("the .sob is what solas writes",
              a != NULL && b != NULL && a_size == b_size &&
              memcmp(a, b, a_size) == 0, NULL);
        free(a);
        free(b);
    }
    status = run("solvm v.sob", out, sizeof out);
    check("and it runs", status == 0 && strcmp(out, "#5\n") == 0, out);

    /* -o names the .sob, and the .sol goes beside it, not beside the source;
       the map, asked for, goes beside the .sol. */
    {
        char path[512];
        snprintf(path, sizeof path, "%s/out", directory);
        mkdir(path, 0700);
    }
    status = run("parasol --sob --map v.psol -o out/w.sob", out, sizeof out);
    check("-o with --sob exits 0", status == 0, out);
    check("-o names the .sob", exists("out/w.sob"), NULL);
    check("the .sol is beside the .sob", exists("out/w.sol"), NULL);
    check("the map is beside the .sol", exists("out/w.sol.map"), NULL);
    check("nothing lands beside the source", !exists("v.sol.map"), NULL);

    /* -I reaches both compilers: the dialect through @use, the generated
       library through @include. One directory, because in every program so
       far they are the same directory. */
    {
        char path[512];
        snprintf(path, sizeof path, "%s/lib", directory);
        mkdir(path, 0700);
    }
    write_file("lib/ops.psol", "@infix * 70 mul.\n");
    write_file("lib/seven.sol", "seven := #7.\n");
    write_file("both.psol",
               "@use \"ops.psol\".\n@include \"seven.sol\".\n(seven * #6):print.\n");
    status = run("parasol --sob -I lib both.psol", out, sizeof out);
    check("-I reaches @use and @include", status == 0, out);
    status = run("solvm both.sob", out, sizeof out);
    check("and the program runs", status == 0 && strcmp(out, "#42\n") == 0, out);

    /* A Parasol error stops before solas: 65, and no file of either kind. */
    write_file("bad.psol", "@infix + 60 add.\n(#1 + ).\n");
    status = run("parasol --sob bad.psol", out, sizeof out);
    check("a Parasol error is 65", status == 65, out);
    check("and writes no .sol", !exists("bad.sol"), NULL);
    check("and writes no .sob", !exists("bad.sob"), NULL);

    /* A Solveig error is solas's: its status, its message naming the .sol,
       and the .sol left where the map can be read against it. */
    write_file("inc.psol", "@include \"missing.sol\".\n#1:print.\n");
    status = run("parasol --sob inc.psol", out, sizeof out);
    check("a solas error is solas's status", status == 65, out);
    check("and solas's message, naming the .sol",
          strstr(out, "inc.sol") != NULL && strstr(out, "solas") != NULL, out);
    check("the .sol is kept", exists("inc.sol"), NULL);
    check("and there is no .sob", !exists("inc.sob"), NULL);

    /* --dump is solas's flag, passed through; alone it is a usage error. */
    status = run("parasol --dump v.psol", out, sizeof out);
    check("--dump without --sob is 64", status == 64, out);
    status = run("parasol --sob --dump v.psol", out, sizeof out);
    check("--dump with --sob disassembles",
          status == 0 && strstr(out, "SEND") != NULL, out);

    /* --tree still writes nothing, whatever else was asked for. */
    remove_file("v.sob");
    remove_file("v.sol");
    status = run("parasol --sob --tree v.psol", out, sizeof out);
    check("--tree wins over --sob", status == 0 && !exists("v.sob") &&
          !exists("v.sol"), out);

    /* Which solas. Beside the binary first: a copy of parasol somewhere with
       no solas beside it, and PATH taken away, finds none and says so with
       127; give PATH back and it finds solas there. The copy is the case of
       a parasol reached off PATH, whose argv[0] names no directory. */
    {
        char line[1024];
        snprintf(line, sizeof line, "cp '%s/parasol' '%s/p'", bin, directory);
        if (system(line) != 0) { perror("cp"); return 1; }
    }
    status = run("PATH=/nonexistent ./p --sob v.psol", out, sizeof out);
    check("no solas anywhere is 127", status == 127, out);
    check("and says so", strstr(out, "cannot run") != NULL, out);
    check("and writes no .sob", !exists("v.sob"), NULL);
    status = run("./p --sob v.psol", out, sizeof out);
    check("solas on PATH is found", status == 0 && exists("v.sob"), out);

    printf("%d checks, %d failed\n", checks, failures);

    const char *files[] = { "v.psol", "v.sol", "v.sob", "two.sob", "out/w.sob",
                            "out/w.sol", "out/w.sol.map", "lib/ops.psol",
                            "lib/seven.sol", "both.psol", "both.sol", "both.sob",
                            "bad.psol", "inc.psol", "inc.sol", "p" };
    for (size_t i = 0; i < sizeof files / sizeof *files; i++)
        remove_file(files[i]);
    {
        char path[512];
        snprintf(path, sizeof path, "%s/out", directory);
        rmdir(path);
        snprintf(path, sizeof path, "%s/lib", directory);
        rmdir(path);
    }
    rmdir(directory);

    return failures == 0 ? 0 : 1;
}
