/* host.c -- a program that holds a SolVM and runs scripts through it.
 *
 *     make embed && ./bin/solhost
 *     ./bin/solhost programs/serve.sol
 *
 * Not a component and not a feature. `solas`, `solvm`, `solis` and `solid` are
 * each a main.c linked against build/libsol.a; so is this. The difference is
 * that they *are* the interpreter and this one *contains* it -- a larger
 * program that runs somebody else's scripts on its own behalf, which is the
 * case ROADMAP 6.32 is about and which nothing in this repository had ever
 * done.
 *
 * It exists to find out whether the interface 6.32 assumes exists actually
 * does. The shape is the webserver from that entry with the sockets taken out:
 * compile one script once, run it many times -- once per request -- each run
 * under its own allowance, and see what comes back.
 *
 * What it set out to test, and what it found, is at the bottom under "what this
 * found". docs/embedding.md is the same list written for a reader rather than
 * for whoever maintains this file.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/embed.h"

/* ------------------------------------------------------------------------ *
 * The requests
 *
 * A path and a query string, which is what a webserver would have parsed out
 * of the request line before handing anything to a handler. The last two are
 * the ones worth having: one that is trying to become code, and one that is
 * merely enormous.
 */

typedef struct {
    const char *what;             /* what this request is here to show */
    const char *path;
    const char *query;
    uint64_t    steps;            /* 0 for no limit */
    size_t      memory;
} Request;

static const Request requests[] = {
    { "the index",        "/",            "",              200000, 8u << 20 },
    { "one note",         "/note/limits", "",              200000, 8u << 20 },
    { "a search",         "/search",      "q=limit",       200000, 8u << 20 },
    { "a script tag",     "/search",      "q=%3Cscript%3E", 200000, 8u << 20 },
    { "a traversal",      "/note/..",     "",              200000, 8u << 20 },
    { "too little rope",  "/search",      "q=limit",          300, 8u << 20 },
    { "too little room",  "/",            "",              200000,   12u << 10 },
};
#define REQUEST_COUNT (sizeof requests / sizeof requests[0])

static const char *result_name(SolResult r)
{
    switch (r) {
    case SOL_OK:            return "ok";
    case SOL_EXIT:          return "exit";
    case SOL_STOPPED:       return "stopped";
    case SOL_RUNTIME_ERROR: return "failed";
    case SOL_COMPILE_ERROR: return "would not compile";
    }
    return "?";
}

/* ------------------------------------------------------------------------ *
 * One request
 *
 * A fresh VM each time, which is the first thing this had to decide and is
 * covered under "what this found". The chunk is compiled once by the caller and
 * handed in, so the compiler runs once however many requests arrive -- which is
 * the whole reason a host would rather hold the machine than shell out to
 * `solvm`.
 *
 * One chunk serves every machine because `sol_vm_run` resolves its names to
 * whichever VM is about to run it, every time. A host does nothing to arrange
 * that -- which is worth saying because this file used to call
 * `sol_vm_intern_chunk` itself and claim it was required. It never was.
 */
static SolResult serve_one(SolChunk *chunk, const Request *request, int *status)
{
    /* CGI hands a handler its request through the environment, and that is
       genuinely how a webserver does it -- so this is not a shortcut. It is
       also the only route in that this host has: see the findings. */
    setenv("PATH_INFO", request->path, 1);
    setenv("QUERY_STRING", request->query, 1);

    SolVM vm;
    sol_vm_init(&vm);

    /* Before it runs, and from C, which 6.32 says is the requirement: if the
       mechanism is argv parsing then the case that asked for it cannot use it.
       For limits that requirement is met. */
    sol_vm_set_step_limit(&vm, request->steps);
    sol_vm_set_memory_limit(&vm, request->memory);

    SolResult result = sol_vm_run(&vm, chunk);
    *status = vm.exit_code;                 /* read before the VM goes away */

    sol_vm_free(&vm);
    return result;
}

/* ------------------------------------------------------------------------ *
 * Text in, run, text out
 *
 * The whole of what a host and a script have to say to each other, and the half
 * that had no front door when this file was written. It has one now:
 * `sol_vm_set_global_text` before the run, `sol_vm_global_text` after, and the
 * text is on the heap so it outlives the machine that made it.
 *
 * What the interface cannot supply is the *name*. This side says "request" and
 * "answer"; the script has to say the same, and nothing checks that they do.
 * That is the weakest joint in embedding and is written down as such rather
 * than papered over.
 */
static char *evaluate(const char *source, const char *name, const char *request)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    if (!sol_compile_source(source, name, &chunk)) {
        sol_chunk_free(&chunk);
        return NULL;
    }

    SolVM vm;
    sol_vm_init(&vm);
    sol_vm_set_step_limit(&vm, 100000);
    sol_vm_set_memory_limit(&vm, 8u << 20);

    /* A failure here is this host's to report, in this host's words, once. */
    sol_vm_set_error_reporting(&vm, false);
    if (request != NULL) sol_vm_set_global_text(&vm, "request", request);

    char *out = NULL;
    if (sol_vm_run(&vm, &chunk) == SOL_OK) out = sol_vm_global_text(&vm, "answer");
    else fprintf(stderr, "solhost: %s\n", sol_vm_error_message(&vm));

    sol_vm_free(&vm);

    /* And *then* the chunk, not before: blocks made while it ran point into it.
       ROADMAP 3.6 -- freeing these the other way round is undefined and nothing
       detects it. A host is the second thing to meet that, after the tests. */
    sol_chunk_free(&chunk);
    return out;
}

