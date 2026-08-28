/* ext_sdl.c -- SDL2, standing in for the graphics half of a game.
 *
 * The point of this file in the demo is everything it does NOT contain: no
 * mention of fastmath, no mention of net, no arrangement with either, and no
 * knowledge of whether they were loaded. Three bundles meet only at the root
 * object, the way `system` and `array` do.
 */
#include <SDL.h>

#include "solum/embed.h"
#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"

static SDL_Window   *window;
static SDL_Renderer *renderer;

/* The block a frame runs. Kept in an array hung on the extension's own global,
   because a block reachable only from C is swept -- which the probe found the
   hard way, and which is the same four lines in every extension that has a
   callback. That repetition is the argument for putting it in the VM. */
static SolArray *rooted;

static SolValue prim_open(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 3 || args[0].type != SOL_STRING ||
        args[1].type != SOL_INT || args[2].type != SOL_INT) {
        sol_vm_runtime_error(vm, "open expects a title and two integers");
        return SOL_NIL_VAL;
    }
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        sol_vm_runtime_error(vm, "sdl: %s", SDL_GetError());
        return SOL_NIL_VAL;
    }
    window = SDL_CreateWindow(args[0].as.string->chars,
                              SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                              (int)args[1].as.integer, (int)args[2].as.integer, 0);
    if (window == NULL) {
        sol_vm_runtime_error(vm, "sdl: %s", SDL_GetError());
        return SOL_NIL_VAL;
    }
    renderer = SDL_CreateRenderer(window, -1, 0);
    return SOL_BOOL_VAL(renderer != NULL);
}

/* sdl:each({ ... }) -- run the block once a frame until it answers false, or
   until the window is closed. This is the foreign main loop: SDL owns the
   program and calls back into the VM. */
static SolValue prim_each(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_BLOCK) {
        sol_vm_runtime_error(vm, "each expects a block");
        return SOL_NIL_VAL;
    }
    sol_array_add(vm, rooted, args[0]);

    for (;;) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) return SOL_NIL_VAL;
        }

        SDL_SetRenderDrawColor(renderer, 20, 20, 30, 255);
        SDL_RenderClear(renderer);
        SDL_RenderPresent(renderer);

        SolValue answer = sol_vm_call_block(vm, args[0], NULL, 0);

        /* The rule the probe found, and the one extend.h has to state: a
           limit-stop sets this, and a loop that does not look keeps calling
           into a machine that has already been stopped. */
        if (vm->had_error) return SOL_NIL_VAL;
        if (!(answer.type == SOL_BOOL && answer.as.boolean)) return SOL_NIL_VAL;

        SDL_Delay(16);
    }
}

static SolValue prim_close(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)vm; (void)self; (void)args; (void)argc;
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
    renderer = NULL; window = NULL;
    return SOL_NIL_VAL;
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != 1) return -1;
    SolObject *sdl = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, sdl, "open",  prim_open);
    sol_object_define_primitive(vm, sdl, "each",  prim_each);
    sol_object_define_primitive(vm, sdl, "close", prim_close);
    rooted = sol_array_new(vm, 4);
    sol_object_define(vm, sdl, "handlers", SOL_ARRAY_VAL(rooted));
    sol_vm_set_global(vm, "sdl", SOL_OBJ_VAL(sdl));
    return 0;
}
