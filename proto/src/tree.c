/* tree.c -- building, walking and freeing the tree. */
#include <stdlib.h>
#include <string.h>

#include "proto/tree.h"

ProtoNode *proto_node_new(ProtoNodeKind kind, ProtoSpan span)
{
    ProtoNode *node = proto_alloc(sizeof *node);
    node->kind = kind;
    node->span = span;
    node->introduced_by = NULL;
    node->scope = 0;
    node->text = NULL;
    node->form = -1;
    node->children = NULL;
    node->count = node->capacity = 0;
    node->params = NULL;
    node->param_count = 0;
    node->temps = NULL;
    node->temp_count = 0;
    return node;
}

ProtoNode *proto_node_leaf(ProtoNodeKind kind, ProtoSpan span,
                       const char *text, int length)
{
    ProtoNode *node = proto_node_new(kind, span);
    node->text = proto_strndup(text, (size_t)length);
    return node;
}

ProtoNode *proto_node_copy(const ProtoNode *node)
{
    ProtoNode *copy = proto_node_new(node->kind, node->span);
    copy->introduced_by = node->introduced_by;
    copy->scope = node->scope;
    copy->form = node->form;
    if (node->text != NULL)
        copy->text = proto_strndup(node->text, strlen(node->text));

    for (int i = 0; i < node->count; i++)
        proto_node_add(copy, proto_node_copy(node->children[i]));
    for (int i = 0; i < node->param_count; i++)
        proto_node_add_param(copy, node->params[i], (int)strlen(node->params[i]));
    for (int i = 0; i < node->temp_count; i++)
        proto_node_add_temp(copy, node->temps[i], (int)strlen(node->temps[i]));
    return copy;
}

void proto_node_add(ProtoNode *parent, ProtoNode *child)
{
    if (parent->count == parent->capacity) {
        parent->capacity = parent->capacity < 4 ? 4 : parent->capacity * 2;
        parent->children = proto_realloc(parent->children,
                                       (size_t)parent->capacity * sizeof *parent->children);
    }
    parent->children[parent->count++] = child;
}

static void add_name(char ***list, int *count, const char *text, int length)
{
    *list = proto_realloc(*list, (size_t)(*count + 1) * sizeof **list);
    (*list)[(*count)++] = proto_strndup(text, (size_t)length);
}

void proto_node_add_param(ProtoNode *block, const char *text, int length)
{
    add_name(&block->params, &block->param_count, text, length);
}

void proto_node_add_temp(ProtoNode *block, const char *text, int length)
{
    add_name(&block->temps, &block->temp_count, text, length);
}

void proto_node_free(ProtoNode *node)
{
    if (node == NULL) return;
    for (int i = 0; i < node->count; i++) proto_node_free(node->children[i]);
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
ProtoSpan proto_node_extent(const ProtoNode *node)
{
    uint32_t start = node->span.offset;
    uint32_t end = node->span.offset + node->span.length;

    for (int i = 0; i < node->count; i++) {
        ProtoSpan child = proto_node_extent(node->children[i]);
        /* Only what came from the same file. A node whose child came from a
           used file -- an argument reaching a template, or the other way -- has
           no extent covering both, and picking one end from each would draw a
           caret across whichever file was asked. */
        if (child.source != node->span.source) continue;
        if (child.offset < start) start = child.offset;
        if (child.offset + child.length > end) end = child.offset + child.length;
    }
    return (ProtoSpan){ node->span.source, start, end - start };
}

const char *proto_node_kind_name(ProtoNodeKind kind)
{
    switch (kind) {
        case PROTO_NODE_INTEGER:  return "integer";
        case PROTO_NODE_FLOAT:    return "float";
        case PROTO_NODE_STRING:   return "string";
        case PROTO_NODE_SYMBOL:   return "symbol";
        case PROTO_NODE_NAME:     return "name";
        case PROTO_NODE_SEND:     return "send";
        case PROTO_NODE_ASSIGN:   return "assign";
        case PROTO_NODE_ARRAY:    return "array";
        case PROTO_NODE_DICTIONARY: return "dictionary";
        case PROTO_NODE_MACRO:    return "macro";
        case PROTO_NODE_INCLUDE:  return "include";
        case PROTO_NODE_BLOCK:    return "block";
        case PROTO_NODE_SEQUENCE: return "sequence";
    }
    return "?";
}

void proto_node_dump(const ProtoNode *node, FILE *out, int depth)
{
    fprintf(out, "%*s%s", depth * 2, "", proto_node_kind_name(node->kind));
    if (node->text != NULL) fprintf(out, " %s", node->text);

    for (int i = 0; i < node->param_count; i++)
        fprintf(out, " param:%s", node->params[i]);
    for (int i = 0; i < node->temp_count; i++)
        fprintf(out, " temp:%s", node->temps[i]);

    fprintf(out, " @%u+%u", node->span.offset, node->span.length);
    if (node->scope != 0) fprintf(out, " scope:%u", node->scope);
    if (node->introduced_by != NULL)
        fprintf(out, " from:%s", node->introduced_by->text);
    fputc('\n', out);

    for (int i = 0; i < node->count; i++)
        proto_node_dump(node->children[i], out, depth + 1);
}
