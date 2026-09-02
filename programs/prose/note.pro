; note.pro -- a document written in prose.pro, and the code that renders it.
;
;     proto note.pro -o note.sol && solas note.sol -o note.sob && solvm note.sob
;
; The split is the point of the program: everything above `; the renderer` is
; written in the dialect and is data; everything below it is ordinary Proto with
; no notation at all. What each half costs is in README.md.
;
; **The document runs past eighty columns and the rest of this repository does
; not.** A paragraph is a string, and a string is one line unless it is broken
; into `:concat` calls -- which puts code in the middle of a sentence, or a
; literal newline, which changes the text. So the content is left long. It is
; the narrowest place the program is visibly a program and not a document.

@use "prose.pro".

doc := array:new.

; ------------------------------------------------------------- the document

title "Proto".

para "A compiler whose syntax arrives with the file it is compiling.".
para "A module declares its own grammar in its header, and that grammar holds for that file and no other.".

section "What a header may say".
indent {
    item "an operator, its precedence, and the message it becomes".
    item "an operator standing for a template, which a message cannot be".
    item "a form that reads like a call".
    item "a form that reads like a statement".
}.

section "What it will not do".
para "The line between a fixed token stream and a declared grammar is where this design sits.".
quote "Forth and TeX moved the line and became languages no tool can read without executing them.".

rule.

section "Where the evidence is".
indent {
    item "ember, an assembler: notation pays per line".
    item "grammar, a parser: a rule cannot be a form".
    indent {
        item "so the recursive part stops being notation".
        item "and becomes data".
    }.
    item "digest, a hash: a dialect can carry a rule".
    item "ledger, in decimal: and sometimes it carries nothing".
}.

para "Four programs, and the fifth is this one.".

; ---------------------------------------------------------------- the renderer
;
; No notation below this line. It is a walk over `doc` with a case per kind, and
; it is written the way any Solveig-shaped program would be.

repeated := { c, n | | out, i |
    out := "". i := #0.
    while i < n do (out := out:concat(c). i := i + #1).
    out }.

depth := #0.
pad := { repeated:value("    ", depth) }.

emit := { line | line:display }.

render := { | i, node, kind, text |
    ; `i < doc:size + #1` and not `i <= doc:size`, because lib/arith.pro does
    ; not declare `<=`. README.md: this program is the first customer for it.
    i := #1.
    while i < doc:size + #1 do (
        node := doc:at(i).
        kind := node:at(#1).
        text := node:at(#2).

        if kind == 'title then (
            emit:value(text).
            emit:value(repeated:value("=", text:size)))
        else if kind == 'section then (
            emit:value("").
            emit:value(text).
            emit:value(repeated:value("-", text:size)))
        else if kind == 'para then (
            emit:value("").
            emit:value(pad:value:concat(text)))
        else if kind == 'item then
            emit:value(pad:value:concat("- "):concat(text))
        else if kind == 'quote then (
            emit:value("").
            emit:value(pad:value:concat("    "):concat(text)))
        else if kind == 'rule then (
            emit:value("").
            emit:value("---"))
        else if kind == 'in then depth := depth + #1
        else if kind == 'out then depth := depth - #1
        else emit:value("?").

        i := i + #1) }.

render:value.
