/* tree.c -- building, walking and freeing the tree. */
#include <stdlib.h>
#include <string.h>

#include "phoenix/tree.h"

PhxNode *phx_node_new(PhxNodeKind kind, PhxSpan span)
{
    PhxNode *node = phx_alloc(sizeof *node);
    node->kind = kind;
    node->span = span;
    node->introduced_by = NULL;
    node->scope = 0;
    node->text = NULL;
    node->children = NULL;
    node->count = node->capacity = 0;
    node->params = NULL;
    node->param_count = 0;
    node->temps = NULL;
    node->temp_count = 0;
    return node;
}

PhxNode *phx_node_leaf(PhxNodeKind kind, PhxSpan span,
                       const char *text, int length)
{
    PhxNode *node = phx_node_new(kind, span);
    node->text = phx_strndup(text, (size_t)length);
    return node;
}

void phx_node_add(PhxNode *parent, PhxNode *child)
{
    if (parent->count == parent->capacity) {
        parent->capacity = parent->capacity < 4 ? 4 : parent->capacity * 2;
        parent->children = phx_realloc(parent->children,
                                       (size_t)parent->capacity * sizeof *parent->children);
    }
    parent->children[parent->count++] = child;
}

static void add_name(char ***list, int *count, const char *text, int length)
{
    *list = phx_realloc(*list, (size_t)(*count + 1) * sizeof **list);
    (*list)[(*count)++] = phx_strndup(text, (size_t)length);
}

void phx_node_add_param(PhxNode *block, const char *text, int length)
{
    add_name(&block->params, &block->param_count, text, length);
}

void phx_node_add_temp(PhxNode *block, const char *text, int length)
{
    add_name(&block->temps, &block->temp_count, text, length);
}

void phx_node_free(PhxNode *node)
{
    if (node == NULL) return;
    for (int i = 0; i < node->count; i++) phx_node_free(node->children[i]);
    for (int i = 0; i < node->param_count; i++) free(node->params[i]);
    for (int i = 0; i < node->temp_count; i++) free(node->temps[i]);
    free(node->children);
    free(node->params);
    free(node->temps);
    free(node->text);
    free(node);
}

/* From the leftmost offset any node under here holds to the rightmost end.
 *
 * Not the node's own span alone, which for a SEND is the selector: underlining
 * `add` in `#2 + #3 * #4` says nothing, and underlining the whole product says
 * what went wrong with it. */
PhxSpan phx_node_extent(const PhxNode *node)
{
    uint32_t start = node->span.offset;
    uint32_t end = node->span.offset + node->span.length;

    for (int i = 0; i < node->count; i++) {
        PhxSpan child = phx_node_extent(node->children[i]);
        if (child.length == 0 && child.offset == 0) continue;
        if (child.offset < start) start = child.offset;
        if (child.offset + child.length > end) end = child.offset + child.length;
    }
    return (PhxSpan){ start, end - start };
}

const char *phx_node_kind_name(PhxNodeKind kind)
{
    switch (kind) {
        case PHX_NODE_INTEGER:  return "integer";
        case PHX_NODE_FLOAT:    return "float";
        case PHX_NODE_STRING:   return "string";
        case PHX_NODE_SYMBOL:   return "symbol";
        case PHX_NODE_NAME:     return "name";
        case PHX_NODE_SEND:     return "send";
        case PHX_NODE_ASSIGN:   return "assign";
        case PHX_NODE_ARRAY:    return "array";
        case PHX_NODE_INCLUDE:  return "include";
        case PHX_NODE_BLOCK:    return "block";
        case PHX_NODE_SEQUENCE: return "sequence";
    }
    return "?";
}

void phx_node_dump(const PhxNode *node, FILE *out, int depth)
{
    fprintf(out, "%*s%s", depth * 2, "", phx_node_kind_name(node->kind));
    if (node->text != NULL) fprintf(out, " %s", node->text);

    for (int i = 0; i < node->param_count; i++)
        fprintf(out, " param:%s", node->params[i]);
    for (int i = 0; i < node->temp_count; i++)
        fprintf(out, " temp:%s", node->temps[i]);

    fprintf(out, " @%u+%u", node->span.offset, node->span.length);
    if (node->introduced_by != NULL) fprintf(out, " introduced");
    fputc('\n', out);

    for (int i = 0; i < node->count; i++)
        phx_node_dump(node->children[i], out, depth + 1);
}
