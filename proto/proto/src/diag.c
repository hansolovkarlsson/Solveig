/* diag.c -- an error, the line it happened on, and a caret under it. */
#include <stdarg.h>

#include "proto/diag.h"

void proto_diag_init(ProtoDiagnostics *diag, FILE *out)
{
    diag->out = out;
    diag->errors = 0;
    diag->warnings = 0;
    diag->last = PROTO_SPAN_NONE;
}

/* The shape both `proto_error` and `proto_note` print:
 *
 *     examples/vectors.pro:9:12: error: '+' has not been declared
 *       9 | a := #2 + #3.
 *         |         ^
 *
 * The gutter is as wide as the line number so the bars line up, and the caret
 * is as wide as the span so a whole expression can be underlined rather than
 * only where it started. */
static void report(ProtoDiagnostics *diag, const char *severity, ProtoSpan span,
                   const char *format, va_list args)
{
    const ProtoSource *source = span.source;
    if (source == NULL) {
        /* A report against a span nothing produced. Nothing should get here,
           and the alternative to saying so is a caret on the first character
           of a file chosen at random. */
        fprintf(diag->out, "proto: %s: ", severity);
        vfprintf(diag->out, format, args);
        fputc('\n', diag->out);
        return;
    }

    int line, column;
    proto_source_position(source, span.offset, &line, &column);

    fprintf(diag->out, "%s:%d:%d: %s: ", source->path, line, column, severity);
    vfprintf(diag->out, format, args);
    fputc('\n', diag->out);

    /* A note about the very thing the error just underlined does not need the
       line and the caret again -- it is the same line and the same caret, and
       printing it twice makes a two-line remark look like two problems. */
    bool repeat = span.source == diag->last.source &&
                  span.offset == diag->last.offset &&
                  span.length == diag->last.length;
    diag->last = span;
    if (repeat) return;

    int text_length;
    const char *text = proto_source_line(source, span.offset, &text_length);

    char gutter[16];
    int width = snprintf(gutter, sizeof gutter, "%d", line);

    fprintf(diag->out, " %*d | %.*s\n", width, line, text_length, text);
    fprintf(diag->out, " %*s | ", width, "");

    /* Tabs in the source have to be tabs in the caret line, or the caret lands
       somewhere else in a terminal that renders them eight wide. */
    for (int i = 0; i < column - 1 && i < text_length; i++)
        fputc(text[i] == '\t' ? '\t' : ' ', diag->out);

    uint32_t length = span.length > 0 ? span.length : 1;
    /* Clamped to the line: a span that runs over the end of one -- a block, an
       unterminated string -- should not draw a caret past what is shown. */
    uint32_t room = (uint32_t)text_length - (uint32_t)(column - 1);
    if (length > room) length = room > 0 ? room : 1;

    for (uint32_t i = 0; i < length; i++) fputc('^', diag->out);
    fputc('\n', diag->out);
}

void proto_error(ProtoDiagnostics *diag, ProtoSpan span, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    report(diag, "error", span, format, args);
    va_end(args);
    diag->errors++;
}

void proto_warning(ProtoDiagnostics *diag, ProtoSpan span, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    report(diag, "warning", span, format, args);
    va_end(args);
    diag->warnings++;
}

void proto_note(ProtoDiagnostics *diag, ProtoSpan span, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    report(diag, "note", span, format, args);
    va_end(args);
}

void proto_note_expansion(ProtoDiagnostics *diag, const ProtoNode *node)
{
    for (const ProtoNode *use = node->introduced_by; use != NULL;
         use = use->introduced_by)
        proto_note(diag, use->span, "in the expansion of '%s', written here",
                 use->text != NULL ? use->text : "a form");
}

void proto_note_from(ProtoDiagnostics *diag, ProtoSpan at, const char *what)
{
    if (at.source == NULL) return;
    int line, column;
    proto_span_position(at, &line, &column);
    (void)column;
    fprintf(diag->out, "  ... %s %s, line %d\n", what, at.source->path, line);
}
