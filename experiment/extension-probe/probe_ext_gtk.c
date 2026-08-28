/* probe_ext_gtk.c -- the half a checksum cannot test.
 *
 * A window is not a hash. GTK owns the main loop, and a signal handler is
 * foreign code calling *back* into the VM with a Solum block it has been
 * holding since before the last collection. Three questions, and the probe
 * exists to answer them rather than to be a design:
 *
 *   1. does sol_vm_call_block work from inside a GLib source callback?
 *   2. is a block held only as `gpointer user_data` visible to the collector?
 *   3. what happens to an error raised inside a callback, with GTK's C frames
 *      between the raise and anything that could unwind to?
 */
#include <glib.h>
#include <gtk/gtk.h>

#include "solum/embed.h"
#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"

static GMainLoop *loop;

/* The answer to question 2, once the probe had asked it: somewhere the tracer
   already looks. An array on a slot of the extension's own global, which is a
   slot of the root, which mark_roots walks. Nothing clever -- the point is that
   there is no way for an extension to do this without one, and no supported
   call that offers one. */
static SolArray *rooted;

typedef struct {
    SolVM   *vm;
    SolValue block;
} Callback;

static gboolean on_tick(gpointer data)
{
    Callback *cb = data;
    SolValue answer = sol_vm_call_block(cb->vm, cb->block, NULL, 0);
    if (cb->vm->had_error) {
        g_printerr("probe: callback failed: %s\n", sol_vm_error_message(cb->vm));
        g_main_loop_quit(loop);
        return G_SOURCE_REMOVE;
    }
    if (answer.type == SOL_BOOL && answer.as.boolean) return G_SOURCE_CONTINUE;
    g_main_loop_quit(loop);
    return G_SOURCE_REMOVE;
}

/* gtk:every(#ms, { ... }) -- run the block on a timer until it answers false. */
static SolValue prim_every(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 2 || args[0].type != SOL_INT || args[1].type != SOL_BLOCK) {
        sol_vm_runtime_error(vm, "every expects an integer and a block");
        return SOL_NIL_VAL;
    }
    Callback *cb = g_new(Callback, 1);
    cb->vm = vm;
    cb->block = args[1];          /* the collector cannot see this */
#ifdef PROBE_ROOTED
    sol_array_add(vm, rooted, args[1]);
#endif
    g_timeout_add((guint)args[0].as.integer, on_tick, cb);
    return SOL_NIL_VAL;
}

/* gtk:stress -- turn on collect-on-every-allocation, to make question 2 loud. */
static SolValue prim_stress(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    vm->gc_stress = true;
    return SOL_NIL_VAL;
}

static SolValue prim_run(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(loop);          /* GTK owns the program from here */
    g_main_loop_unref(loop);
    loop = NULL;
    /* Whatever a callback left set is still set. */
    return vm->had_error ? SOL_NIL_VAL : SOL_NIL_VAL;
}

/* gtk:window("title") -- a real window, to prove the toolkit half works. */
static SolValue prim_window(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_STRING) {
        sol_vm_runtime_error(vm, "window expects a string");
        return SOL_NIL_VAL;
    }
    if (!gtk_init_check()) {
        sol_vm_runtime_error(vm, "no display");
        return SOL_NIL_VAL;
    }
    GtkWidget *w = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(w), args[0].as.string->chars);
    gtk_window_set_default_size(GTK_WINDOW(w), 320, 200);
    gtk_widget_set_visible(w, TRUE);
    /* Nothing here gives the window back to Solum: there is no value type that
       could carry it, which is question 4 and the reason the foreign cell in
       ideas.md is the only real design decision. */
    return SOL_NIL_VAL;
}

/* Does the toolkit come up at all from inside a loaded bundle? Widgets are
   built and never presented: the question is gtk_init, not focus. */
static SolValue prim_probe_display(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)vm; (void)self; (void)args; (void)argc;
    if (!gtk_init_check()) return SOL_BOOL_VAL(false);
    GtkWidget *w = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(w), "probe");
    gtk_window_set_default_size(GTK_WINDOW(w), 320, 200);
    GtkWidget *label = gtk_label_new("built, not shown");
    gtk_window_set_child(GTK_WINDOW(w), label);
    return SOL_BOOL_VAL(GTK_IS_WINDOW(w) && GTK_IS_LABEL(label));
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != 1) return -1;
    SolObject *gtk = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, gtk, "every",  prim_every);
    sol_object_define_primitive(vm, gtk, "run",    prim_run);
    sol_object_define_primitive(vm, gtk, "stress", prim_stress);
    sol_object_define_primitive(vm, gtk, "window", prim_window);
    sol_object_define_primitive(vm, gtk, "probeDisplay", prim_probe_display);
    rooted = sol_array_new(vm, 4);
    sol_object_define(vm, gtk, "handlers", SOL_ARRAY_VAL(rooted));
    sol_vm_set_global(vm, "gtk", SOL_OBJ_VAL(gtk));
    return 0;
}
