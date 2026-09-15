/* tree.h -- the tree every Parasol program becomes.
 *
 * Parasol owns this rather than borrowing Solveig's, because Solveig does not
 * have one: `sol_compile` runs the parser straight into the emitter, one pass,
 * no tree in between. That is a fine shape for a compiler with fixed syntax and
 * the wrong one for a compiler whose syntax arrives with the file, so the tree
 * is here and Solveig stays as it is.
 *
 * Three fields are on every node from the first commit and are carried by
 * nothing yet. They are here now because each of them is impossible to add
 * later without touching every constructor and every rewrite in the compiler:
 *
 *   span           where in the *surface text* this came from. Set on every
 *                  node, including nodes an expansion will one day build, which
 *                  inherit the span of the form that caused them.
 *
 *   introduced_by  NULL for a node the programmer wrote. For a node some
 *                  expansion produced, the form that produced it -- so an error
 *                  can say "in the expansion of `unless`, from here" instead of
 *                  pointing at code nobody has read.
 *
 *   scope          the hygiene anchor. Binding as sets of scopes (Flatt, 2016)
 *                  is the intended answer, and a set is what this becomes: an
 *                  index into a scope table rather than the bare 0 it holds
 *                  today. Nothing reads it in 0.1.0. The field is here so that
 *                  adding an expander is a change to the expander.
 *
 * A tree with none of the three is a tree that has to be rebuilt to get them,
 * which is the mistake this file is written to avoid making. */
#ifndef PARASOL_TREE_H
#define PARASOL_TREE_H

#include <stdio.h>

#include "parasol/source.h"

typedef enum {
    PARASOL_NODE_INTEGER,    /* text is the literal as written, tag and all     */
    PARASOL_NODE_FLOAT,
    PARASOL_NODE_STRING,     /* text is the contents, escapes not yet undone    */
    PARASOL_NODE_SYMBOL,     /* text is the name, without the quote             */
    PARASOL_NODE_NAME,       /* an identifier in expression position            */

    PARASOL_NODE_SEND,       /* text is the selector; [0] is the receiver, the
                            rest are arguments                              */
    PARASOL_NODE_ASSIGN,     /* [0] is the target (NAME or a nullary SEND),
                            [1] is the value                                */
    PARASOL_NODE_ARRAY,      /* [a, b, c]                                       */
    PARASOL_NODE_DICTIONARY, /* #[k = v, …]; children alternate key, value      */
    PARASOL_NODE_MACRO,      /* a use of a declared form, before expansion:
                            text is the name, children are the arguments   */
    PARASOL_NODE_INCLUDE,    /* @include "text.sol" -- Solveig's own directive,
                            carried through unread                          */
    PARASOL_NODE_BLOCK,      /* params, temps, and children as the body         */
    PARASOL_NODE_SEQUENCE    /* a module, or a block's body                     */
} ParasolNodeKind;

typedef struct ParasolNode ParasolNode;

struct ParasolNode {
    ParasolNodeKind kind;
    ParasolSpan span;
    const ParasolNode *introduced_by;
    uint32_t scope;

    char *text;                 /* owned; NULL where the kind has no text   */

    /* PARASOL_NODE_MACRO only: which declaration this use matched, as an index
       into the dialect. -1 everywhere else.
     *
     * An index and not a pointer, because the dialect grows while the header is
     * still being read and a template parsed early holds uses of forms declared
     * before it -- `realloc` moves the array and would leave those pointing at
     * freed memory. Appending never invalidates an index. */
    int form;

    ParasolNode **children;
    int count;
    int capacity;

    /* BLOCK only. Owned. */
    char **params;
    int param_count;
    char **temps;
    int temp_count;
};

ParasolNode *parasol_node_new(ParasolNodeKind kind, ParasolSpan span);
/* A deep copy, provenance and scope included. What a template is instantiated
   from, and what an argument substituted twice is substituted from. */
ParasolNode *parasol_node_copy(const ParasolNode *node);
ParasolNode *parasol_node_leaf(ParasolNodeKind kind, ParasolSpan span,
                       const char *text, int length);
void parasol_node_add(ParasolNode *parent, ParasolNode *child);
void parasol_node_add_param(ParasolNode *block, const char *text, int length);
void parasol_node_add_temp(ParasolNode *block, const char *text, int length);
void parasol_node_free(ParasolNode *node);

/* The span a node and everything under it covers, which is what an error about
   a whole expression should underline rather than only its first token. */
ParasolSpan parasol_node_extent(const ParasolNode *node);

const char *parasol_node_kind_name(ParasolNodeKind kind);

/* Writes the tree to `out`, one node per line, indented. `--tree` prints this,
   and it is what the tests compare against. */
void parasol_node_dump(const ParasolNode *node, FILE *out, int depth);

#endif /* PARASOL_TREE_H */
