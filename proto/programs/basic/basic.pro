; basic.pro -- a BASIC interpreter, written in Proto.
;
;     solvm basic.sob examples/fizzbuzz.bas
;     solvm basic.sob                        ; no file: a prompt
;
; Line numbers, LET, PRINT, INPUT, IF/THEN, GOTO, GOSUB/RETURN, FOR/NEXT, END
; and REM. What the dialect bought and what it did not is in README.md, under
; the predictions it was written to test.
;
; **Two grammars are in this file and Proto touches one of them.** The header
; settles how *this* file reads; BASIC's own syntax is a string the program
; reads while it runs, and no header anywhere has an opinion about it. That is
; the distinction docs/targets.md had to untangle for the compiler question,
; and it is worth meeting once in a program that has both.

@use "interp.pro".
@use "../../lib/control.pro".

@include "scan.sol".

; ---------------------------------------------------------------- the state
;
; Every one of these is named by a form in interp.pro, which is why they are
; declared here at the top rather than beside the code that uses them.

toks := array:new.          ; the tokens of the line being parsed
tp := #1.                   ; where the parser is in them
env := dictionary:new.      ; BASIC's variables
pc := #1.                   ; the program counter, in program
running := true.
program := array:new.       ; the statements, in line-number order
lineOf := dictionary:new.   ; a BASIC line number -> an index into program
gosubs := array:new.        ; return addresses
fors := array:new.          ; open FOR frames

digits := "0123456789".
letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_".

; ---------------------------------------------------------------- the lexer
;
; One line at a time, which is BASIC's own unit -- nothing in the language
; spans a line, so a lexer that stops at one needs no state between lines and
; the prompt driver at the foot of this file needs no second parser.

token := { kind, text | | t |
    t := object:new. t:kind := kind. t:text := text. t }.

twoCharOp := { a, b |
    b:notNil && ["<>", "<=", ">="]:indexOf(a:concat(b)):notNil }.