/* ------------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "programs/serve.sol";

    char *source = sol_read_file(path);
    if (source == NULL) {
        fprintf(stderr, "solhost: cannot read '%s'\n", path);
        return 66;
    }

    /* The search path, so a script may `@include "json.sol"` and find the
       shipped library, exactly as `solas` arranges it. A host that skipped this
       would be offering a smaller language than the one documented. */
    SolSearchPath search;
    sol_search_path_init(&search);
    sol_search_path_add_defaults(&search, argv[0]);

    SolChunk chunk;
    sol_chunk_init(&chunk);
    if (!sol_compile_file(source, path, &search, &chunk)) {
        fprintf(stderr, "solhost: '%s' would not compile\n", path);
        free(source);
        sol_chunk_free(&chunk);
        sol_search_path_free(&search);
        return 65;
    }
    free(source);
    sol_search_path_free(&search);

    printf("solhost %s -- %s, compiled once, run %zu times\n",
           SOLUM_VERSION, path, REQUEST_COUNT);

    /* Each request's response goes to stdout, because that is the only place it
       can go: `display` writes there and there is no other way out of a run. A
       webserver wants the page as a *value* and this host cannot have one, so
       what follows is the script talking to the terminal over the host's
       shoulder rather than answering it. That is the finding, and printing a
       banner per request is the best a host can do about it. */
    SolResult results[REQUEST_COUNT];
    int statuses[REQUEST_COUNT];
    for (size_t i = 0; i < REQUEST_COUNT; i++) {
        printf("\n==== %s: %s%s%s\n", requests[i].what, requests[i].path,
               requests[i].query[0] != '\0' ? "?" : "", requests[i].query);
        fflush(stdout);
        results[i] = serve_one(&chunk, &requests[i], &statuses[i]);
    }

    printf("\n  %-18s %-8s %-9s %s\n", "request", "steps", "memory", "result");
    printf("  %-18s %-8s %-9s %s\n",
           "------------------", "--------", "---------", "------");
    for (size_t i = 0; i < REQUEST_COUNT; i++) {
        char memory[16];
        snprintf(memory, sizeof memory, "%zuK", requests[i].memory / 1024);
        printf("  %-18s %-8llu %-9s %s\n",
               requests[i].what,
               (unsigned long long)requests[i].steps, memory,
               result_name(results[i]));
    }

    sol_chunk_free(&chunk);

    /* The other direction, on a script small enough to read: a value handed in
       by name, and the answer taken back out as text that outlives the VM. */
    printf("\n  text in, run, text out:\n");
    static const char *snippet =
        "answer := request:split(\",\")"
        ":collect({ w | w:trim:asUppercase }):join(\" | \").\n";
    char *answer = evaluate(snippet, "<host>", "one, two, three");
    printf("    \"one, two, three\" -> %s\n", answer != NULL ? answer : "(nothing)");
    free(answer);

    return 0;
}

/* ------------------------------------------------------------------------ *
 * What this found
 *
 * Written after running it, and the predictions it was built to test are in the
 * commit that added it, so they cannot be fitted afterwards.
 *
 *   1. **Compile once, run many works, and the allowance really is per run.**
 *      `sol_vm_run` resets `steps_remaining` from `step_limit`, which was
 *      written for exactly this and had never had a second run to prove it.
 *      Seven requests through one chunk, each with its own budget, and the two
 *      deliberately starved ones stop while the five before them do not. The
 *      reasoning recorded in vm.h -- "a server handing one machine a request
 *      and then another means each of them to have the whole of it" -- is now
 *      something that has happened rather than something intended.
 *
 *   2. **`sol_vm_intern_chunk` is load-bearing and undocumented as such.** A
 *      chunk's names are interned against the VM that runs it, so a second VM
 *      needs them re-resolved. `sol_vm_run` does not do it and the header says
 *      only that a front end should call it "before a chunk runs". A host
 *      reusing a chunk across VMs and not knowing that is reading another
 *      machine's name table.
 *
 *   3. **There was no route for the answer**, which was the finding that
 *      mattered most and was predicted. A script's output goes to stdout,
 *      because `display` writes there and nothing else existed, so the run's
 *      product arrived somewhere the host could not pick it up.
 *
 *      There is one now: `sol_vm_set_global_text` before the run and
 *      `sol_vm_global_text` after, in solum/embed.h, which name the three
 *      internal calls this file used to assemble by hand. What they still
 *      cannot supply is the *name* -- this side says "request" and "answer",
 *      the script has to agree, and nothing checks that it does. `serve.sol`
 *      stays on the environment because CGI genuinely works that way; the
 *      snippet at the bottom of `main` is the direct route.
 *
 *   4. **A fresh VM per request is the only safe choice today**, and it is not
 *      free. Globals are one flat namespace and nothing unbinds them, so a
 *      second request on a reused VM sees the first one's names. That is the
 *      same flatness `@include` relies on, seen from the side where it hurts.
 *      Discarding the VM discards the interned names and the built-in classes
 *      with it, so every request pays to rebuild them.
 *
 *   5. **ROADMAP 3.6 has its second victim, as predicted.** A caller-owned
 *      chunk must outlive the blocks defined in it, so `sol_chunk_free` comes
 *      after `sol_vm_free` and not before. The entry says the hazard bites code
 *      mixing caller-owned chunks with a long-lived VM, "which today is the
 *      test suite". It is a host as well, and a host is the case that will meet
 *      it in somebody else's program.
 *
 * So 6.32's aside -- that deciding it is also deciding to have an embedding
 * interface -- is right, and understated. The pieces exist and compose; what is
 * missing is that nothing says which of them a host may rely on, and two of the
 * five things above are ordering rules you find out by crashing.
 */
