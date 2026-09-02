/* emit.c -- the tree as Solveig source, and where every piece of it came from.
 *
 * The generated file is an artefact and is meant to be read the way anybody
 * reads an artefact: rarely, and with the map beside it. What it is not is a
 * place where a diagnostic may point. Every position written here is recorded
 * against the `.pro` offset that caused it, so the day something downstream --
 * `solas`, `solid`, a stack trace -- names a line in the `.sol`, that line can
 * be turned back into the line somebody wrote. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "proto/emit.h"

void proto_emitter_init(ProtoEmitter *emitter)
{
    emitter->text = NULL;
    emitter->length = emitter->capacity = 0;
    emitter->mappings = NULL;
    emitter->mapping_count = emitter->mapping_capacity = 0;
    emitter->line = 1;
    emitter->column = 1;
    emitter->indent = 0;
    emitter->flat = false;
}

void proto_emitter_free(ProtoEmitter *emitter)
{
    free(emitter->text);
    free(emitter->mappings);
    proto_emitter_init(emitter);
}

static void put(ProtoEmitter *emitter, const char *chars, size_t length)
{
    if (emitter->length + length + 1 > emitter->capacity) {
        while (emitter->length + length + 1 > emitter->capacity)
            emitter->capacity = emitter->capacity < 256 ? 256
                                                        : emitter->capacity * 2;
        emitter->text = proto_realloc(emitter->text, emitter->capacity);
    }
    memcpy(emitter->text + emitter->length, chars, length);
    emitter->length += length;
    emitter->text[emitter->length] = '\0';

    for (size_t i = 0; i < length; i++) {
        if (chars[i] == '\n') { emitter->line++; emitter->column = 1; }
        else                  { emitter->column++; }
    }
}

static void write(ProtoEmitter *emitter, const char *chars)
{
    put(emitter, chars, strlen(chars));
}

static void newline(ProtoEmitter *emitter)
{
    write(emitter, "\n");
    for (int i = 0; i < emitter->indent; i++) write(emitter, "    ");
}

static void record(ProtoEmitter *emitter, const ProtoNode *node)
{
    /* Nodes with no span are the ones the compiler made up -- a module's own
       sequence, and whatever an expansion introduces without a form to blame.
       Mapping those to offset 0 would put a caret on the first character of a
       file chosen at random and call it an answer. */
    if (node->span.source == NULL || node->span.length == 0) return;

    if (emitter->mapping_count == emitter->mapping_capacity) {
        emitter->mapping_capacity = emitter->mapping_capacity < 64
                                  ? 64 : emitter->mapping_capacity * 2;
        emitter->mappings = proto_realloc(emitter->mappings,
                                        (size_t)emitter->mapping_capacity
                                            * sizeof *emitter->mappings);
    }
    /* A parent and its leftmost child begin at the same generated character --
       an assignment and its target, a send and its receiver. The deepest of
       them is emitted last and is the precise answer, so it replaces the
       others rather than joining them: one generated position, one source. */
    ProtoMapping *mapping;
    if (emitter->mapping_count > 0 &&
        emitter->mappings[emitter->mapping_count - 1].line == emitter->line &&
        emitter->mappings[emitter->mapping_count - 1].column == emitter->column) {
        mapping = &emitter->mappings[emitter->mapping_count - 1];
    } else {
        mapping = &emitter->mappings[emitter->mapping_count++];
    }
    mapping->line = emitter->line;
    mapping->column = emitter->column;
    mapping->span = node->span;
}

static void emit_node(ProtoEmitter *emitter, const ProtoNode *node);

/* How wide this would be written on one line.
 *
 * Measured by emitting it, into a scratch emitter that never breaks, rather
 * than by a second function that adds up the punctuation. A width calculation
 * beside the emitter is a width calculation that disagrees with it eventually,
 * and the disagreement shows up as a line that wraps for no reason -- or worse,
 * one that does not. Quadratic in nesting depth and nowhere near mattering. */