lex := { src | | s, out, c |
    s := scan:on(src).
    out := array:new.
    while !s:atEnd do (
        c := s:peek.
        if isSpace(c) then s:step
        else if isDigit(c) then
            out:add(token:value('num, s:takeWhile({ ch | isDigit(ch) })))
        else if isLetter(c) then
            out:add(token:value('name,
                s:takeWhile({ ch | isLetter(ch) || isDigit(ch) }):asUppercase))
        else if c == "\"" then (
            s:step.
            out:add(token:value('str, s:takeUntil({ ch | ch == "\"" }))).
            s:step)
        else if twoCharOp:value(c, s:peekAt(#1)) then (
            out:add(token:value('op, c:concat(s:peekAt(#1)))). s:step. s:step)
        else (out:add(token:value('op, c)). s:step)).
    out:add(token:value('end, "")).
    out }.

; --------------------------------------------------------------- the parser
;
; Recursive descent over one line's tokens. Four levels of expression, tightest
; last, which is `programs/ember`'s shape -- and the comparison level is where
; this program's own `<=` wants to be a declared operator and cannot be. See
; README.md, prediction 4.

expect := { kind, text |
    unless (toks:at(tp):kind == kind && toks:at(tp):text == text) then
        fail "expected '":concat(text):concat("'").
    take }.

node := { kind | | n | n := object:new. n:kind := kind. n }.

binNode := { op, left, right | | n |
    n := node:value('bin). n:op := op. n:left := left. n:right := right. n }.

parseExpr := { parseCmp:value }.

parseCmp := { | left, op |
    left := parseSum:value.
    while kindIs('op) && ["=", "<>", "<", ">", "<=", ">="]:indexOf(peek:text):notNil do (
        op := take:text.
        left := binNode:value(op, left, parseSum:value)).
    left }.

parseSum := { | left, op |
    left := parseTerm:value.
    while kindIs('op) && ["+", "-"]:indexOf(peek:text):notNil do (
        op := take:text.
        left := binNode:value(op, left, parseTerm:value)).
    left }.

parseTerm := { | left, op |
    left := parseAtom:value.
    while kindIs('op) && ["*", "/"]:indexOf(peek:text):notNil do (
        op := take:text.
        left := binNode:value(op, left, parseAtom:value)).
    left }.

parseAtom := { | t, n |
    if opIs("-") then (
        step.
        n := node:value('neg). n:operand := parseAtom:value. n)
    else (
        t := take.
        if t:kind == 'num then (n := node:value('num). n:value := t:text:asInteger. n)
        else if t:kind == 'str then (n := node:value('str). n:text := t:text. n)
        else if t:kind == 'name then (n := node:value('var). n:name := t:text. n)
        else if t:kind == 'op && t:text == "(" then (
            n := parseExpr:value.
            expect:value('op, ")").
            n)
        else (fail "expected an expression". nil)) }.

; A LET with the word left off, which BASIC allows and which is why the
; keyword chain below ends with a name rather than with an error.
parseAssign := { | n |
    n := node:value('let).
    n:name := take:text.
    expect:value('op, "=").
    n:expr := parseExpr:value.
    n }.

parsePrint := { | n |
    n := node:value('print).
    n:items := array:new.
    unless kindIs('end) then (
        n:items:add(parseExpr:value).
        while opIs(",") do (step. n:items:add(parseExpr:value))).
    n }.

parseFor := { | n |
    n := node:value('for).
    n:name := take:text.
    expect:value('op, "=").
    n:from := parseExpr:value.
    expect:value('name, "TO").
    n:to := parseExpr:value.
    if wordIs("STEP") then (step. n:by := parseExpr:value)
    else (n:by := node:value('num). n:by:value := #1).
    n }.

parseIf := { | n |
    n := node:value('if).
    n:cond := parseExpr:value.
    expect:value('name, "THEN").
    ; `THEN 100` is `THEN GOTO 100`, which is BASIC's one abbreviation.
    if kindIs('num) then (
        n:then := node:value('goto).
        n:then:target := take:text:asInteger)
    else (n:then := parseStmt:value).
    n }.

parseStmt := { | n |
    if wordIs("REM") then (tp := toks:size. node:value('rem))
    else if wordIs("LET") then (step. parseAssign:value)
    else if wordIs("PRINT") then (step. parsePrint:value)
    else if wordIs("INPUT") then (
        step.
        n := node:value('input).
        ; `INPUT "name? "; N` -- the separator is optional, as it is in the
        ; BASICs that have it at all.
        if kindIs('str) then (
            n:prompt := take:text.
            if opIs(";") || opIs(",") then step)
        else (n:prompt := "? ").
        n:name := take:text.
        n)
    else if wordIs("IF") then (step. parseIf:value)
    else if wordIs("GOTO") then (
        step. n := node:value('goto). n:target := take:text:asInteger. n)
    else if wordIs("GOSUB") then (
        step. n := node:value('gosub). n:target := take:text:asInteger. n)
    else if wordIs("RETURN") then (step. node:value('return))
    else if wordIs("FOR") then (step. parseFor:value)
    else if wordIs("NEXT") then (
        step. n := node:value('next).
        if kindIs('name) then n:name := take:text else n:name := nil.
        n)
    else if wordIs("END") then (step. node:value('end))
    else if kindIs('name) then parseAssign:value
    else (fail "expected a statement". nil) }.

; ------------------------------------------------------------- the evaluator
;
; BASIC values are Solveig's integers and strings, unwrapped. `+` is add or
; concat depending on what it is given, which is the one place this program has
; a domain of values -- and the one operator it cannot declare. README.md,
; prediction 2.

truth := { b | if b then #1 else #0 }.

numeric := { v |
    if v:isKindOf(string) then (fail "a number was wanted here". #0) else v }.

binop := { op, a, b |
    if op == "+" then (
        if a:isKindOf(string) then a:concat(b:asString)
        else numeric:value(a):add(numeric:value(b)))
    else if op == "-" then numeric:value(a):sub(numeric:value(b))
    else if op == "*" then numeric:value(a):mul(numeric:value(b))
    else if op == "/" then (
        if numeric:value(b) == #0 then (fail "division by zero". #0)
        else numeric:value(a):div(numeric:value(b)))
    else if op == "=" then truth:value(a == b)
    else if op == "<>" then truth:value(a != b)
    else if op == "<" then truth:value(a:lessThan(b))
    else if op == ">" then truth:value(a:greaterThan(b))
    else if op == "<=" then truth:value(a <= b)
    else truth:value(a >= b) }.

evalExpr := { e |
    if e:kind == 'num then e:value
    else if e:kind == 'str then e:text
    else if e:kind == 'var then fetch(e:name)
    else if e:kind == 'neg then numeric:value(evalExpr:value(e:operand)):negated
    else binop:value(e:op, evalExpr:value(e:left), evalExpr:value(e:right)) }.

; ---------------------------------------------------------------- the runner
;
; The dispatch, and the thing this program was written to look at: it is a
; chain of comparisons on a symbol, and no form in interp.pro removes a line of
; it. README.md, prediction 1.

lineIndex := { n |
    unless lineOf:includes(n) then
        fail "no line ":concat(n:asString).
    lineOf:at(n) }.

forFrame := { name, limit, by, idx | | f |
    f := object:new. f:name := name. f:limit := limit. f:by := by. f:idx := idx. f }.

doPrint := { n |
    if n:items:size == #0 then "":display
    else n:items:collect({ e | evalExpr:value(e):asString }):join(" "):display }.

looksNumeric := { t |
    (t:size > #0 && isDigit(t:at(#1)))
        || (t:size > #1 && t:at(#1) == "-" && isDigit(t:at(#2))) }.

doInput := { n | | text |
    system:write(n:prompt).
    text := system:readLine.
    if text:isNil then halt
    else if looksNumeric:value(text:trim) then
        store n:name as text:trim:asInteger
    else store n:name as text:trim }.

doNext := { n | | f, v |
    if fors:size == #0 then fail "NEXT without FOR".
    f := fors:at(fors:size).
    v := numeric:value(fetch(f:name)):add(f:by).
    store f:name as v.
    if (f:by > #0 && v <= f:limit) || (f:by < #0 && v >= f:limit)
    then jump to f:idx
    else (fors:removeLast. fallThrough) }.

exec := { n |
    if n:kind == 'rem then fallThrough
    else if n:kind == 'let then (store n:name as evalExpr:value(n:expr). fallThrough)
    else if n:kind == 'print then (doPrint:value(n). fallThrough)
    else if n:kind == 'input then (doInput:value(n). fallThrough)
    else if n:kind == 'if then (
        if evalExpr:value(n:cond) != #0 then exec:value(n:then)
        else fallThrough)
    else if n:kind == 'goto then jump to lineIndex:value(n:target)
    else if n:kind == 'gosub then (
        gosubs:add(pc + #1).
        jump to lineIndex:value(n:target))
    else if n:kind == 'return then (
        if gosubs:size == #0 then fail "RETURN without GOSUB".
        jump to gosubs:removeLast)
    else if n:kind == 'for then (
        store n:name as evalExpr:value(n:from).
        fors:add(forFrame:value(n:name,
            evalExpr:value(n:to), evalExpr:value(n:by), pc + #1)).
        fallThrough)
    else if n:kind == 'next then doNext:value(n)
    else halt }.

run := {
    pc := #1.
    running := true.
    while running && pc <= program:size do exec:value(program:at(pc)) }.

; ----------------------------------------------------------------- loading
;
; A line replaces the one with its number, which is how a BASIC program is
; edited at a prompt and costs nothing to have when loading a file.

sortProgram := {
    program := program:sorted({ a, b | a:line:lessThan(b:line) }).
    lineOf := dictionary:new.
    program:do({ s | lineOf:atPut(s:line, program:indexOf(s)) }) }.

addLine := { text | | n, ln, old |
    toks := lex:value(text).
    tp := #1.
    unless kindIs('num) then fail "a line needs a line number".
    ln := take:text:asInteger.
    if kindIs('end) then (
        ; a bare line number deletes that line
        old := program:select({ s | s:line != ln }).
        program := old)
    else (
        n := parseStmt:value.
        n:line := ln.
        n:src := text.
        program := program:select({ s | s:line != ln }).
        program:add(n)).
    sortProgram:value }.

load := { src |
    src:split("\n"):do({ text |
        if text:trim:size > #0 then addLine:value(text:trim) }) }.

; ------------------------------------------------------------------- driver
;
; Two drivers over one parser, and the difference between them is a loop. That
; is BASIC's doing and not Proto's: nothing in the language spans a line, so a
; line read from a prompt is the same unit as a line read from a file.

args := system:arguments.

if args:size > #0 then (
    load:value(system:readFile(args:at(#1))).
    run:value)
else (
    "basic -- RUN, LIST, BYE, or a numbered line":display.
    { running }:whileTrue({ | text |
        system:write("> ").
        text := system:readLine.
        if text:isNil then running := false
        else if text:trim == "BYE" then running := false
        else if text:trim == "RUN" then (run:value. running := true)
        else if text:trim == "LIST" then
            program:do({ s | s:src:display })
        else if text:trim:size > #0 then addLine:value(text:trim) }))
