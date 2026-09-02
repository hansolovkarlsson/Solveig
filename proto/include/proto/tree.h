/* tree.h -- the tree every Proto program becomes.
 *
 * Proto owns this rather than borrowing Solveig's, because Solveig does not
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
#ifndef PROTO_TREE_H
#define PROTO_TREE_H

#include <stdio.h>

#include "proto/source.h"

typedef enum {
    PROTO_NODE_INTEGER,    /* text is the literal as written, tag and all     */
    PROTO_NODE_FLOAT,
    PROTO_NODE_STRING,     /* text is the contents, escapes not yet undone    */
    PROTO_NODE_SYMBOL,     /* text is the name, without the quote             */
    PROTO_NODE_NAME,       /* an identifier in expression position            */

    PROTO_NODE_SEND,       /* text is the selector; [0] is the receiver, the
                            rest are arguments                              */
    PROTO_NODE_ASSIGN,     /* [0] is the target (NAME or a nullary SEND),
                            [1] is the value                                */
    PROTO_NODE_ARRAY,      /* [a, b, c]                                       */
    PROTO_NODE_DICTIONARY, /* #[k = v, …]; children alternate key, value      */
    PROTO_NODE_MACRO,      /* a use of a declared form, before expansion:
                            text is the name, children are the arguments   */
    PROTO_NODE_INCLUDE,    /* @include "text.sol" -- Solveig's own directive,
                            carried through unread                          */
    PROTO_NODE_BLOCK,      /* params, temps, and children as the body         */
    PROTO_NODE_SEQUENCE    /* a module, or a block's body                     */
} ProtoNodeKind;

typedef struct ProtoNode ProtoNode;

struct ProtoNode {
    ProtoNodeKind kind;
    ProtoSpan span;
    const ProtoNode *introduced_by;
    uint32_t scope;

    char *text;                 /* owned; NULL where the kind has no text   */

    /* PROTO_NODE_MACRO only: which declaration this use matched, as an index
       into the dialect. -1 everywhere else.
     *
     * An index and not a pointer, because the dialect grows while the header is
     * still being read and a template parsed early holds uses of forms declared
     * before it -- `realloc` moves the array and would leave those pointing at
     * freed memory. Appending never invalidates an index. */
    int form;

    ProtoNode **children;
    int count;
    int capacity;

    /* BLOCK only. Owned. */
    char **params;
    int param_count;
    char **temps;
    int temp_count;
};

ProtoNode *proto_node_new(ProtoNodeKind kind, ProtoSpan span);
/* A deep copy, provenance and scope included. What a template is instantiated
   from, and what an argument substituted twice is substituted from. */
ProtoNode *proto_node_copy(const ProtoNode *node);
ProtoNode *proto_node_leaf(ProtoNodeKind kind, ProtoSpan span,
                       const char *text, int length);
void proto_node_add(ProtoNode *parent, ProtoNode *child);
void proto_node_add_param(ProtoNode *block, const char *text, int length);
void proto_node_add_temp(ProtoNode *block, const char *text, int length);
void proto_node_free(ProtoNode *node);

/* The span a node and everything under it covers, which is what an error about
   a whole expression should underline rather than only its first token. */
ProtoSpan proto_node_extent(const ProtoNode *node);

const char *proto_node_kind_name(ProtoNodeKind kind);

/* Writes the tree to `out`, one node per line, indented. `--tree` prints this,
   and it is what the tests compare against. */
void proto_node_dump(const ProtoNode *node, FILE *out, int depth);

#endif /* PROTO_TREE_H */