static size_t flat_width(const ProtoNode *node)
{
    ProtoEmitter scratch;
    proto_emitter_init(&scratch);
    scratch.flat = true;
    emit_node(&scratch, node);
    size_t width = scratch.length;
    proto_emitter_free(&scratch);
    return width;
}

/* Where a generated line is asked to stop. Not a rule about style: a `.sol`
   Proto wrote is read when something has gone wrong, and the reader is
   holding a column number out of a diagnostic. */
#define PROTO_WIDTH 88

static void emit_body(ProtoEmitter *emitter, const ProtoNode *node,
                      const char *separator)
{
    for (int i = 0; i < node->count; i++) {
        if (i > 0) write(emitter, separator);
        emit_node(emitter, node->children[i]);
    }
}

static void emit_block(ProtoEmitter *emitter, const ProtoNode *node)
{
    /* Every piece is written with its space in front rather than behind, so
       that a block which then breaks onto its own lines does not leave a
       trailing space on the header. Generated code is still code somebody
       reads. */
    write(emitter, "{");

    if (node->param_count > 0) {
        write(emitter, " ");
        for (int i = 0; i < node->param_count; i++) {
            if (i > 0) write(emitter, ", ");
            write(emitter, node->params[i]);
        }
        write(emitter, " |");
    }

    if (node->temp_count > 0) {
        write(emitter, " |");
        for (int i = 0; i < node->temp_count; i++) {
            write(emitter, i > 0 ? ", " : " ");
            write(emitter, node->temps[i]);
        }
        write(emitter, " |");
    }

    if (node->count == 0) {
        write(emitter, " }");
        return;
    }

    /* Blocks break when they have to and not before. A block with one short
       statement in it belongs on the line that opened it -- `{ x | x:mul(x) }`
       is the whole point of the notation -- and one that would run off the end
       of the line does not, however few statements it has. */
    bool multiline = !emitter->flat &&
                     (node->count > 1 ||
                      emitter->column + (int)flat_width(node) > PROTO_WIDTH);

    if (multiline) {
        emitter->indent++;
        for (int i = 0; i < node->count; i++) {
            newline(emitter);
            emit_node(emitter, node->children[i]);
            if (i < node->count - 1) write(emitter, ".");
        }
        emitter->indent--;
        write(emitter, " }");
    } else {
        write(emitter, " ");
        emit_node(emitter, node->children[0]);
        write(emitter, " }");
    }
}

