/* diag.c -- an error, the line it happened on, and a caret under it. */
#include <stdarg.h>

#include "parasol/diag.h"

void parasol_diag_init(ParasolDiagnostics *diag, FILE *out)
{
    diag->out = out;
    diag->errors = 0;
    diag->warnings = 0;
    diag->last = PARASOL_SPAN_NONE;
}

/* The shape both `parasol_error` and `parasol_note` print:
 *
 *     examples/vectors.psol:9:12: error: '+' has not been declared
 *       9 | a := #2 + #3.
 *         |         ^
 *
 * The gutter is as wide as the line number so the bars line up, and the caret
 * is as wide as the span so a whole expression can be underlined rather than
 * only where it started. */
static void report(ParasolDiagnostics *diag, const char *severity, ParasolSpan span,
                   const char *format, va_list args)
{
    const ParasolSource *source = span.source;
    if (source == NULL) {
        /* A report against a span nothing produced. Nothing should get here,
           and the alternative to saying so is a caret on the first character
           of a file chosen at random. */
        fprintf(diag->out, "parasol: %s: ", severity);
        vfprintf(diag->out, format, args);
        fputc('\n', diag->out);
        return;
    }

    int line, column;
    parasol_source_position(source, span.offset, &line, &column);

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
    const char *text = parasol_source_line(source, span.offset, &text_length);

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

void parasol_error(ParasolDiagnostics *diag, ParasolSpan span, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    report(diag, "error", span, format, args);
    va_end(args);
    diag->errors++;
}

void parasol_warning(ParasolDiagnostics *diag, ParasolSpan span, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    report(diag, "warning", span, format, args);
    va_end(args);
    diag->warnings++;
}

void parasol_note(ParasolDiagnostics *diag, ParasolSpan span, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    report(diag, "note", span, format, args);
    va_end(args);
}

void parasol_note_expansion(ParasolDiagnostics *diag, const ParasolNode *node)
{
    for (const ParasolNode *use = node->introduced_by; use != NULL;
         use = use->introduced_by)
        parasol_note(diag, use->span, "in the expansion of '%s', written here",
                 use->text != NULL ? use->text : "a form");
}

void parasol_note_from(ParasolDiagnostics *diag, ParasolSpan at, const char *what)
{
    if (at.source == NULL) return;
    int line, column;
    parasol_span_position(at, &line, &column);
    (void)column;
    fprintf(diag->out, "  ... %s %s, line %d\n", what, at.source->path, line);
}
