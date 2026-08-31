/* tree.h -- the tree every Phoenix program becomes.
 *
 * Phoenix owns this rather than borrowing Solveig's, because Solveig does not
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
#ifndef PHOENIX_TREE_H
#define PHOENIX_TREE_H

#include <stdio.h>

#include "phoenix/source.h"

typedef enum {
    PHX_NODE_INTEGER,    /* text is the digits, without the '#'             */
    PHX_NODE_FLOAT,
    PHX_NODE_STRING,     /* text is the contents, escapes not yet undone    */
    PHX_NODE_SYMBOL,     /* text is the name, without the quote             */
    PHX_NODE_NAME,       /* an identifier in expression position            */

    PHX_NODE_SEND,       /* text is the selector; [0] is the receiver, the
                            rest are arguments                              */
    PHX_NODE_ASSIGN,     /* [0] is the target (NAME or a nullary SEND),
                            [1] is the value                                */
    PHX_NODE_ARRAY,      /* [a, b, c]                                       */
    PHX_NODE_INCLUDE,    /* @include "text.sol" -- Solveig's own directive,
                            carried through unread                          */
    PHX_NODE_BLOCK,      /* params, temps, and children as the body         */
    PHX_NODE_SEQUENCE    /* a module, or a block's body                     */
} PhxNodeKind;

typedef struct PhxNode PhxNode;

struct PhxNode {
    PhxNodeKind kind;
    PhxSpan span;
    const PhxNode *introduced_by;
    uint32_t scope;

    char *text;                 /* owned; NULL where the kind has no text   */

    PhxNode **children;
    int count;
    int capacity;

    /* BLOCK only. Owned. */
    char **params;
    int param_count;
    char **temps;
    int temp_count;
};

PhxNode *phx_node_new(PhxNodeKind kind, PhxSpan span);
PhxNode *phx_node_leaf(PhxNodeKind kind, PhxSpan span,
                       const char *text, int length);
void phx_node_add(PhxNode *parent, PhxNode *child);
void phx_node_add_param(PhxNode *block, const char *text, int length);
void phx_node_add_temp(PhxNode *block, const char *text, int length);
void phx_node_free(PhxNode *node);

/* The span a node and everything under it covers, which is what an error about
   a whole expression should underline rather than only its first token. */
PhxSpan phx_node_extent(const PhxNode *node);

const char *phx_node_kind_name(PhxNodeKind kind);

/* Writes the tree to `out`, one node per line, indented. `--tree` prints this,
   and it is what the tests compare against. */
void phx_node_dump(const PhxNode *node, FILE *out, int depth);

#endif /* PHOENIX_TREE_H */