static void emit_node(ProtoEmitter *emitter, const ProtoNode *node)
{
    record(emitter, node);

    switch (node->kind) {
        case PROTO_NODE_INTEGER:
            write(emitter, node->text);     /* the tag is part of the text */
            break;

        case PROTO_NODE_FLOAT:
        case PROTO_NODE_NAME:
            write(emitter, node->text);
            break;

        case PROTO_NODE_STRING:
            write(emitter, "\"");
            write(emitter, node->text);
            write(emitter, "\"");
            break;

        case PROTO_NODE_SYMBOL:
            write(emitter, "'");
            write(emitter, node->text);
            break;

        case PROTO_NODE_INCLUDE:
            write(emitter, "@include \"");
            write(emitter, node->text);
            write(emitter, "\"");
            break;

        case PROTO_NODE_SEND:
            emit_node(emitter, node->children[0]);
            write(emitter, ":");
            write(emitter, node->text);
            if (node->count > 1) {
                write(emitter, "(");
                for (int i = 1; i < node->count; i++) {
                    if (i > 1) write(emitter, ", ");
                    emit_node(emitter, node->children[i]);
                }
                write(emitter, ")");
            }
            break;

        case PROTO_NODE_ASSIGN:
            emit_node(emitter, node->children[0]);
            write(emitter, " := ");
            emit_node(emitter, node->children[1]);
            break;

        case PROTO_NODE_ARRAY:
            write(emitter, "[");
            emit_body(emitter, node, ", ");
            write(emitter, "]");
            break;

        /* Children alternate key, value. The `=` written here is Solveig's
           pair separator and not an operator -- whatever a dialect declared
           `=` to mean, it did not mean this, and the reader stopped it from
           reaching the key. See docs/GRAMMAR.md. */
        case PROTO_NODE_DICTIONARY:
            write(emitter, "#[");
            for (int i = 0; i + 1 < node->count; i += 2) {
                if (i > 0) write(emitter, ", ");
                emit_node(emitter, node->children[i]);
                write(emitter, " = ");
                emit_node(emitter, node->children[i + 1]);
            }
            write(emitter, "]");
            break;

        case PROTO_NODE_BLOCK:
            emit_block(emitter, node);
            break;

        case PROTO_NODE_MACRO:
            /* Unreachable: the expander replaces every one of these, and a
               module it could not is never emitted. Written out rather than
               left to `default:`, so that a new node kind is a warning here
               instead of silence. */
            write(emitter, "<unexpanded ");
            write(emitter, node->text);
            write(emitter, ">");
            break;

        case PROTO_NODE_SEQUENCE:
            /* A group. The module's own sequence never reaches here -- proto_emit
               writes that one, because its statements each end in '.' and a
               group's do not. */
            write(emitter, "(");
            emit_body(emitter, node, ". ");
            write(emitter, ")");
            break;
    }
}

void proto_emit(ProtoEmitter *emitter, const ProtoNode *module)
{
    write(emitter,
          "; Generated by Proto " PROTO_VERSION ". Edit the .pro, not this.\n\n");

    for (int i = 0; i < module->count; i++) {
        emit_node(emitter, module->children[i]);
        write(emitter, ".\n");
    }
}

bool proto_emit_write(const ProtoEmitter *emitter, const char *path)
{
    FILE *file = fopen(path, "wb");
    if (file == NULL) return false;
    size_t written = fwrite(emitter->text, 1, emitter->length, file);
    bool ok = written == emitter->length;
    if (fclose(file) != 0) ok = false;
    return ok;
}

const ProtoMapping *proto_emit_lookup(const ProtoEmitter *emitter,
                                  int line, int column)
{
    /* Linear, from the end. The mappings are in generated order, so a binary
       search is available and is not needed yet: this is called once, by a
       person who has just been handed an error. */
    for (int i = emitter->mapping_count - 1; i >= 0; i--) {
        const ProtoMapping *mapping = &emitter->mappings[i];
        if (mapping->line < line ||
            (mapping->line == line && mapping->column <= column))
            return mapping;
    }
    return NULL;
}

bool proto_emit_map_write(const ProtoEmitter *emitter, const char *map_path,
                        const ProtoSource *source, const char *output_path)
{
    FILE *file = fopen(map_path, "wb");
    if (file == NULL) return false;

    fprintf(file, "# proto source map 1\n");
    fprintf(file, "# from %s\n", source->path);
    fprintf(file, "# to   %s\n", output_path);
    fprintf(file, "#\n");
    fprintf(file, "# generated  source   offset  [file, when not the one above]\n");

    for (int i = 0; i < emitter->mapping_count; i++) {
        const ProtoMapping *mapping = &emitter->mappings[i];
        int line, column;
        proto_span_position(mapping->span, &line, &column);

        /* The path only when it is not the file being compiled. A module made
           of one file -- which is most of them -- gets a map with no fourth
           column at all, and a `@use` shows up as the lines that have one. */
        fprintf(file, "%d:%d  %d:%d  %u", mapping->line, mapping->column,
                line, column, mapping->span.offset);
        if (mapping->span.source != source)
            fprintf(file, "  %s", mapping->span.source->path);
        fputc('\n', file);
    }

    return fclose(file) == 0;
}
