; sola.sol -- SolaBasic compiled to bytecode. Stage 3: labels and GOTO.
;
; Run with:  ./bin/solas programs/sola.sol && ./bin/solvm programs/sola.sob
; On a file:  ./bin/solvm programs/sola.sob prog.bas [prog.sob]
;
; The thirteenth program here, and the second that is about another language --
; but where [basic.sol](basic.sol) *interprets* one, this **compiles** one, and
; the file it writes is run by `solvm` with nothing of this program present.
;
; The language is [SolaBasic](../docs/SOLABASIC.md), and there is a
; [reference manual](../docs/SOLABASIC-REFERENCE.md) for people who want to
; write it rather than read about it. **All eight stages are here**, and every
; one of them is held against a real QuickBASIC 4.5 by
; [oracle.sh](sola/oracle.sh) rather than only against transcripts this
; compiler recorded of itself.
;
; **Stage 3 went first on purpose** -- it is `GOTO` and labels, the claim the
; whole design rests on, and the document says to reach it in week one rather
; than week six. Stage 2, the structured half, then needed nothing the first
; half had not already built. Stage 4 is procedures, and it is the one the
; document called the most expensive item in the language.
;
; ---------------------------------------------------------------------------
; Why a compiler at all, when there is already an interpreter
;
; **Because `GOTO` cannot be written in Solum.** Solum has no control-flow
; syntax -- a loop is a message send -- so a translator from BASIC to Solum
; source would have to compile every statement into a block, put the blocks in
; an array, and dispatch on a label variable. That is a full send per BASIC
; statement, which is roughly what `basic.sol` already pays as a tree-walker: it
; would be a slower interpreter wearing a compiler's name.
;
; Emitting bytecode, `GOTO` is `OP_JUMP` and `OP_LOOP`. This is the rare case
; where dropping a level buys a **construct** rather than a constant factor.
;
; **And the verifier cooperates**, which is the part that had to be checked
; rather than assumed. SolVM verifies that the paths into any instruction agree
; on stack height. Every SolaBasic statement here compiles at depth 0 and ends
; with a `POP`, so every label is a depth-0 merge point *by construction* and an
; arbitrary jump between statements needs no analysis at all.
;
; That was measured before this program was written, by hand-assembling a chunk
; with a backward jump to an arbitrary earlier offset, a forward jump over dead
; code, and a conditional between them. It verified and ran. Both ways of
; getting it wrong were checked too, and both are refused **at load**, exit 65,
; as a message rather than a crash:
;
;   a jump into the middle of an instruction   bytecode is internally inconsistent
;   a jump to a different stack depth          bytecode is internally inconsistent
;
; The second is the one that matters, because it is what a compiler that got
; clever would produce -- and it means the depth-0 discipline is load-bearing
; rather than tidy.
;
; ---------------------------------------------------------------------------
; What stage 2 cost, which was less than expected
;
; **Every structured statement is jumps and a stack, and the jumps were already
; here.** `GOTO` needed a hole punched in the code and filled in when its label
; turned up; `IF`, `SELECT CASE`, `FOR`, `DO` and `WHILE` need exactly the same
; hole, filled in when their closing line turns up instead. So the whole of
; stage 2 is one stack of open blocks, each frame holding the holes it still
; owes an answer to, and nothing was added to the back end at all.
;
; **The blocks are a stack and the statements stay flat**, which is the one
; design decision here worth arguing about. A parser that built a tree is the
; other way, and it is the wrong way: BASIC's blocks are not written as nesting,
; they are an opening line and a closing line, and half the errors worth
; reporting are about the two not matching. A stack has the mismatch in its
; hand -- `NEXT` closes whatever is on top and says what it found -- where a
; tree would have refused to parse and had less to say about why.
;
; **And it is what makes `EXIT FOR` reach the right loop.** It leaves the
; innermost `FOR`, not the innermost block, so an `EXIT FOR` inside an `IF`
; inside the loop is a search down the stack for the first frame of that kind.
; That is four lines against a tree walk.
;
; ---------------------------------------------------------------------------
; What stage 5 cost, which was less than by-reference had been
;
; **A Solum array is already a reference**, so passing one to a procedure needs
; none of the boxing a scalar needs: `Sort(n(), 6)` hands the array over and the
; callee's `atPut` writes the caller's storage because it is the same array.
; That is the whole of by-reference for arrays, and it is free.
;
; **The bounds are constant, so most of the index arithmetic is.** A SolaBasic
; array is a Solum array, which is one-dimensional and counts from one, so
; `a(i)` is `i - low + 1` and a second dimension multiplies by the size of the
; ones inside it. Those strides are worked out while compiling.
;
; **Every subscript of a multi-dimensional array is checked, and a
; one-dimensional one is not.** One out of range would otherwise land on a
; *different element* rather than off the end -- `a(1, 9)` in an eight-by-eight
; is index 9, which is `a(2, 1)` -- and answering the wrong element quietly is
; the one thing this must not do. A one-dimensional array needs no check because
; there is nowhere for a bad subscript to land except outside the array, and the
; machine refuses that itself.
;
; ---------------------------------------------------------------------------
; What stage 1 cost, which was the type system and the library
;
; **Types have to be worked out before a single byte is emitted.** A conversion
; is an instruction acting on the top of the stack, so turning an Integer into a
; Double must be emitted *after* that Integer is pushed and *before* the value
; beside it -- and by then it is much too late to discover it was needed. So
; every node learns its type in a pass of its own, and emitting is a second walk
; that already knows where the conversions go. Getting that order wrong is the
; whole difficulty of the stage; everything after it is a table.
;
; **There is no boolean type, and that is BASIC's rule rather than a shortcut.**
; A comparison answers `-1` or `0` when it is used as a number, which is why
; `NOT`, `AND` and `OR` are bit operations and still read correctly. Internally a
; comparison answers the machine's boolean, because that is what a conditional
; jump wants; turning one into `-1` costs a jump, so the jump is emitted only
; where the value really is used as a number -- which is almost nowhere.
;
; **Two operators follow QBasic against the machine.** SolVM's integer `div` and
; `mod` are floored, so `-7 \\ 2` would be `-4` and `-7 MOD 2` would be `1`.
; QBasic says `-3` and `-1`. The correction is exact and stays in integers -- the
; truncating quotient is the floored one plus one when there is a remainder and
; the signs differ -- so this is right for every number an Integer can hold.
;
; **A supplied function is emitted where it is called.** There is nowhere to put
; a library: the `.sob` this writes is the whole program and none of `lib/` is in
; it. So `SGN` is a scratch slot and two conditional jumps, `LEFT$` is two
; comparisons that clamp before `copyFrom` is allowed near it, and `LTRIM$` is a
; loop -- all of it the same jumps a `SELECT CASE` compiles to.
;
; ---------------------------------------------------------------------------
; What stage 4 cost, which was the expensive one
;
; **A SUB is a block and a call is `value`.** That is a close fit rather than a
; contrivance: a block has its own frame, takes its arguments in slots 1..n, and
; answers its last expression. A `FUNCTION` answers by assigning to its own
; name, so the name is a local and the body's last act is to push it.
;
; **It never captures its home frame.** ROADMAP 3.1 says a block that reads the
; frame it was written in cannot outlive it, and that would have been in the way
; -- except that a SolaBasic procedure has no reason to reach outside itself,
; because every name it uses is its own slot or a global. So the flags say
; block-and-not-capturing and the limitation never bites.
;
; **What does bite is 3.5**, exactly as SOLABASIC.md predicted before any of
; this existed: a call is a real frame, so recursion stops around 254 levels.
; The trace names the BASIC procedure and the BASIC line when it does.
;
; **By reference is a box, and the variable *is* the box.** QBasic passes by
; reference -- assigning to a parameter assigns to the caller's variable -- and
; passing by value instead would leave `SWAP`-shaped programs running and
; answering *differently*, which is the one outcome this project does not take.
; The implementation is a one-element array: a variable that is ever passed by
; reference is kept in one everywhere, so the call hands over the array itself
; and the callee's `atPut` reaches the caller's storage. No wrapping at the
; call, no copying back, nothing to keep alive across it, and nothing to get
; wrong when the call is recursive.
;
; **Which parameters are by reference is a fixed point.** A parameter is one
; when the procedure assigns to it, or when it hands it on to somewhere that
; does -- and that second half chains, so it takes as many rounds as the chain
; is long. It settles because a parameter only ever turns from by-value to
; by-reference and never back.
;
; ---------------------------------------------------------------------------
; What is here, and what is stage 5 onwards
;
;   labels        `Name:` at the start of a line, and a bare number, which is a
;                 label and not a line number -- CB80's rule, so it need not be
;                 ordered and nothing here ever sorts one
;   GOTO          forwards and backwards, to any label in the program
;   IF            both shapes: a block with `ELSEIF` and `ELSE`, and the
;                 one-line form, which holds a single statement and an `ELSE`
;   SELECT CASE   value lists, `low TO high`, `CASE IS <op>`, `CASE ELSE`
;   FOR / NEXT    with `STEP`, nested, and `NEXT j, i` closing two at once
;   DO / LOOP     `WHILE` or `UNTIL` at either end, or neither
;   WHILE / WEND  the same loop under its older spelling
;   EXIT          `EXIT FOR`, `EXIT DO`, `EXIT SUB`, `EXIT FUNCTION`
;   SUB           with parameters, called as `CALL S(a)` or `S a`
;   FUNCTION      answering by assignment to its own name, and recursive
;   SHARED        inside a procedure, naming a module variable to use
;   STATIC        a local that survives between calls
;   DECLARE       read and dropped; nothing needs declaring here
;   DIM           arrays of up to eight dimensions, bounds fixed at compile
;                 time, with `AS` or a suffix for the type, and `SHARED`
;   PRINT USING   `# . , + - ** $$ ^^^^ _` for numbers, `! \\ \\ &` for text,
;                 and a format shorter than the list starts again
;   INPUT         one line split on commas, with the prompt beside the answer
;   LINE INPUT    the line whole, commas and all
;   OPEN / CLOSE  sequential files, for INPUT, OUTPUT or APPEND
;   PRINT # / WRITE #   to a file; WRITE quotes its text and commas its items
;   INPUT # / LINE INPUT #   back out again, and `EOF(n)` says when to stop
;   OPTION BASE   0 or 1, asked once, before the first `DIM`
;   CONST         folded where it stands
;   assignment    `LET` optional, scalars only
;   PRINT         BASIC's rules: the sign space and the trailing space on a
;                 number, print zones of 14, a margin of 80, `TAB` and `SPC`,
;                 and a separator at the end of the line that holds it open
;   END           stops
;   types         Integer, Double and String, by suffix or by `DEF`
;   expressions   `^ * / \\ MOD + -`, the six comparisons, `NOT AND OR XOR`
;   functions     all twenty-seven, compiled where they are called
;   RANDOMIZE     reseeds the one generator
;   comments      `REM` and `'`
;
; **Not here, and not pretended:** random-access files, `REDIM`,
; `LBOUND`/`UBOUND`, and an array parameter of more than one dimension. `PRINT`'s real formatting is
; stage 6; here the items of one `PRINT` are joined and shown, with no zones and
; no trailing space, so its output is **not** what a BASIC prints. That is a
; stage, not a divergence, and it is the one thing here most likely to be
; mistaken for a bug.

@include "scan.sol".
@include "control.sol".
@include "sob.sol".

; ---------------------------------------------------------------------------
; The instruction set -- the ten this stage needs
;
; The opcode numbers are the order of the enum in
; solum/include/solum/bytecode.h. BYTECODE.md describes every instruction and
; now gives the byte for each, which it did not when disasm.sol first wanted one.

CONST   := #0.
NIL     := #1.
GLOBAL  := #2.
LOCAL   := #4.
SETLOCAL := #5.
SETGLOB := #3.
STRING  := #9.
BLOCK   := #8.
SEND    := #11.
JUMP    := #13.
JMPF    := #14.
LOOP    := #17.
POP     := #18.
RETURN  := #19.
HALT    := #20.

; A jump's operand is a u16, so no jump reaches further than this. SolaBasic
; says so in as many words, and this is where it is enforced.
jumpLimit := #65535.

digits  := "0123456789".
letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ".

isDigit  := { c | c:notNil:and({ digits:indexOf(c):notNil }) }.
isLetter := { c | c:notNil:and({ letters:indexOf(c:asUppercase):notNil }) }.
isSpace  := { c | c:notNil:and({ c:equals(" "):or({ c:equals("\t") }) }) }.

; The operators, and the message each one becomes. There is no arithmetic
; instruction in this machine, so every one of these is an ordinary send -- the
; same send the tree-walker makes, minus the tree.
selectors := dictionary:new.
selectors:atPut("+", "add").          selectors:atPut("-", "sub").
selectors:atPut("*", "mul").          selectors:atPut("/", "div").
selectors:atPut("=", "equals").       selectors:atPut("<>", "notEquals").
selectors:atPut("<", "lessThan").     selectors:atPut(">", "greaterThan").
selectors:atPut("<=", "lessOrEqual"). selectors:atPut(">=", "greaterOrEqual").
selectors:atPut("AND", "bitAnd").     selectors:atPut("OR", "bitOr").
selectors:atPut("XOR", "bitXor").

comparisons := ["=", "<>", "<", "<=", ">", ">="].
additive    := ["+", "-"].
multiplicative := ["*", "/"].
bitwise     := ["AND", "OR", "XOR"].

; The three types, and the fourth that is not one.
;
; `'boolean` is what a comparison answers and is **not a SolaBasic type**: the
; language has no boolean, and `A = B` used as a number is `-1` or `0` as it is
; in every BASIC. It exists here because a condition wants the machine's boolean
; and turning one into `-1` costs a jump -- so the jump is emitted only where the
; value is used as a number, which is almost nowhere.
types := ['integer, 'double, 'string].

; Filled in below, once the emitters they need exist.
builtins := dictionary:new.

suffixTypes := dictionary:new.
suffixTypes:atPut("%", 'integer).  suffixTypes:atPut("&", 'integer).
suffixTypes:atPut("#", 'double).   suffixTypes:atPut("$", 'string).

keywords := ["PRINT", "GOTO", "IF", "THEN", "ELSE", "ELSEIF", "END", "REM",
             "LET", "SELECT", "CASE", "IS", "TO", "FOR", "STEP", "NEXT",
             "DO", "LOOP", "WHILE", "WEND", "UNTIL", "EXIT",
             "SUB", "FUNCTION", "CALL", "SHARED", "STATIC", "DECLARE",
             "AND", "OR", "XOR", "NOT", "MOD",
             "DEFINT", "DEFLNG", "DEFDBL", "DEFSTR", "RANDOMIZE",
             "DIM", "OPTION", "BASE", "CONST", "AS", "INPUT", "LINE",
             "USING", "OPEN", "CLOSE", "OUTPUT", "APPEND", "WRITE"].

; ---------------------------------------------------------------------------
; A token, and a node

token := object:new.
token:kind := 'word.        ; 'number 'based 'string 'word 'punct
token:text := "".
; A numeric literal may say its own type: `1#` is a Double and `1%` an Integer,
; which is how QBasic writes one and is separate from the digits themselves.
token:suffix := nil.

makeToken := { kind, text | | t |
    t := token:new. t:kind := kind. t:text := text. t }.

node := object:new.
node:kind := 'number.       ; 'number 'string 'variable 'binary 'negate 'call
node:value := nil.
node:name := "".            ; 'variable, 'call
node:op := "".
node:left := nil.
node:right := nil.
node:args := nil.           ; 'call
; The type the value will have, worked out over the whole tree before any of it
; is emitted -- because a conversion has to be inserted *before* the value it
; converts is pushed, and by then it is too late to ask.
node:type := nil.
; What both sides of a binary node have to be turned into before the send. Not
; always the answer's type: `/` answers a Double from two Integers, `\\` answers
; an Integer from two Doubles, and a comparison answers neither.
node:operandType := nil.
; **Whether it was written in brackets**, which matters in exactly one place:
; `CALL Foo((x))` passes a copy where `CALL Foo(x)` passes the variable. That is
; QBasic's own way of spelling by-value and the only one SolaBasic has.
node:grouped := false.

arrayRefNode := { name | | n | n := node:new. n:kind := 'arrayref. n:name := name. n }.

numberNode   := { v, t | | n |
    n := node:new. n:kind := 'number. n:value := v. n:type := t. n }.
stringNode   := { v | | n |
    n := node:new. n:kind := 'string. n:value := v. n:type := 'string. n }.
variableNode := { s | | n | n := node:new. n:kind := 'variable. n:name := s. n }.
negateNode   := { x | | n | n := node:new. n:kind := 'negate. n:left := x. n }.
notNode      := { x | | n | n := node:new. n:kind := 'not. n:left := x. n }.
binaryNode   := { op, l, r | | n |
    n := node:new. n:kind := 'binary. n:op := op. n:left := l. n:right := r. n }.
callNode     := { name, args | | n |
    n := node:new. n:kind := 'call. n:name := name. n:args := args. n }.

; A statement, with the label that stands in front of it and the source line it
; came from -- the line is carried this far because the `.sob` records which
; line each byte belongs to, and a debugger reads that back.
stmt := object:new.
stmt:kind := 'rem.
    ; 'rem 'let 'print 'goto 'end
    ; 'ifline 'ifblock 'elseif 'else 'endif
    ; 'select 'case 'caseelse 'endselect
    ; 'for 'next  'do 'loop  'while 'wend  'exit
stmt:line := #1.
stmt:label := nil.
stmt:name := "".            ; 'let, 'for
stmt:expr := nil.           ; 'let, the condition of every conditional, 'select
stmt:items := nil.          ; 'print, and 'next's list of variables
stmt:target := "".          ; 'goto, and what 'exit leaves
stmt:then := nil.           ; 'ifline: the statement after THEN
stmt:otherwise := nil.      ; 'ifline: the statement after ELSE
stmt:limit := nil.          ; 'for
stmt:step := nil.           ; 'for, nil when none was written
stmt:test := 'none.         ; 'do and 'loop: 'none 'while 'until
stmt:alternatives := nil.   ; 'case
stmt:seps := nil.           ; 'print: what followed each item -- ; or , or nothing
stmt:bounds := nil.         ; 'dim: [low, high] per dimension, already constant
stmt:shared := false.       ; 'dim: whether a procedure may see it
stmt:subscripts := nil.     ; 'arrayset: the subscripts of the element assigned
stmt:arrayParams := nil.    ; 'sub and 'function: which parameters are arrays
stmt:using := nil.          ; 'print: the format, when there is a USING
stmt:channel := nil.        ; a file number, when the statement names one
stmt:body := nil.           ; 'sub and 'function: the statements between them

; ---------------------------------------------------------------------------
; A block being compiled
;
; **The statements stay flat and the blocks are a stack.** A parser that built a
; tree would be the other way to do this, and it is the wrong way here: BASIC's
; block structure is not written as nesting, it is written as an opening
; statement and a closing one on lines of their own, with a listing that is
; legal to write and illegal to nest wrongly. Matching them on a stack while
; emitting is the same shape as the source, and it is what makes `EXIT FOR`
; reach the right loop -- the innermost frame of that kind, which is a search up
; a stack and would be a search up a tree.
;
; A frame holds what has to be patched later and what has to be jumped back to,
; and nothing else. Everything in it is a code offset.

frame := object:new.
frame:kind := 'if.          ; 'if 'select 'for 'do 'while
frame:line := #1.           ; where it was opened, for the error if it is not closed
frame:pending := nil.       ; forward holes waiting for the next arm of the block
frame:exits := nil.         ; forward holes waiting for the end of the block
frame:top := #0.            ; a loop: the offset to jump back to
frame:name := "".           ; 'for: the counter, so NEXT can be checked against it
frame:index := #0.          ; 'for: the counter's slot, when the counter is one
frame:limitSlot := #0.      ; 'for: where the limit was put, evaluated once
frame:stepSlot := #0.       ; 'for: where a computed step was put
frame:subject := #0.        ; 'select: where the subject was put, evaluated once
frame:step := nil.          ; 'for: the step, when it was written as a literal
frame:varType := 'double.   ; 'for: the counter's type, which the loop runs in
frame:subjectType := 'double.  ; 'select: the subject's type
frame:seenElse := false.    ; 'if and 'select: whether ELSE has gone by

makeFrame := { kind, line | | f |
    f := frame:new.
    f:kind := kind. f:line := line.
    f:pending := array:new. f:exits := array:new.
    f }.

; ---------------------------------------------------------------------------
; The compiler

sola := object:new.
sola:path := "prog.bas".
sola:atLine := #0.
sola:statements := nil.

sola:code := nil.
sola:names := nil.
sola:nameIndex := nil.
sola:constants := nil.
sola:constIndex := nil.
sola:labelAt := nil.        ; label -> the code offset it stands in front of
sola:fixups := nil.         ; [at, label, line] for every jump, patched at the end
sola:lineMarks := nil.      ; [offset, line], to be run-length encoded

sola:fail := { message |
    self:atLine:equals(#0):ifElse(
        { error:raise(message) },
        { error:raise("line {}: {}":fill([self:atLine, message])) }) }.

; ---------------------------------------------------------------------------
; Tokenising, one line at a time
;
; Line by line rather than over the whole text, because SolaBasic is
; line-oriented: a statement ends at the end of its line, there is no
; continuation, and `REM` swallows the rest of its line as raw text.

sola:tokenise := { text | | s, out, c |
    s := scan:on(text).
    out := array:new.
    { s:atEnd:not }:whileTrue({
        c := s:peek.
        [ { isSpace:value(c) },      { s:step },
          { c:equals("'") },         { s:skipWhile({ any | true }) },
          { isDigit:value(c):or({ c:equals("."):and({
                isDigit:value(s:peekAt(#1)) }) }) },
                                     { out:add(self:numberToken(s)) },
          { c:equals("&") },         { out:add(self:basedToken(s)) },
          { isLetter:value(c) },
            ; REM takes the rest of its line as raw text, which need not be
            ; anything this could tokenise -- `REM don't` is a legal comment and
            ; an unclosed string. So the scanner stops rather than reading it.
            { out:add(self:wordToken(s)).
              out:at(out:size):text:equals("REM"):ifTrue({
                  s:skipWhile({ any | true }) }) },
          { c:equals("\"") },        { out:add(self:quotedToken(s)) },
                                     { out:add(self:punctToken(s)) } ]:ifElseIf }).
    out }.

; **`D` is an exponent as well as `E`.** QBasic writes a Double's exponent with
; a D and a Single's with an E; SolaBasic has one float, so both are read and
; the text is normalised to the E that `asFloat` understands.
sola:numberToken := { s | | start, text, t, mark |
    start := s:pos.
    s:skipWhile({ c | isDigit:value(c) }).
    s:match("."):ifTrue({ s:skipWhile({ c | isDigit:value(c) }) }).
    s:peek:notNil:and({ ["E", "D"]:indexOf(s:peek:asUppercase):notNil }):ifTrue({
        s:step.
        s:match("+"):ifFalse({ s:match("-") }).
        s:skipWhile({ c | isDigit:value(c) }) }).
    text := s:since(start).
    ["D", "d"]:do({ letter |
        text := text:split(letter):join("E") }).
    t := makeToken:value('number, text).
    s:match("!"):ifTrue({
        self:fail("'{}!' is a SINGLE, and SolaBasic has no SINGLE -- see "
            :concat("docs/SOLABASIC.md. A plain {} is a Double.")
            :fill([text, text])) }).
    mark := ["%", "&", "#"]:select({ each | s:looksLike(each) }).
    mark:size:equals(#0):ifFalse({ s:step. t:suffix := mark:at(#1) }).
    t }.

; Folded to uppercase, so `print x` and `PRINT X` are one program. A string
; literal is not folded, which is why this happens here and not to the line.
;
; **A type suffix is part of the name.** `A%` and `A$` are two variables, not one
; variable read two ways, which is QBasic's rule -- and it is why the suffix is
; taken here rather than left to the parser as an operator.
sola:wordToken := { s | | text, suffix |
    text := s:takeWhile({ c | isLetter:value(c):or({ isDigit:value(c) }) }):asUppercase.
    ; **Names beginning `SOLA` belong to the runtime.** `PRINT`'s rules are
    ; written in SolaBasic and compiled with everything else, so its routines and
    ; its line buffer are ordinary names and would collide with a listing that
    ; happened to pick one. Reserving four letters is the whole of the defence,
    ; and it is one rule rather than a renaming pass.
    self:inPrelude:not:and({ text:size:greaterOrEqual(#4) })
        :and({ text:copyFrom(#1, #4):equals("SOLA") }):ifTrue({
        self:fail("names beginning SOLA belong to the runtime: '{}'"
            :fill([text])) }).
    s:match("!"):ifTrue({
        self:fail("'{}!' is a SINGLE, and SolaBasic has no SINGLE -- see "
            :concat("docs/SOLABASIC.md. Write {} or {}# for a Double.")
            :fill([text, text, text])) }).
    suffix := ["%", "&", "#", "$"]:select({ mark | s:looksLike(mark) }).
    suffix:size:equals(#0):ifElse(
        { makeToken:value('word, text) },
        { s:step. makeToken:value('word, text:concat(suffix:at(#1))) }) }.

; `&HFF` and `&O17`, which are integers however they are written.
sola:basedToken := { s | | mark, digits |
    s:step.
    mark := s:peek.
    mark:isNil:ifTrue({ self:fail("'&' needs H or O after it") }).
    mark := mark:asUppercase.
    ["H", "O"]:indexOf(mark):isNil:ifTrue({
        self:fail("'&{}' is not a number: write &H for hex or &O for octal"
            :fill([s:peek])) }).
    s:step.
    digits := s:takeWhile({ c |
        isDigit:value(c):or({ c:notNil:and({
            "ABCDEFabcdef":indexOf(c):notNil }) }) }).
    digits:size:equals(#0):ifTrue({ self:fail("'&{}' has no digits":fill([mark])) }).
    makeToken:value('based,
        digits:asInteger(mark:equals("H"):ifElse({ #16 }, { #8 })):asString) }.

sola:quotedToken := { s | | text |
    s:step.
    text := s:takeUntil({ c | c:equals("\"") }).
    s:match("\""):ifFalse({ self:fail("a string was never closed") }).
    makeToken:value('string, text) }.

sola:punctToken := { s | | c |
    c := s:next.
    c:equals("<"):ifTrue({
        s:match("="):ifElse({ c := "<=" }, { s:match(">"):ifTrue({ c := "<>" }) }) }).
    c:equals(">"):ifTrue({ s:match("="):ifTrue({ c := ">=" }) }).
    "+-*/(),;=<>:^\\#":indexOf(c:at(#1)):isNil:ifTrue({
        self:fail("'{}' means nothing here":fill([c])) }).
    makeToken:value('punct, c) }.

; ---------------------------------------------------------------------------
; Parsing
;
; A cursor into one line's tokens. `cursor` is where the next unread token is,
; and every parse routine leaves it pointing past what it read.

sola:tokens := nil.
sola:cursor := #1.

sola:peekToken := { self:tokenAt(self:cursor) }.
sola:tokenAt := { i |
    i:lessOrEqual(self:tokens:size):ifElse({ self:tokens:at(i) }, { nil }) }.
sola:takeToken := { | t |
    t := self:peekToken. self:cursor := self:cursor:add(#1). t }.
; **A one-line IF ends its statement at ELSE**, and there is nowhere else for
; that knowledge to live: `IF c THEN PRINT a ELSE PRINT b` needs PRINT to stop
; at a word it would otherwise have read as another item. The flag is set only
; while the two halves of such an IF are being parsed, so ELSE is an ordinary
; word everywhere else -- including where it opens a block on a line of its own.
sola:stopAtElse := false.
sola:inPrelude := false.
sola:hasPrelude := false.

; **A `:` ends a statement as surely as the end of the line does.** It cannot
; appear inside an expression, and a label's colon is taken before any statement
; is parsed, so there is nowhere else for one to be.
sola:atEndOfLine := {
    self:cursor:greaterThan(self:tokens:size)
        :or({ self:nextIs(":") })
        :or({ self:stopAtElse:and({ self:nextIs("ELSE") }) }) }.

sola:atEndOfRealLine := { self:cursor:greaterThan(self:tokens:size) }.

; Is the next token this punctuation or word?
;
; **The kind is checked and not only the text**, which looks like belt and
; braces and is not: a string literal carries its contents as its text, so
; `"-"` answered yes to *is the next token a minus* and
; `T$ = "-" + MID$(T$, 3)` was read as an assignment beginning with a unary
; minus. Found by writing SolaBasic rather than by testing the compiler.
sola:nextIs := { text | | t |
    t := self:peekToken.
    t:notNil:and({ ['word, 'punct]:indexOf(t:kind):notNil })
        :and({ t:text:equals(text) }) }.

; ---------------------------------------------------------------------------
; A line: an optional label, then at most one statement
;
; **A number at the start of a line is a label**, not a line number. That is
; CB80's rule taken over whole -- a label is a string of characters rather than
; a numeric quantity -- and it is what lets an old listing through unaltered
; while nothing in this program ever sorts one or expects them to ascend.

; A line answers however many statements are written on it, the label going to
; the first of them.
sola:parseLine := { text, line | | out, st, t |
    self:atLine := line.
    self:tokens := self:tokenise(text).
    self:cursor := #1.
    self:stopAtElse := false.
    out := array:new.
    self:atEndOfRealLine:ifElse({ out }, {
        st := stmt:new.
        st:line := line.

        ; A label: `Name:` or a bare number.
        t := self:peekToken.
        t:kind:equals('number):ifTrue({
            st:label := t:text. self:takeToken }).
        t:kind:equals('word):and({ keywords:indexOf(t:text):isNil }):and({
            | n | n := self:tokenAt(self:cursor:add(#1)).
                  n:notNil:and({ n:text:equals(":") }) }):ifTrue({
            st:label := t:text. self:takeToken. self:takeToken }).

        self:atEndOfLine:ifElse({ st:kind := 'rem }, { self:parseStatement(st) }).
        out:add(st).
        { self:nextIs(":") }:whileTrue({
            self:takeToken.
            self:atEndOfRealLine:ifFalse({
                st := stmt:new.
                st:line := line.
                self:parseStatement(st).
                out:add(st) }) }).
        out }) }.

; One entry per keyword that opens a statement. A dictionary rather than a nest
; of tests, for the reason lib/control.sol gives and basic.sol's parser found
; first: seventeen alternatives written flat, against seventeen closing braces.
; Anything that is not in here is an assignment.
parsers := dictionary:new.

sola:parseStatement := { st | | t |
    t := self:peekToken.
    t:kind:equals('word):and({ parsers:includes(t:text) }):ifElse(
        { self:takeToken. parsers:at(t:text):value(self, st) },
        { self:parseAssignment(st) }) }.

; The statements a one-line IF may hold. A block cannot go on one, because its
; closing line would have nowhere to be. Everything else can, and `CALL` in
; particular -- `IF x > 80 THEN CALL Wrap` is how BASIC is written, and leaving
; it out was found by the runtime below failing to compile.
; Anything that is not a block may go on one. `IF c THEN a(i) = 1` is as
; ordinary as `IF c THEN x = 1`, and leaving the first out was found by a
; program that wanted it rather than by anything looking.
inlineKinds := ['let, 'arrayset, 'print, 'goto, 'end, 'exit, 'call, 'randomize,
                'rem, 'input, 'lineinput, 'open, 'close, 'write].

; The label a jump names. A word or a number, and nothing else -- the error
; here is worth naming because the mistake is almost always a later BASIC:
; `GOTO` in QBasic takes a label, and in every BASIC before it a line number,
; and here those are the same thing wearing different clothes.
sola:labelName := { | t |
    t := self:takeToken.
    t:isNil:ifTrue({ self:fail("GOTO needs a label to jump to") }).
    t:kind:equals('word):or({ t:kind:equals('number) }):ifFalse({
        self:fail("'{}' is not a label":fill([t:text])) }).
    self:expectEndOfLine("GOTO").
    t:text }.

sola:expectEndOfLine := { what |
    self:atEndOfLine:ifFalse({
        self:fail("{} takes nothing after it, and there is '{}'"
            :fill([what, self:peekToken:text])) }) }.

sola:parseAssignment := { st | | t |
    t := self:takeToken.
    t:text:equals("LET"):ifTrue({ t := self:takeToken }).
    t:isNil:or({ t:kind:equals('word):not }):ifTrue({
        self:fail("a statement starts with a keyword or a variable") }).
    ; `a(i) = v` and `Greet (x)` both begin with a name and a bracket, and only
    ; the `=` afterwards tells them apart -- so the subscripts are read, and put
    ; back if what follows is not an assignment.
    self:nextIs("("):ifTrue({ | mark, subs |
        mark := self:cursor.
        subs := self:parseCallArguments.
        self:nextIs("="):ifElse(
            { self:takeToken.
              st:kind := 'arrayset.
              st:name := t:text.
              st:subscripts := subs.
              st:expr := self:parseExpression.
              self:expectEndOfLine("an assignment") },
            { self:cursor := mark }) }).

    st:kind:equals('arrayset):ifElse({ nil }, {
    self:nextIs("="):ifElse(
        { self:takeToken.
          st:kind := 'let.
          st:name := t:text.
          st:expr := self:parseExpression.
          self:expectEndOfLine("an assignment") },
        { ; Not an assignment, so it is a call written without CALL --
          ; `Greet "world"`, which is how BASIC has always spelt one.
          st:kind := 'call.
          st:name := t:text.
          st:items := self:parseArguments(false).
          self:expectEndOfLine("a call") }) }) }.

; `IF <condition> THEN GOTO <label>`, and `THEN <label>` for short, which is
; what every BASIC has allowed since there were labels to write.
; ---------------------------------------------------------------------------
; The statements, one block each
;
; Each takes the compiler and the statement being filled in, and reads from the
; cursor the keyword was just taken off.

parsers:atPut("REM", { m, st | st:kind := 'rem }).

parsers:atPut("PRINT", { m, st | m:parsePrint(st) }).

parsers:atPut("GOTO", { m, st | st:kind := 'goto. st:target := m:labelName }).

; `END`, `END IF` and `END SELECT` are one keyword and three statements, which
; is why the bare one is the last arm rather than the first.
parsers:atPut("END", { m, st |
    [ { m:nextIs("IF") },
        { m:takeToken. st:kind := 'endif. m:expectEndOfLine("END IF") },
      { m:nextIs("SELECT") },
        { m:takeToken. st:kind := 'endselect. m:expectEndOfLine("END SELECT") },
      { m:nextIs("SUB") },
        { m:takeToken. st:kind := 'endsub. m:expectEndOfLine("END SUB") },
      { m:nextIs("FUNCTION") },
        { m:takeToken. st:kind := 'endfunction. m:expectEndOfLine("END FUNCTION") },
        { st:kind := 'end. m:expectEndOfLine("END") } ]:ifElseIf }).

; ---------------------------------------------------------------------------
; IF, in both of its shapes
;
; **What follows THEN decides which.** Nothing after it on the line opens a
; block that runs until `END IF`; anything else is the one-line form, which
; holds a single statement and an optional `ELSE`. That is QBasic's rule and
; every BASIC's since labels arrived, and the two forms share nothing but the
; condition.

parsers:atPut("IF", { m, st |
    st:expr := m:parseExpression.
    m:nextIs("THEN"):ifFalse({ m:fail("IF needs THEN") }).
    m:takeToken.
    m:atEndOfLine:ifElse(
        { st:kind := 'ifblock },
        { st:kind := 'ifline.
          m:stopAtElse := true.
          st:then := m:parseInlineStatement.
          m:nextIs("ELSE"):ifTrue({
              m:takeToken.
              st:otherwise := m:parseInlineStatement }).
          m:stopAtElse := false.
          m:expectEndOfLine("a one-line IF") }) }).

parsers:atPut("ELSEIF", { m, st |
    st:kind := 'elseif.
    st:expr := m:parseExpression.
    m:nextIs("THEN"):ifFalse({ m:fail("ELSEIF needs THEN") }).
    m:takeToken.
    m:expectEndOfLine("ELSEIF") }).

parsers:atPut("ELSE", { m, st | st:kind := 'else. m:expectEndOfLine("ELSE") }).

; **A bare label after THEN is a GOTO**, which is what `IF X < 5 THEN Top` has
; meant in every BASIC that had labels, and what `THEN 100` meant in every one
; before that. It is a jump and not an expression statement, because a bare
; name is not a statement in this language and so there is nothing else it
; could be.
sola:parseInlineStatement := { | sub, t, next, lead |
    t := self:peekToken.
    lead := t:isNil:ifElse({ "the end of the line" }, { t:text }).
    sub := stmt:new.
    sub:line := self:atLine.
    next := self:tokenAt(self:cursor:add(#1)).
    t:notNil:and({ t:kind:equals('number):or({
            t:kind:equals('word):and({ parsers:includes(t:text):not }) }) })
        :and({ next:isNil:or({ next:text:equals("ELSE") }) }):ifElse(
        { sub:kind := 'goto. sub:target := self:takeToken:text },
        { self:parseStatement(sub) }).
    inlineKinds:indexOf(sub:kind):isNil:ifTrue({
        self:fail("'{}' cannot go on a one-line IF"
            :fill([lead])) }).

    ; **`IF c THEN a : b` runs both when c is true**, which is QuickBASIC's
    ; answer and was measured rather than assumed. So everything up to the end
    ; of the line -- or to an ELSE -- belongs to the arm, and a group holds it.
    self:nextIs(":"):ifTrue({ | group |
        group := stmt:new.
        group:kind := 'group.
        group:line := sub:line.
        group:body := array:new:add(sub).
        { self:nextIs(":") }:whileTrue({
            self:takeToken.
            self:atEndOfLine:ifFalse({
                group:body:add(self:parseInlineStatement) }) }).
        sub := group }).
    sub }.

; ---------------------------------------------------------------------------
; SELECT CASE
;
; The subject is evaluated **once** and kept, which is the standard's rule
; everywhere it is written down and the only one that makes sense: a subject
; with a side effect tested against six cases would otherwise happen six times.

parsers:atPut("SELECT", { m, st |
    m:nextIs("CASE"):ifFalse({ m:fail("SELECT needs CASE after it") }).
    m:takeToken.
    st:kind := 'select.
    st:expr := m:parseExpression.
    m:expectEndOfLine("SELECT CASE") }).

parsers:atPut("CASE", { m, st | | more |
    m:nextIs("ELSE"):ifElse(
        { m:takeToken. st:kind := 'caseelse. m:expectEndOfLine("CASE ELSE") },
        { st:kind := 'case.
          st:alternatives := array:new.
          more := true.
          { more }:whileTrue({
              st:alternatives:add(m:parseAlternative).
              m:nextIs(","):ifElse({ m:takeToken }, { more := false }) }).
          m:expectEndOfLine("CASE") }) }).

; One of the three shapes a CASE takes: a value, a range, or a comparison.
sola:parseAlternative := { | op, low |
    self:nextIs("IS"):ifElse(
        { self:takeToken.
          op := self:takeToken.
          op:isNil:or({ comparisons:indexOf(op:text):isNil }):ifTrue({
              self:fail("CASE IS needs one of = <> < <= > >=") }).
          ["is", op:text, self:parseExpression] },
        { low := self:parseExpression.
          self:nextIs("TO"):ifElse(
              { self:takeToken. ["range", low, self:parseExpression] },
              { ["value", low] }) }) }.

; ---------------------------------------------------------------------------
; FOR and NEXT
;
;     FOR <variable> = <expression> TO <expression> [STEP <expression>]
;     NEXT [<variable>[, <variable>]...]
;
; The limit and the step are evaluated **once, when the loop starts**, which is
; the standard's rule rather than an optimisation: `FOR I = 1 TO N` where the
; body assigns to `N` runs the number of times `N` named at the start.

parsers:atPut("FOR", { m, st | | t |
    st:kind := 'for.
    t := m:takeToken.
    t:isNil:or({ t:kind:equals('word):not }):ifTrue({
        m:fail("FOR needs a variable") }).
    st:name := t:text.
    m:nextIs("="):ifFalse({ m:fail("FOR needs an = after the variable") }).
    m:takeToken.
    st:expr := m:parseExpression.
    m:nextIs("TO"):ifFalse({ m:fail("FOR needs TO") }).
    m:takeToken.
    st:limit := m:parseExpression.
    m:nextIs("STEP"):ifTrue({ m:takeToken. st:step := m:parseExpression }).
    m:expectEndOfLine("FOR") }).

; `NEXT`, `NEXT I` and `NEXT J, I` -- the last closing two loops on one line,
; innermost first, which is the order they are written in and the order they
; have to close in.
parsers:atPut("NEXT", { m, st | | t |
    st:kind := 'next.
    st:items := array:new.
    { m:atEndOfLine:not }:whileTrue({
        t := m:takeToken.
        t:kind:equals('word):ifFalse({ m:fail("NEXT takes variable names") }).
        st:items:add(t:text).
        m:atEndOfLine:ifFalse({
            m:nextIs(","):ifFalse({ m:fail("NEXT separates its variables with commas") }).
            m:takeToken.
            m:atEndOfLine:ifTrue({ m:fail("a comma with no variable after it") }) }) }) }).

; ---------------------------------------------------------------------------
; DO, LOOP, WHILE and WEND
;
; `DO` takes its condition at either end or at neither, and **not at both** --
; a loop that tests twice is two loops and the reader cannot tell which one is
; meant. `WHILE`/`WEND` is `DO WHILE`/`LOOP` under another spelling, kept
; because listings have it.

parsers:atPut("DO", { m, st | st:kind := 'do. m:parseLoopTest(st, "DO") }).
parsers:atPut("LOOP", { m, st | st:kind := 'loop. m:parseLoopTest(st, "LOOP") }).

sola:parseLoopTest := { st, what |
    [ { self:nextIs("WHILE") },
        { self:takeToken. st:test := 'while. st:expr := self:parseExpression },
      { self:nextIs("UNTIL") },
        { self:takeToken. st:test := 'until. st:expr := self:parseExpression },
        { st:test := 'none } ]:ifElseIf.
    self:expectEndOfLine(what) }.

parsers:atPut("WHILE", { m, st |
    st:kind := 'while.
    st:expr := m:parseExpression.
    m:expectEndOfLine("WHILE") }).

parsers:atPut("WEND", { m, st | st:kind := 'wend. m:expectEndOfLine("WEND") }).

parsers:atPut("EXIT", { m, st | | t |
    st:kind := 'exit.
    t := m:takeToken.
    t:isNil:or({ ["FOR", "DO", "SUB", "FUNCTION"]:indexOf(t:text):isNil }):ifTrue({
        m:fail("EXIT takes FOR, DO, SUB or FUNCTION") }).
    st:target := t:text.
    m:expectEndOfLine("EXIT") }).

; ---------------------------------------------------------------------------
; SUB and FUNCTION
;
; A procedure is not a statement that runs where it is written. It is collected
; out of the listing before anything is emitted, compiled into a chunk of its
; own, and bound to its name before the module's first line runs -- which is why
; a listing may call something defined below it and `DECLARE` has nothing to do.

parsers:atPut("SUB", { m, st |
    st:kind := 'sub.
    st:name := m:plainName("SUB").
    st:items := m:parseParameters(st).
    m:expectEndOfLine("SUB") }).

parsers:atPut("FUNCTION", { m, st |
    st:kind := 'function.
    st:name := m:plainName("FUNCTION").
    st:items := m:parseParameters(st).
    m:expectEndOfLine("FUNCTION") }).

; `DECLARE` is read and dropped. QBasic needs one for a procedure used before it
; is defined and its editor writes them for you; this resolves every name in a
; pass over the whole listing first, so there is nothing for it to say.
parsers:atPut("DECLARE", { m, st |
    st:kind := 'rem.
    m:cursor := m:tokens:size:add(#1) }).

parsers:atPut("CALL", { m, st |
    st:kind := 'call.
    st:name := m:plainName("CALL").
    st:items := m:nextIs("("):ifElse({ m:parseArguments(true) }, { m:parseArguments(false) }).
    m:expectEndOfLine("CALL") }).

; ---------------------------------------------------------------------------
; OPTION BASE, CONST and DIM
;
; All three are read as the listing is read rather than when it is emitted,
; because each of them answers a question the next line may ask: what the lowest
; subscript is, what a name stands for, and how big an array is.

; ---------------------------------------------------------------------------
; INPUT and LINE INPUT
;
;     INPUT ["prompt"{;|,}] variable[, variable]...
;     LINE INPUT ["prompt"{;|,}] variable$
;
; **A prompt followed by `;` gets a question mark after it and one followed by
; `,` does not**, which is BASIC's rule and the only thing the two separators
; do here. No prompt at all still gets the question mark, because that is what
; `INPUT N` has always shown.
;
; `INPUT` reads one line and splits it on commas, so several variables are
; filled from one answer; `LINE INPUT` reads the line whole, commas and all.

; ---------------------------------------------------------------------------
; Files
;
;     OPEN <path> FOR INPUT|OUTPUT|APPEND AS #<n>
;     CLOSE [#<n>[, #<n>]...]
;     PRINT #<n>, ...      WRITE #<n>, ...
;     INPUT #<n>, ...      LINE INPUT #<n>, <variable$>
;     EOF(<n>)
;
; Sequential only. There is no streaming underneath -- the machine reads and
; writes whole files -- so a channel open for reading holds the file and one
; open for writing holds what has been written until it is closed.

modes := dictionary:new.
modes:atPut("INPUT", #1).
modes:atPut("OUTPUT", #2).
modes:atPut("APPEND", #3).

parsers:atPut("OPEN", { m, st | | t |
    st:kind := 'open.
    st:expr := m:parseExpression.
    m:nextIs("FOR"):ifFalse({ m:fail("OPEN needs FOR and a mode") }).
    m:takeToken.
    t := m:takeToken.
    t:isNil:or({ modes:includes(t:text):not }):ifTrue({
        m:fail("OPEN takes FOR INPUT, FOR OUTPUT or FOR APPEND") }).
    st:test := modes:at(t:text).
    m:nextIs("AS"):ifFalse({ m:fail("OPEN needs AS and a file number") }).
    m:takeToken.
    st:channel := m:parseChannel.
    m:expectEndOfLine("OPEN") }).

parsers:atPut("CLOSE", { m, st | | more |
    st:kind := 'close.
    st:items := array:new.
    m:atEndOfLine:ifFalse({
        more := true.
        { more }:whileTrue({
            st:items:add(m:parseChannel).
            m:nextIs(","):ifElse({ m:takeToken }, { more := false }) }) }).
    m:expectEndOfLine("CLOSE") }).

parsers:atPut("WRITE", { m, st | | more |
    st:kind := 'write.
    st:items := array:new.
    m:nextIs("#"):ifTrue({
        st:channel := m:parseChannel.
        m:nextIs(","):ifTrue({ m:takeToken }) }).
    m:atEndOfLine:ifFalse({
        more := true.
        { more }:whileTrue({
            st:items:add(m:parseExpression).
            m:nextIs(","):ifElse({ m:takeToken }, { more := false }) }) }).
    m:expectEndOfLine("WRITE") }).

; `#1`, and the `#` is not part of the number -- a file number is an expression
; like any other, so `#N%` names one too.
sola:parseChannel := {
    self:nextIs("#"):ifFalse({ self:fail("a file number is written '#1'") }).
    self:takeToken.
    self:parseExpression }.

parsers:atPut("INPUT", { m, st |
    st:kind := 'input.
    m:nextIs("#"):ifElse(
        { st:channel := m:parseChannel.
          m:nextIs(","):ifFalse({ m:fail("INPUT # needs a comma after the number") }).
          m:takeToken },
        { m:parseInputPrompt(st) }).
    st:items := m:parseInputTargets.
    m:expectEndOfLine("INPUT") }).

; **What `INPUT` fills may be an array element**, which is what a program
; reading records into parallel arrays wants and is the first thing one asked
; for. A target is a name, and a name may be followed by subscripts.
sola:parseInputTargets := { | targets, more, name, subs |
    targets := array:new.
    more := true.
    { more }:whileTrue({
        name := self:plainName("a variable").
        subs := nil.
        self:nextIs("("):ifTrue({ subs := self:parseCallArguments }).
        targets:add([name, subs]).
        self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }).
    targets }.

parsers:atPut("LINE", { m, st |
    m:nextIs("INPUT"):ifFalse({ m:fail("LINE takes INPUT after it") }).
    m:takeToken.
    st:kind := 'lineinput.
    m:nextIs("#"):ifElse(
        { st:channel := m:parseChannel.
          m:nextIs(","):ifFalse({
              m:fail("LINE INPUT # needs a comma after the number") }).
          m:takeToken },
        { m:parseInputPrompt(st) }).
    st:items := [m:parseInputTargets:at(#1)].
    m:expectEndOfLine("LINE INPUT") }).

sola:parseInputPrompt := { st | | t |
    st:test := 'none.
    t := self:peekToken.
    t:notNil:and({ t:kind:equals('string) }):ifTrue({
        st:expr := stringNode:value(self:takeToken:text).
        self:nextIs(";"):ifElse(
            { self:takeToken. st:test := 'semi },
            { self:nextIs(","):ifElse(
                { self:takeToken. st:test := 'comma },
                { self:fail("a prompt is followed by ';' or ','") }) }) }) }.

parsers:atPut("OPTION", { m, st |
    st:kind := 'rem.
    m:nextIs("BASE"):ifFalse({ m:fail("OPTION takes BASE") }).
    m:takeToken.
    m:setOptionBase(m:constantInteger(m:parseExpression)).
    m:expectEndOfLine("OPTION BASE") }).

parsers:atPut("CONST", { m, st | | more, name |
    st:kind := 'rem.
    more := true.
    { more }:whileTrue({
        name := m:plainName("CONST").
        m:nextIs("="):ifFalse({ m:fail("CONST needs an = after the name") }).
        m:takeToken.
        m:defineConstant(name, m:parseExpression).
        m:nextIs(","):ifElse({ m:takeToken }, { more := false }) }).
    m:expectEndOfLine("CONST") }).

; `DIM a(10)`, `DIM Grid(1 TO 8, 1 TO 8) AS INTEGER`, `DIM SHARED Names$(100)`,
; and `DIM Total AS DOUBLE` for a plain variable.
parsers:atPut("DIM", { m, st | | more |
    st:kind := 'dim.
    st:items := array:new.
    st:bounds := array:new.
    st:shared := m:nextIs("SHARED"):ifElse({ m:takeToken. true }, { false }).
    more := true.
    { more }:whileTrue({
        m:parseOneDim(st).
        m:nextIs(","):ifElse({ m:takeToken }, { more := false }) }).
    m:expectEndOfLine("DIM") }).

sola:parseOneDim := { st | | name, bounds, low, more |
    name := self:plainName("DIM").
    bounds := nil.
    self:nextIs("("):ifTrue({
        self:takeToken.
        bounds := array:new.
        more := true.
        { more }:whileTrue({
            low := self:constantInteger(self:parseExpression).
            ; `DIM a(10)` runs from OPTION BASE to 10; `DIM a(1 TO 10)` says both.
            self:nextIs("TO"):ifElse(
                { self:takeToken.
                  bounds:add([low, self:constantInteger(self:parseExpression)]) },
                { bounds:add([self:optionBase, low]) }).
            self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }).
        self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
        self:takeToken.
        bounds:size:greaterThan(#8):ifTrue({
            self:fail("{} has {} dimensions, and eight is the most"
                :fill([name, bounds:size])) }) }).
    self:nextIs("AS"):ifTrue({ self:takeToken. self:declareType(name, self:typeName) }).
    st:items:add(name).
    st:bounds:add(bounds).
    bounds:isNil:ifElse(
        { st:shared:and({ self:sharedNames:indexOf(name):isNil }):ifTrue({
              self:sharedNames:add(name) }) },
        { self:declareArray(name, bounds, st:shared) }) }.

; `()` with nothing between them, consumed if it is there.
sola:emptyBrackets := {
    self:nextIs("("):and({ | n | n := self:tokenAt(self:cursor:add(#1)).
                                 n:notNil:and({ n:text:equals(")") }) }):ifElse(
        { self:takeToken. self:takeToken. true },
        { false }) }.

; An argument written `a()` is the array itself rather than one of its elements.
sola:maybeArrayRef := { | t, after, closing |
    t := self:peekToken.
    after := self:tokenAt(self:cursor:add(#1)).
    closing := self:tokenAt(self:cursor:add(#2)).
    t:notNil:and({ t:kind:equals('word) })
        :and({ after:notNil:and({ after:text:equals("(") }) })
        :and({ closing:notNil:and({ closing:text:equals(")") }) }):ifElse(
        { self:takeToken. self:takeToken. self:takeToken.
          arrayRefNode:value(t:text) },
        { self:parseExpression }) }.

sola:typeName := { | t |
    t := self:takeToken.
    t:isNil:ifTrue({ self:fail("AS needs a type") }).
    [ { ["INTEGER", "LONG"]:indexOf(t:text):notNil }, { 'integer },
      { t:text:equals("DOUBLE") },                    { 'double },
      { t:text:equals("STRING") },                    { 'string },
      { t:text:equals("SINGLE") },
        { self:fail("SolaBasic has no SINGLE -- see docs/SOLABASIC.md. "
            :concat("DOUBLE is the one it has.")) },
        { self:fail("'{}' is not a type: INTEGER, LONG, DOUBLE or STRING"
            :fill([t:text])) } ]:ifElseIf }.

parsers:atPut("RANDOMIZE", { m, st |
    st:kind := 'randomize.
    st:expr := m:parseExpression.
    m:expectEndOfLine("RANDOMIZE") }).

parsers:atPut("DEFINT", { m, st | m:parseDefaults(st, 'integer) }).
parsers:atPut("DEFLNG", { m, st | m:parseDefaults(st, 'integer) }).
parsers:atPut("DEFDBL", { m, st | m:parseDefaults(st, 'double) }).
parsers:atPut("DEFSTR", { m, st | m:parseDefaults(st, 'string) }).

; `DEFINT A-N, X` -- the default type for every name starting with one of those
; letters. It applies to the whole listing wherever it is written, which is one
; fewer rule to remember than QBasic's, where it applies from where it stands.
sola:parseDefaults := { st, t | | more, first, last, i |
    st:kind := 'rem.
    more := true.
    { more }:whileTrue({
        first := self:defLetter.
        last := first.
        self:nextIs("-"):ifTrue({ self:takeToken. last := self:defLetter }).
        i := letters:indexOf(first).
        i:greaterThan(letters:indexOf(last)):ifTrue({
            self:fail("{}-{} is not a range of letters":fill([first, last])) }).
        { i:lessOrEqual(letters:indexOf(last)) }:whileTrue({
            self:defaultTypes:atPut(letters:copyFrom(i, i), t).
            i := i:add(#1) }).
        self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }).
    self:expectEndOfLine("a DEF") }.

sola:defLetter := { | t |
    t := self:takeToken.
    t:isNil:or({ t:kind:equals('word):not }):or({ t:text:size:notEquals(#1) })
        :ifTrue({ self:fail("a DEF names single letters, like A-N") }).
    t:text }.

parsers:atPut("SHARED", { m, st |
    st:kind := 'shared. st:items := m:nameList. m:expectEndOfLine("SHARED") }).

parsers:atPut("STATIC", { m, st |
    st:kind := 'static. st:items := m:nameList. m:expectEndOfLine("STATIC") }).

sola:plainName := { what | | t |
    t := self:takeToken.
    t:isNil:or({ t:kind:equals('word):not }):ifTrue({
        self:fail("{} needs a name":fill([what])) }).
    parsers:includes(t:text):or({ builtins:includes(t:text) }):ifTrue({
        self:fail("'{}' is already a keyword or a supplied function"
            :fill([t:text])) }).
    t:text }.

; `SHARED total` and `SHARED counts()` -- the brackets say it is an array and
; are otherwise empty, which is how BASIC names one without subscripting it.
sola:nameList := { | names, more |
    names := array:new.
    more := true.
    { more }:whileTrue({
        names:add(self:plainName("this")).
        self:nextIs("("):ifTrue({
            self:takeToken.
            self:nextIs(")"):ifFalse({ self:fail("an array is named as 'a()'") }).
            self:takeToken }).
        self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }).
    names }.

; A parameter list, in brackets or not -- `SUB Greet (name)` and `SUB Greet name`
; are the same declaration, as they are in QBasic.
sola:parseParameters := { st | | names, more, bracketed |
    names := array:new.
    st:arrayParams := array:new.
    bracketed := self:nextIs("(").
    bracketed:ifTrue({ self:takeToken }).
    self:atEndOfLine:not:and({ self:nextIs(")"):not }):ifTrue({
        more := true.
        { more }:whileTrue({
            names:add(self:plainName("a parameter")).
            ; `SUB Sort (a())` -- the empty brackets say the parameter is an
            ; array, which is how BASIC names one without subscripting it.
            st:arrayParams:add(self:emptyBrackets).
            self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }) }).
    bracketed:ifTrue({
        self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
        self:takeToken }).
    names }.

; The arguments of a statement call.
;
; **Only `CALL`'s brackets are an argument list.** Written without `CALL`, a
; leading `(` belongs to the first argument instead, so `Double (n)` passes a
; *copy* of `n` where `CALL Double(n)` passes `n` itself. That reads like a
; quibble and is the whole of how QBasic spells by-value, so it is kept.
sola:parseArguments := { bracketed | | args, more |
    args := array:new.
    bracketed:ifTrue({
        self:nextIs("("):ifFalse({ self:fail("CALL needs brackets round its arguments") }).
        self:takeToken }).
    self:atEndOfLine:not:and({ self:nextIs(")"):not }):ifTrue({
        more := true.
        { more }:whileTrue({
            args:add(self:maybeArrayRef).
            self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }) }).
    bracketed:ifTrue({
        self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
        self:takeToken }).
    args }.

; The arguments of a call inside an expression, where they are not optional.
sola:parseCallArguments := { | args, more |
    self:takeToken.
    args := array:new.
    self:nextIs(")"):ifFalse({
        more := true.
        { more }:whileTrue({
            args:add(self:maybeArrayRef).
            self:nextIs(","):ifElse({ self:takeToken }, { more := false }) }) }).
    self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
    self:takeToken.
    args }.

; **The separator after each item is part of the statement**, not punctuation
; to be dropped: a comma moves to the next print zone, a semicolon moves
; nowhere, and one at the end of the line holds the line open for the next
; PRINT to carry on.
sola:parsePrint := { st | | t |
    st:kind := 'print.
    st:items := array:new.
    st:seps := array:new.
    self:nextIs("#"):ifTrue({
        st:channel := self:parseChannel.
        self:nextIs(","):ifFalse({ self:fail("PRINT # needs a comma after the number") }).
        self:takeToken }).
    self:nextIs("USING"):ifTrue({
        self:takeToken.
        st:using := self:parseExpression.
        self:nextIs(";"):ifFalse({
            self:fail("PRINT USING wants ';' between the format and the items") }).
        self:takeToken }).
    { self:atEndOfLine:not }:whileTrue({
        st:items:add(self:parseExpression).
        self:atEndOfLine:ifElse(
            { st:seps:add("none") },
            { t := self:peekToken.
              t:text:equals(";"):or({ t:text:equals(",") }):ifElse(
                  { st:seps:add(self:takeToken:text:equals(","):ifElse(
                        { "comma" }, { "semi" })).
                    self:atEndOfLine:ifTrue({
                        ; a separator with nothing after it keeps the line open
                        st:items:add(nil). st:seps:add("open") }) },
                  { self:fail("PRINT separates its items with ';' or ','") }) }) }) }.

; ---------------------------------------------------------------------------
; Expressions
;
; Four levels: comparison, then additive, then multiplicative, then unary minus
; and a primary. Comparison is lowest, which is what lets `IF A + 1 < B THEN`
; read the way it looks.

; Ten levels, loosest first, which is BASIC's table:
;
;     OR XOR
;     AND
;     NOT              (unary)
;     = <> < <= > >=
;     + -
;     MOD
;     \\
;     * /
;     -                (unary)
;     ^                (right-associative, and tighter than unary minus, so
;                       -2 ^ 2 is -(2 ^ 2) and not (-2) ^ 2)

sola:parseExpression := { self:parseOr }.

sola:parseOr := { | left, op |
    left := self:parseAnd.
    { self:peekToken:notNil:and({
        ["OR", "XOR"]:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseAnd) }).
    left }.

sola:parseAnd := { | left |
    left := self:parseNot.
    { self:nextIs("AND") }:whileTrue({
        self:takeToken.
        left := binaryNode:value("AND", left, self:parseNot) }).
    left }.

sola:parseNot := {
    self:nextIs("NOT"):ifElse(
        { self:takeToken. notNode:value(self:parseNot) },
        { self:parseComparison }) }.

sola:parseComparison := { | left, op |
    left := self:parseAdditive.
    { self:peekToken:notNil:and({
        comparisons:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseAdditive) }).
    left }.

sola:parseAdditive := { | left, op |
    left := self:parseMod.
    { self:peekToken:notNil:and({
        additive:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseMod) }).
    left }.

sola:parseMod := { | left |
    left := self:parseIntegerDivide.
    { self:nextIs("MOD") }:whileTrue({
        self:takeToken.
        left := binaryNode:value("MOD", left, self:parseIntegerDivide) }).
    left }.

sola:parseIntegerDivide := { | left |
    left := self:parseMultiplicative.
    { self:nextIs("\\") }:whileTrue({
        self:takeToken.
        left := binaryNode:value("\\", left, self:parseMultiplicative) }).
    left }.

sola:parseMultiplicative := { | left, op |
    left := self:parseUnary.
    { self:peekToken:notNil:and({
        multiplicative:indexOf(self:peekToken:text):notNil }) }:whileTrue({
        op := self:takeToken:text.
        left := binaryNode:value(op, left, self:parseUnary) }).
    left }.

sola:parseUnary := {
    self:nextIs("-"):ifElse(
        { self:takeToken. negateNode:value(self:parseUnary) },
        { self:parsePower }) }.

sola:parsePower := { | base |
    base := self:parsePrimary.
    self:nextIs("^"):ifElse(
        { self:takeToken. binaryNode:value("^", base, self:parseUnary) },
        { base }) }.

sola:parsePrimary := { | t, inner |
    t := self:takeToken.
    t:isNil:ifTrue({ self:fail("an expression stops short") }).
    [ { t:kind:equals('number) },
        ; **A literal with no point and no exponent is an Integer**, which is
        ; QBasic's rule and the reason `7 / 2` and `7 \\ 2` differ without
        ; anything being declared -- unless the literal says its own type.
        { t:suffix:notNil:ifElse(
            { suffixTypes:at(t:suffix):equals('integer):ifElse(
                { numberNode:value(t:text:asFloat:rounded, 'integer) },
                { numberNode:value(t:text:asFloat, 'double) }) },
            { t:text:indexOf("."):isNil
                :and({ t:text:asUppercase:indexOf("E"):isNil }):ifElse(
                { numberNode:value(t:text:asInteger, 'integer) },
                { numberNode:value(t:text:asFloat, 'double) }) }) },
      { t:kind:equals('based) }, { numberNode:value(t:text:asInteger, 'integer) },
      { t:kind:equals('string) }, { stringNode:value(t:text) },
      { t:text:equals("(") },
        { inner := self:parseExpression.
          self:nextIs(")"):ifFalse({ self:fail("a '(' was never closed") }).
          self:takeToken.
          inner:grouped := true.
          inner },
      { t:kind:equals('word) },
        ; **A function of no arguments is written without brackets**, so a bare
        ; `RND` is a call and not a variable. Reading it as a variable is what
        ; it was doing, which meant `r = RND` quietly read an uninitialised name
        ; and answered nought -- and the test written for it passed, because
        ; nought is in the range it checked.
        { self:nextIs("("):ifElse(
            { callNode:value(t:text, self:parseCallArguments) },
            { builtins:includes(t:text)
                :and({ builtins:at(t:text):at(#1):size:equals(#0) }):ifElse(
                { callNode:value(t:text, array:new) },
                { variableNode:value(t:text) }) }) },
        { self:fail("'{}' cannot start an expression":fill([t:text])) }
    ]:ifElseIf }.

; ---------------------------------------------------------------------------
; Emitting
;
; Bytes go into an array and are handed to `sob.sol` at the end. Every operand
; wider than a byte is little-endian, which is the format's rule since version
; 14 and the reason there was a version 14.

sola:here := { self:code:size }.
sola:byte := { b | self:code:add(b:bitAnd(#255)) }.
sola:u16 := { n | self:byte(n). self:byte(n:shiftRight(#8)) }.

; Names are interned **when the instruction mentioning them is emitted**, so the
; table's order is the order the code refers to things. Selectors, global names
; and string literals all share it, which is the format's doing and not a
; shortcut here.
sola:nameFor := { text |
    self:nameIndex:includes(text):ifElse(
        { self:nameIndex:at(text) },
        { | i | i := self:names:size.
                self:names:add(text).
                self:nameIndex:atPut(text, i).
                i }) }.

; Constants are shared by value **and type**, which matters in a language that
; has both -- though this stage has only floats, so the key carries the tag
; against the day it does not.
sola:constFor := { tag, value | | key |
    key := tag:asString:concat(":"):concat(value:asString).
    self:constIndex:includes(key):ifElse(
        { self:constIndex:at(key) },
        { | i | i := self:constants:size.
                self:constants:add([tag, value]).
                self:constIndex:atPut(key, i).
                i }) }.

sola:emitConst  := { v | self:byte(CONST).   self:u16(self:constFor(#2, v)) }.
sola:emitString := { s | self:byte(STRING).  self:u16(self:nameFor(s)) }.
sola:emitGlobal := { s | self:byte(GLOBAL).  self:u16(self:nameFor(s)) }.
sola:emitStore  := { s | self:byte(SETGLOB). self:u16(self:nameFor(s)) }.
sola:emitSend   := { sel, argc |
    self:byte(SEND). self:u16(self:nameFor(sel)). self:byte(argc) }.
sola:emitPop    := { self:byte(POP) }.
sola:emitNil    := { self:byte(NIL) }.

; An **integer** constant, which this language has only one use for: the
; subscript of a one-element array, which is what a variable passed by
; reference is kept in. Everything a SolaBasic program computes is a Double.
sola:emitIntConst := { n | self:byte(CONST). self:u16(self:constFor(#1, n)) }.

; A numeric constant of whichever type is wanted. `#0` and `0.0` are two
; constants and two types, and pushing the wrong one is a program that runs and
; is wrong -- the trap experiment/compile.sol names in ideas.md.
; The same number as a Double, whichever it arrived as. The compiler holds a
; literal step as whatever the listing wrote, and `#1` and `1.0` are two types
; that do not compare with each other.
sola:asDouble := { v | v:respondsTo('asFloat):ifElse({ v:asFloat }, { v }) }.

sola:emitZero := { t |
    t:equals('string):ifElse({ self:emitString("") }, { self:emitNumber(#0, t) }) }.

sola:emitNumber := { v, t |
    t:equals('integer):ifElse(
        { self:emitIntConst(v:respondsTo('rounded):ifElse({ v:rounded }, { v })) },
        { self:emitConst(self:asDouble(v)) }) }.

; A frame slot. `u8`, because a frame of more than 255 slots is refused before
; it runs and the format says so by giving the operand one byte.
sola:emitLocal    := { slot | self:byte(LOCAL).    self:byte(slot) }.
sola:emitSetLocal := { slot | self:byte(SETLOCAL). self:byte(slot) }.

; ---------------------------------------------------------------------------
; A place to put a value that is needed twice
;
; There is no instruction that duplicates the top of the stack, so anything
; wanting its argument twice -- `SGN`, `MOD`, `INSTR` -- has to put it
; somewhere. A scratch slot is that somewhere, handed out by nesting depth so
; that `SGN(SGN(x))` gets two and two uses in a row share one.

sola:takeScratch := { | slot |
    self:scratchDepth := self:scratchDepth:add(#1).
    self:scratchSlots:size:lessThan(self:scratchDepth):ifTrue({
        self:scratchSlots:add(self:newSlot("scratch")) }).
    self:scratchSlots:at(self:scratchDepth) }.

sola:dropScratch := { self:scratchDepth := self:scratchDepth:sub(#1) }.

; Evaluate something into a scratch slot and leave nothing on the stack.
sola:intoScratchAs := { node, wanted | | slot |
    slot := self:takeScratch.
    self:emitTyped(node, wanted).
    self:emitSetLocal(slot).
    self:emitPop.
    slot }.

; ---------------------------------------------------------------------------
; Arrays, constants, and the lowest subscript
;
; All three are program-wide rather than per-unit: an array declared at module
; level is one array however many procedures see it, a `CONST` means the same
; everywhere, and `OPTION BASE` is asked once.

sola:arrays := nil.         ; name -> [bounds, shared]
; **`DIM SHARED` on a plain variable, which is not the same list as the arrays.**
; Recording the flag only on an array was the first version of this, and it made
; `DIM SHARED Total` compile and then quietly give every procedure a local of its
; own -- found by writing a program that wanted one.
sola:sharedNames := nil.
sola:declaredTypes := nil.  ; name -> type, from an AS clause
sola:optionBase := #0.
sola:baseFixed := false.

sola:setOptionBase := { n |
    self:baseFixed:ifTrue({ self:fail("OPTION BASE is asked once") }).
    ["0", "1"]:indexOf(n:asString):isNil:ifTrue({
        self:fail("OPTION BASE is 0 or 1") }).
    self:arrays:size:equals(#0):ifFalse({
        self:fail("OPTION BASE comes before the first DIM") }).
    self:optionBase := n.
    self:baseFixed := true }.

sola:declareType := { name, t | self:declaredTypes:atPut(name, t) }.

sola:declareArray := { name, bounds, shared |
    self:arrays:includes(name):ifTrue({
        self:fail("'{}' is dimensioned twice":fill([name])) }).
    self:arrays:atPut(name, [bounds, shared]) }.

; An array parameter is an array the unit knows about and the program does
; not: its bounds arrive with it, so the only thing fixed at compile time is
; where its subscripts start, which is `OPTION BASE`.
sola:arrayParams := nil.

sola:isArray := { name |
    self:arrayParams:includes(name):or({ self:arrays:includes(name) }) }.

sola:boundsOf := { name |
    self:arrayParams:includes(name):ifElse(
        { self:arrayParams:at(name) },
        { self:arrays:at(name):at(#1) }) }.

sola:arrayIsShared := { name |
    self:arrayParams:includes(name):ifElse(
        { false }, { self:arrays:at(name):at(#2) }) }.

sola:defineConstant := { name, node |
    self:constants2:includes(name):ifTrue({
        self:fail("'{}' is declared CONST twice":fill([name])) }).
    self:constants2:atPut(name, [self:constantValue(node), self:typeOfName(name)]) }.

sola:isConstant := { name | self:constants2:includes(name) }.

; ---------------------------------------------------------------------------
; Constants
;
; `CONST` is folded where it stands, and array bounds have to be: an array is
; made once, at the size the listing wrote, so `DIM a(N)` where `N` is a variable
; has no answer at the time the question is asked. A constant expression is
; therefore worked out by the compiler rather than emitted, which is what makes
; `CONST Size = 10` and `DIM a(Size)` both mean something.

sola:constants2 := nil.     ; name -> [value, type]

sola:constantValue := { n | | left, right |
    [ { n:kind:equals('number) }, { n:value },
      { n:kind:equals('string) }, { n:value },
      { n:kind:equals('variable) },
        { self:constants2:includes(n:name):ifFalse({
              self:fail("'{}' is not a constant, and this has to be one"
                  :fill([n:name])) }).
          self:constants2:at(n:name):at(#1) },
      { n:kind:equals('negate) }, { self:constantValue(n:left):negated },
      { n:kind:equals('binary) },
        { left := self:constantValue(n:left).
          right := self:constantValue(n:right).
          self:constantArithmetic(n:op, left, right) },
        { self:fail("this has to be a constant, and is not") } ]:ifElseIf }.

sola:constantArithmetic := { op, left, right |
    [ { op:equals("+") },
        { left:respondsTo('concat):ifElse(
            { left:concat(right) }, { left:add(right) }) },
      { op:equals("-") }, { left:sub(right) },
      { op:equals("*") }, { left:mul(right) },
      { op:equals("/") }, { self:asDouble(left):div(self:asDouble(right)) },
      { op:equals("\\") }, { self:asDouble(left):div(self:asDouble(right)):truncated },
        { self:fail("'{}' cannot be worked out at compile time":fill([op])) }
    ]:ifElseIf }.

sola:constantInteger := { n | | v |
    v := self:constantValue(n).
    v:respondsTo('rounded):ifElse({ v:rounded }, { v }) }.

; ---------------------------------------------------------------------------
; Types
;
; **A name carries its type.** A suffix says it outright; otherwise the `DEF`
; ranges decide by first letter; otherwise it is a Double. `A%` and `A$` are two
; variables and not one, which is QBasic's rule.

sola:defaultTypes := nil.

sola:typeOfName := { name | | last |
    self:declaredTypes:includes(name):ifElse({ self:declaredTypes:at(name) }, {
        last := name:copyFrom(name:size, name:size).
        suffixTypes:includes(last):ifElse(
            { suffixTypes:at(last) },
            { self:defaultTypes:at(name:copyFrom(#1, #1), 'double) }) }) }.

sola:isNumeric := { t | t:notEquals('string) }.

sola:unify := { a, b, where |
    a:equals('string):or({ b:equals('string) }):ifTrue({
        a:equals(b):ifFalse({
            self:fail("{} cannot mix text and numbers":fill([where])) }).
        'string:equals('string) }).
    a:equals('string):ifElse(
        { 'string },
        { a:equals('double):or({ b:equals('double) })
            :or({ a:equals('boolean) }):or({ b:equals('boolean) })
            :ifElse({ 'double }, { 'integer }) }) }.

; ---------------------------------------------------------------------------
; Typing the tree
;
; **This happens before a single byte is emitted, and it has to.** A conversion
; is an instruction that acts on the top of the stack, so turning an Integer into
; a Double must be emitted *after* that Integer is pushed and *before* the value
; beside it -- and by then it is far too late to work out that it was needed. So
; every node learns its type first, and emitting is then a walk that already
; knows where the conversions go.

sola:typeExpression := { n |
    n:kind:equals('number):ifTrue({ n:type }).
    n:kind:equals('string):ifTrue({ n:type := 'string }).
    n:kind:equals('variable):ifTrue({ n:type := self:typeOfName(n:name) }).
    n:kind:equals('arrayref):ifTrue({ n:type := self:typeOfName(n:name) }).
    n:kind:equals('call):ifTrue({
        n:args:do({ a | self:typeExpression(a) }).
        n:type := self:typeOfCall(n) }).
    n:kind:equals('variable):and({ self:isConstant(n:name) }):ifTrue({
        n:type := self:constants2:at(n:name):at(#2) }).
    n:kind:equals('variable):and({ self:isBareCall(n:name) }):ifTrue({
        n:type := self:typeOfName(n:name) }).
    n:kind:equals('negate):ifTrue({
        self:typeExpression(n:left).
        n:left:type:equals('string):ifTrue({ self:fail("text cannot be negated") }).
        n:operandType := n:left:type:equals('boolean):ifElse({ 'integer }, { n:left:type }).
        n:type := n:operandType }).
    n:kind:equals('not):ifTrue({
        self:typeExpression(n:left).
        n:left:type:equals('string):ifTrue({ self:fail("NOT wants a number") }).
        n:operandType := 'integer.
        n:type := 'integer }).
    n:kind:equals('binary):ifTrue({ self:typeBinary(n) }).
    n:type }.

sola:typeBinary := { n | | left, right |
    left := self:typeExpression(n:left).
    right := self:typeExpression(n:right).

    [ { comparisons:indexOf(n:op):notNil },
        { n:operandType := self:unify(left, right, "a comparison").
          n:type := 'boolean },
      { bitwise:indexOf(n:op):notNil },
        { n:operandType := 'integer. n:type := 'integer },
      { n:op:equals("+") },
        { n:operandType := self:unify(left, right, "'+'").
          n:type := n:operandType },
      { n:op:equals("/") },   { n:operandType := 'double.  n:type := 'double },
      { n:op:equals("^") },   { n:operandType := 'double.  n:type := 'double },
      { n:op:equals("\\") }, { n:operandType := 'integer. n:type := 'integer },
      { n:op:equals("MOD") }, { n:operandType := 'integer. n:type := 'integer },
        { n:operandType := self:unify(left, right, "arithmetic").
          n:operandType:equals('string):ifTrue({
              self:fail("text cannot be used with '{}'":fill([n:op])) }).
          n:type := n:operandType } ]:ifElseIf.
    n:type }.

; ---------------------------------------------------------------------------
; Conversions

sola:coerce := { from, to |
    from:equals(to):ifFalse({
        [ { to:equals('string) },
            { from:equals('boolean):ifTrue({ self:materialise('integer) }).
              self:emitSend("asString", #0) },
          { from:equals('string) },
            { self:fail("text cannot be used as a number here -- VAL reads one out of it") },
          { to:equals('boolean) },
            { from:equals('integer):ifElse({ self:emitIntConst(#0) }, { self:emitConst(0.0) }).
              self:emitSend("notEquals", #1) },
          { from:equals('boolean) }, { self:materialise(to) },
          { to:equals('double) },    { self:emitSend("asFloat", #0) },
                                     { self:emitSend("rounded", #0) } ]:ifElseIf }) }.

; **A comparison is `-1` or `0` when it is used as a number**, which is BASIC's
; rule and the reason there is no boolean type in the language. It costs a jump,
; so it is emitted only where the value really is used as a number -- never for
; a condition, which wants the machine's boolean as it stands.
sola:materialise := { to | | zero, done |
    zero := self:branchHole.
    to:equals('integer):ifElse({ self:emitIntConst(#-1) }, { self:emitConst(-1.0) }).
    done := self:hole.
    self:fillBranch(zero).
    to:equals('integer):ifElse({ self:emitIntConst(#0) }, { self:emitConst(0.0) }).
    self:fillJump(done) }.

; Emit a node and leave a value of the wanted type on the stack.
sola:emitTyped := { n, wanted |
    self:emitExpression(n).
    self:coerce(n:type, wanted) }.
;
; Slot 0 is the receiver -- `self` inside a block, and unused in the script,
; which has none. Everything after it is a parameter, a local, or a temporary
; this compiler needed somewhere to put.
;
; **The temporaries are slots and not hidden globals**, and that is a
; correctness matter rather than tidiness. A `FOR` keeps its limit and its step
; somewhere for the life of the loop; if that somewhere were a global, a
; recursive `FUNCTION` containing a `FOR` would have its inner call overwrite
; the outer call's limit. A slot is per-frame, so each call has its own.

sola:newSlot := { name | | slot |
    slot := self:localNames:size.
    slot:greaterThan(#255):ifTrue({
        self:fail("more than 255 names in one procedure, which is a frame the machine will not make") }).
    self:localNames:add(name).
    slot }.

sola:newLocal := { name | | slot |
    slot := self:newSlot(name).
    self:locals:atPut(name, slot).
    slot }.

sola:slotFor := { name |
    self:locals:includes(name):ifElse(
        { self:locals:at(name) },
        { self:newLocal(name) }) }.

; ---------------------------------------------------------------------------
; Where a name lives
;
; Inside a procedure a name is a slot unless `SHARED` sent it back to the module
; or `STATIC` gave it a private global; at module level everything is a global.

; A `DIM SHARED` array is one array wherever it is named, so it is a global
; everywhere rather than a local that happens to have the same name.
sola:isLocalName := { name |
    self:isArray(name):and({ self:arrayIsShared(name) })
        :or({ self:sharedNames:indexOf(name):notNil }):ifElse(
        { false },
        { self:inProcedure:and({ self:shared:indexOf(name):isNil })
            :and({ self:statics:includes(name):not }) }) }.

sola:globalNameFor := { name |
    self:statics:includes(name):ifElse(
        { self:statics:at(name) }, { name }) }.

; The variable itself, without looking inside it -- which is what a boxed one
; wants when it is being assigned to or passed on by reference.
sola:emitRawVar := { name |
    self:isLocalName(name):ifElse(
        { self:emitLocal(self:slotFor(name)) },
        { self:emitGlobal(self:globalNameFor(name)) }) }.

; ---------------------------------------------------------------------------
; A variable passed by reference lives in a box
;
; **The box is a one-element array, and the variable *is* the box** rather than
; being wrapped at the call and unwrapped after it. That is the whole of the
; by-reference machinery, and choosing it this way is what kept it small:
; passing `a` to a by-reference parameter passes the array, the callee's
; `at(#1)` and `atPut(#1, v)` reach the caller's storage directly, and there is
; no copy back, no temporary to keep alive across the call, and nothing to get
; wrong when the call is recursive.
;
; The cost is one send on every read and every write of a boxed variable, and it
; is paid only by variables that are actually passed by reference somewhere.

sola:isBoxed := { name | self:boxed:indexOf(name):notNil }.

sola:emitLoadVar := { name |
    self:emitRawVar(name).
    self:isBoxed(name):ifTrue({
        self:emitIntConst(#1).
        self:emitSend("at", #1) }) }.

; An assignment is emitted in two halves, because a boxed one puts the box and
; its subscript *before* the value and an ordinary one puts the name after it.
sola:beginAssign := { name |
    self:isBoxed(name):ifTrue({
        self:emitRawVar(name).
        self:emitIntConst(#1) }) }.

sola:endAssign := { name |
    self:isBoxed(name):ifElse(
        { self:emitSend("atPut", #2) },
        { self:isLocalName(name):ifElse(
            { self:emitSetLocal(self:slotFor(name)) },
            { self:emitStore(self:globalNameFor(name)) }) }).
    self:emitPop }.

; ---------------------------------------------------------------------------
; Every variable starts at nought
;
; **That is BASIC's rule and it has to be done rather than assumed**: a global
; this compiler never stored into is an *undefined name* to the machine, not a
; zero, and `PRINT Z` would be an error where every BASIC ever written prints
; ` 0 `. So the names a scope mentions are collected and given their nought
; before its first line runs.
;
; Skipped: parameters, which arrive with values; a FUNCTION's own name, which is
; set up as its answer; anything `SHARED`, which belongs to the module and would
; be wiped by initialising it again on every call; anything `STATIC`, which is
; initialised once at module level and would stop surviving if it were done
; here; and anything boxed, which gets its nought inside its box below.

sola:emitVariableInitialisers := { skip |
    self:variablesIn(self:statementsOfScope):do({ name |
        skip:indexOf(name):isNil
            :and({ self:shared:indexOf(name):isNil })
            ; **A `DIM SHARED` name belongs to the module**, so a procedure that
            ; mentions it must not give it a nought -- that would replace what
            ; the module put there. A `SUB` that assigns to it survived this by
            ; luck of ordering; a `FUNCTION` that only reads it saw nought.
            :and({ self:inProcedure:and({
                self:sharedNames:indexOf(name):notNil }):not })
            ; **A procedure's name holds the procedure**, and giving it a nought
            ; replaces it with one. A bare `Total` that means `FUNCTION Total`
            ; reads as a variable to the walker that collects these, so the
            ; walker's answer has to be filtered here.
            :and({ self:routines:includes(name):not })
            :and({ self:statics:includes(name):not })
            :and({ self:isBoxed(name):not }):ifTrue({
            self:emitZero(self:typeOfName(name)).
            self:isLocalName(name):ifElse(
                { self:emitSetLocal(self:slotFor(name)) },
                { self:emitStore(self:globalNameFor(name)) }).
            self:emitPop }) }) }.

sola:statementsOfScope := nil.

; Every name a body uses as a variable, in the order it first appears.
sola:variablesIn := { body | | names |
    names := array:new.
    body:do({ st | self:variablesInStatement(st, names) }).
    names }.

; The subscripts of every INPUT or LINE INPUT target, if there are any.
sola:inputTargetsDo := { st, block |
    ['input, 'lineinput]:indexOf(st:kind):notNil:ifTrue({
        st:items:do({ each |
            each:at(#2):notNil:ifTrue({
                each:at(#2):do({ a | block:value(a) }) }) }) }) }.

sola:noteName := { names, name |
    names:indexOf(name):isNil:ifTrue({ names:add(name) }) }.

sola:variablesInStatement := { st, names |
    ['let, 'for]:indexOf(st:kind):notNil:ifTrue({ self:noteName(names, st:name) }).
    ; A `DIM`med plain variable is a variable like any other and wants its
    ; nought; a `DIM`med array is made by the DIM itself and must not be given
    ; one, which would replace the array with a number.
    st:kind:equals('dim):ifTrue({ | i |
        i := #1.
        { i:lessOrEqual(st:items:size) }:whileTrue({
            st:bounds:at(i):isNil:ifTrue({
                self:noteName(names, st:items:at(i)) }).
            i := i:add(#1) }) }).
    ['print, 'call]:indexOf(st:kind):notNil:ifTrue({
        st:items:do({ a | self:variablesInExpression(a, names) }) }).
    st:kind:equals('print):ifTrue({ nil }).
    self:variablesInExpression(st:expr, names).
    self:variablesInExpression(st:limit, names).
    self:variablesInExpression(st:step, names).
    st:subscripts:notNil:ifTrue({
        st:subscripts:do({ a | self:variablesInExpression(a, names) }) }).
    self:inputTargetsDo(st, { a | self:variablesInExpression(a, names) }).
    st:alternatives:notNil:ifTrue({
        st:alternatives:do({ alt |
            alt:at(#1):equals("is"):ifElse(
                { self:variablesInExpression(alt:at(#3), names) },
                { self:variablesInExpression(alt:at(#2), names).
                  alt:at(#1):equals("range"):ifTrue({
                      self:variablesInExpression(alt:at(#3), names) }) }) }) }).
    st:then:notNil:ifTrue({ self:variablesInStatement(st:then, names) }).
    st:otherwise:notNil:ifTrue({ self:variablesInStatement(st:otherwise, names) }).
    st:kind:equals('group):ifTrue({
        st:body:do({ each | self:variablesInStatement(each, names) }) }) }.

sola:variablesInExpression := { n, names |
    n:isNil:ifFalse({
        n:kind:equals('variable):ifTrue({ self:noteName(names, n:name) }).
        n:kind:equals('call):ifTrue({
            n:args:do({ a | self:variablesInExpression(a, names) }) }).
        self:variablesInExpression(n:left, names).
        self:variablesInExpression(n:right, names) }) }.

; Every boxed name is given its box before anything runs, because the first
; thing that happens to it may be a call that assigns through it.
sola:emitBoxes := {
    self:toBox:do({ name |
        self:emitGlobal("array").
        self:emitZero(self:typeOfName(name)).
        self:emitSend("of", #1).
        self:isLocalName(name):ifElse(
            { self:emitSetLocal(self:slotFor(name)) },
            { self:emitStore(self:globalNameFor(name)) }).
        self:emitPop }) }.

; ---------------------------------------------------------------------------
; The jump, which is the whole of stage 3
;
; **The opcode is not known when the jump is emitted.** A jump forward is
; `OP_JUMP` and a jump backward is `OP_LOOP` -- two opcodes, because the machine
; has no signed offset and the verifier relies on everything else moving
; forwards. Which one a `GOTO` is depends on where its label turns out to be,
; and that is not known until the whole program has been emitted.
;
; They are both three bytes, which is what makes this easy: three zero bytes go
; down as a placeholder and the fixup list remembers where. Nothing has to be
; moved afterwards, so no offset already computed can be invalidated by a later
; patch -- which is the trap in every backpatching scheme that emits a short
; jump and grows it.

sola:emitJump := { label | | at |
    at := self:here.
    self:byte(#0). self:byte(#0). self:byte(#0).
    self:fixups:add([at, label, self:atLine]) }.

sola:patchJump := { at, op, offset |
    offset:greaterThan(jumpLimit):ifTrue({
        self:fail("a jump of {} bytes: no jump reaches further than {}"
            :fill([offset, jumpLimit])) }).
    self:code:atPut(at:add(#1), op).
    self:code:atPut(at:add(#2), offset:bitAnd(#255)).
    self:code:atPut(at:add(#3), offset:shiftRight(#8):bitAnd(#255)) }.

; **A jump to a label that does not exist is reported before anything runs**,
; which is the same rule `basic.sol` keeps for a `GOTO` to a missing line: a
; program that starts, prints, and then discovers it cannot go where it was told
; has already done half its work wrongly.
sola:resolveJumps := {
    self:fixups:do({ f | | at, label, target, after |
        at := f:at(#1).
        label := f:at(#2).
        self:labelAt:includes(label):ifFalse({
            self:atLine := f:at(#3).
            self:fail("there is no label '{}' to jump to":fill([label])) }).
        target := self:labelAt:at(label).
        after := at:add(#3).
        target:greaterOrEqual(after):ifElse(
            { self:patchJump(at, JUMP, target:sub(after)) },
            { self:patchJump(at, LOOP, after:sub(target)) }) }) }.

; ---------------------------------------------------------------------------
; Expressions, into instructions
;
; Left, right, send. There is no arithmetic instruction in this machine, so a
; SolaBasic `+` is exactly one `OP_SEND` -- against the several the tree-walker
; makes per node, which is where the difference between the two comes from.

sola:emitExpression := { n |
    [ { n:kind:equals('number) },
        { n:type:equals('integer):ifElse(
            { self:emitIntConst(n:value) }, { self:emitConst(n:value) }) },
      { n:kind:equals('string) },   { self:emitString(n:value) },
      { n:kind:equals('arrayref) }, { self:emitRawVar(n:name) },
      { n:kind:equals('variable) },
        { self:isConstant(n:name):ifElse(
            { self:emitConstantValue(n:name) },
            { self:isBareCall(n:name):ifElse(
                { self:emitCall(n:name, array:new, false) },
                { self:emitLoadVar(n:name) }) }) },
      { n:kind:equals('call) },
        { self:isArray(n:name):ifElse(
            { self:emitRawVar(n:name).
              self:emitSubscript(n:name, n:args).
              self:emitSend("at", #1) },
            { self:emitCall(n:name, n:args, false) }) },
      { n:kind:equals('negate) },
        { self:emitTyped(n:left, n:operandType). self:emitSend("negated", #0) },
      { n:kind:equals('not) },
        { self:emitTyped(n:left, 'integer). self:emitSend("bitNot", #0) },
        { self:emitBinary(n) } ]:ifElseIf }.

sola:emitBinary := { n |
    [ { n:op:equals("MOD") }, { self:emitModulo(n) },
      { n:op:equals("\\") },  { self:emitIntegerDivide(n) },
      { n:op:equals("^") },
        { self:emitTyped(n:left, 'double).
          self:emitTyped(n:right, 'double).
          self:emitSend("pow", #1) },
      { n:op:equals("+"):and({ n:operandType:equals('string) }) },
        { self:emitTyped(n:left, 'string).
          self:emitTyped(n:right, 'string).
          self:emitSend("concat", #1) },
        { self:emitTyped(n:left, n:operandType).
          self:emitTyped(n:right, n:operandType).
          self:emitSend(selectors:at(n:op), #1) } ]:ifElseIf }.

; **`\\` truncates towards nought and so does `MOD`'s remainder**, which is
; QBasic's rule and *not* the machine's: SolVM's integer `div` and `mod` are
; **floored**, so `-7 \\ 2` would be `-4` where QBasic says `-3`, and
; `-7 MOD 2` would be `1` where QBasic says `-1`.
;
; **The correction is exact and stays in integers**: the truncating quotient is
; the floored one, plus one when there is a remainder *and* the two signs
; differ. Nothing else is true of any sign combination, and nothing here leaves
; i64 -- so this is right for every number an Integer can hold.
;
; An earlier version went through the float divide and `truncated` instead. That
; is four sends against these twelve instructions and it gets every sign right
; too, but it is **wrong above 2^53**, where a double can no longer hold every
; whole number. Trading bytes in a file nobody reads for an answer that is
; always right is the easy direction of that trade.
;
; A single `quotient` message on integer would be one send and exact, and is
; [deferred with a trigger](../docs/ideas.md#a-truncating-divide-on-integer)
; with this as its one customer.

sola:emitTruncatingQuotient := { a, b | | noRemainder, sameSign |
    self:emitLocal(a). self:emitLocal(b). self:emitSend("div", #1).

    ; ... and one more when the division was not exact ...
    self:emitLocal(a). self:emitLocal(b). self:emitSend("mod", #1).
    self:emitIntConst(#0). self:emitSend("notEquals", #1).
    noRemainder := self:branchHole.

    ; ... and the signs disagreed, which is the only case where flooring and
    ; truncating part company.
    self:emitLocal(a). self:emitIntConst(#0). self:emitSend("lessThan", #1).
    self:emitLocal(b). self:emitIntConst(#0). self:emitSend("lessThan", #1).
    self:emitSend("notEquals", #1).
    sameSign := self:branchHole.

    self:emitIntConst(#1). self:emitSend("add", #1).

    self:fillBranch(noRemainder).
    self:fillBranch(sameSign) }.

sola:emitIntegerDivide := { n | | a, b |
    a := self:intoScratchAs(n:left, 'integer).
    b := self:intoScratchAs(n:right, 'integer).
    self:emitTruncatingQuotient(a, b).
    self:dropScratch.
    self:dropScratch }.

; `a - (a \\ b) * b`, with `\\` meaning the truncating one above -- which is what
; makes the remainder take the sign of the left-hand side, as BASIC's does.
sola:emitModulo := { n | | a, b |
    a := self:intoScratchAs(n:left, 'integer).
    b := self:intoScratchAs(n:right, 'integer).
    self:emitLocal(a).
    self:emitTruncatingQuotient(a, b).
    self:emitLocal(b).
    self:emitSend("mul", #1).
    self:emitSend("sub", #1).
    self:dropScratch.
    self:dropScratch }.

; ---------------------------------------------------------------------------
; Statements, into instructions
;
; **Every one of these leaves the stack exactly as it found it**, at depth 0,
; and that is not tidiness -- it is what makes a label a merge point the
; verifier accepts from any number of jumps. An assignment leaves its value
; behind (all four of the machine's stores do, so that `c := b := #45` falls
; out) and the `POP` here is what discards it.

emitters := dictionary:new.

sola:emitStatement := { st |
    self:atLine := st:line.
    self:mark(st:line).
    st:label:notNil:ifTrue({
        self:labelAt:includes(st:label):ifTrue({
            self:fail("the label '{}' is used twice":fill([st:label])) }).
        self:labelAt:atPut(st:label, self:here) }).
    self:guardSelect(st:kind).
    self:typeStatement(st).
    emitters:at(st:kind):value(self, st) }.

; Everything in one statement, typed before any of it is emitted.
sola:typeStatement := { st |
    ['print, 'call]:indexOf(st:kind):notNil:ifTrue({
        st:items:do({ a | a:isNil:ifFalse({ self:typeExpression(a) }) }) }).
    st:expr:notNil:ifTrue({ self:typeExpression(st:expr) }).
    st:limit:notNil:ifTrue({ self:typeExpression(st:limit) }).
    st:step:notNil:ifTrue({ self:typeExpression(st:step) }).
    st:subscripts:notNil:ifTrue({
        st:subscripts:do({ a | self:typeExpression(a) }) }).
    ; **An INPUT target may be an array element**, and its subscripts are
    ; expressions like any other -- untyped, `emitTyped` had nothing to compare
    ; against and coerced an integer subscript as though it were a Double.
    self:inputTargetsDo(st, { a | self:typeExpression(a) }).
    st:alternatives:notNil:ifTrue({
        st:alternatives:do({ alt |
            alt:at(#1):equals("is"):ifElse(
                { self:typeExpression(alt:at(#3)) },
                { self:typeExpression(alt:at(#2)).
                  alt:at(#1):equals("range"):ifTrue({
                      self:typeExpression(alt:at(#3)) }) }) }) }).
    st:then:notNil:ifTrue({ self:typeStatement(st:then) }).
    st:otherwise:notNil:ifTrue({ self:typeStatement(st:otherwise) }).
    st:kind:equals('group):ifTrue({
        st:body:do({ each | self:typeStatement(each) }) }) }.

emitters:atPut('rem, { m, st | nil }).
emitters:atPut('group, { m, st | st:body:do({ each | m:emitStatement(each) }) }).
; **A line left open goes out before the program stops.** `PRINT "x";` holds
; the line for the next PRINT to continue, and if there is no next PRINT it
; still has to be written -- so every way out of the program flushes first.
emitters:atPut('end, { m, st | m:emitFinalFlush. m:byte(HALT) }).
emitters:atPut('goto, { m, st | m:emitJump(st:target) }).
emitters:atPut('print, { m, st | m:emitPrint(st) }).
emitters:atPut('let, { m, st |
    m:beginAssign(st:name).
    m:emitTyped(st:expr, m:typeOfName(st:name)).
    m:endAssign(st:name) }).

; ---------------------------------------------------------------------------
; Holes
;
; A forward jump is emitted before its target exists, so a hole goes down and
; the frame that owns it remembers where. Two shapes, because two instructions:
; a three-byte `OP_JUMP` and a five-byte `OP_JUMP_IF_FALSE`, whose offset sits
; behind its opcode and in front of the selector name it carries.
;
; **Every hole here is forward.** Backward jumps in these constructs go to a
; place already emitted, so they are written out complete and need no hole at
; all -- which is the difference between a block and a `GOTO`, where the
; direction is not known until the label turns up.

sola:hole := { | at |
    at := self:here. self:byte(#0). self:byte(#0). self:byte(#0). at }.

sola:branchHole := { | at |
    at := self:here.
    self:byte(JMPF). self:u16(#0). self:u16(self:nameFor("ifTrue")).
    at }.

sola:fillJump := { at | self:patchJump(at, JUMP, self:here:sub(at:add(#3))) }.

sola:fillBranch := { at | | offset |
    offset := self:here:sub(at:add(#5)).
    offset:greaterThan(jumpLimit):ifTrue({
        self:fail("a branch of {} bytes: no jump reaches further than {}"
            :fill([offset, jumpLimit])) }).
    self:code:atPut(at:add(#2), offset:bitAnd(#255)).
    self:code:atPut(at:add(#3), offset:shiftRight(#8):bitAnd(#255)) }.

sola:fillAll := { holes |
    holes:do({ h |
        h:at(#2):equals('branch):ifElse(
            { self:fillBranch(h:at(#1)) },
            { self:fillJump(h:at(#1)) }) }) }.

sola:emitLoopTo := { target | | offset |
    offset := self:here:add(#3):sub(target).
    offset:greaterThan(jumpLimit):ifTrue({
        self:fail("a loop of {} bytes: no jump reaches further than {}"
            :fill([offset, jumpLimit])) }).
    self:byte(LOOP).
    self:byte(offset:bitAnd(#255)).
    self:byte(offset:shiftRight(#8):bitAnd(#255)) }.

; ---------------------------------------------------------------------------
; The stack of open blocks

sola:blocks := nil.
sola:forCount := #0.
sola:selectCount := #0.

; ---------------------------------------------------------------------------
; A unit is a chunk being built
;
; A `SUB` compiles to a chunk of its own, held in the module's method table, and
; a chunk owns everything: its code, its own name and constant tables, its own
; frame, its own labels. So the compiler's state is pushed and restored around
; each one rather than being threaded through every routine as an argument.
;
; **Labels are per-unit, which is the language's rule and not an accident of
; this.** SolaBasic says a `GOTO` may not cross between module level and a
; procedure, and it could not if it wanted to: a jump is an offset inside one
; chunk and there is no instruction that leaves a frame and lands somewhere.

sola:localNames := nil.
sola:locals := nil.
; **Which file a chunk's lines belong to.** The runtime is compiled into the
; program that uses it, so without this a failure inside it reported a line
; number of its own against the *user's* filename -- a line that listing does
; not have, in a routine they did not write.
sola:unitPath := "".
sola:varTypes := nil.
sola:scratchSlots := nil.
sola:scratchDepth := #0.
sola:shared := nil.
sola:statics := nil.
sola:boxed := nil.
sola:toBox := nil.
sola:methods := nil.
sola:inProcedure := false.
sola:returnName := "".
sola:unitStack := nil.

sola:pushUnit := { | saved |
    saved := dictionary:new.
    saved:atPut("code", self:code).             saved:atPut("names", self:names).
    saved:atPut("nameIndex", self:nameIndex).   saved:atPut("constants", self:constants).
    saved:atPut("constIndex", self:constIndex). saved:atPut("lineMarks", self:lineMarks).
    saved:atPut("labelAt", self:labelAt).       saved:atPut("fixups", self:fixups).
    saved:atPut("blocks", self:blocks).         saved:atPut("localNames", self:localNames).
    saved:atPut("locals", self:locals).         saved:atPut("shared", self:shared).
    saved:atPut("varTypes", self:varTypes).
    saved:atPut("unitPath", self:unitPath).
    saved:atPut("scratchSlots", self:scratchSlots).
    saved:atPut("scratchDepth", self:scratchDepth).
    saved:atPut("statics", self:statics).       saved:atPut("boxed", self:boxed).
    saved:atPut("arrayParams", self:arrayParams).
    saved:atPut("toBox", self:toBox).           saved:atPut("methods", self:methods).
    saved:atPut("inProcedure", self:inProcedure).
    saved:atPut("returnName", self:returnName).
    self:unitStack:add(saved).
    self:freshUnit }.

sola:freshUnit := {
    self:code := array:new.        self:names := array:new.
    self:nameIndex := dictionary:new.
    self:constants := array:new.   self:constIndex := dictionary:new.
    self:lineMarks := array:new.   self:labelAt := dictionary:new.
    self:fixups := array:new.      self:blocks := array:new.
    self:localNames := array:new.  self:locals := dictionary:new.
    self:varTypes := dictionary:new.
    self:unitPath := self:path.
    self:scratchSlots := array:new. self:scratchDepth := #0.
    self:shared := array:new.      self:statics := dictionary:new.
    self:arrayParams := dictionary:new.
    self:boxed := array:new.       self:toBox := array:new.
    self:methods := array:new.
    self:inProcedure := false.     self:returnName := "".
    self:newSlot("") }.

sola:popUnit := { | saved |
    saved := self:unitStack:removeLast.
    self:code := saved:at("code").             self:names := saved:at("names").
    self:nameIndex := saved:at("nameIndex").   self:constants := saved:at("constants").
    self:constIndex := saved:at("constIndex"). self:lineMarks := saved:at("lineMarks").
    self:labelAt := saved:at("labelAt").       self:fixups := saved:at("fixups").
    self:blocks := saved:at("blocks").         self:localNames := saved:at("localNames").
    self:locals := saved:at("locals").         self:shared := saved:at("shared").
    self:varTypes := saved:at("varTypes").
    self:unitPath := saved:at("unitPath").
    self:scratchSlots := saved:at("scratchSlots").
    self:scratchDepth := saved:at("scratchDepth").
    self:statics := saved:at("statics").       self:boxed := saved:at("boxed").
    self:arrayParams := saved:at("arrayParams").
    self:toBox := saved:at("toBox").           self:methods := saved:at("methods").
    self:inProcedure := saved:at("inProcedure").
    self:returnName := saved:at("returnName") }.

; The chunk the current unit has become. Everything a `.sob` wants about one
; chunk, and the same shape whether it is the script or a procedure.
sola:chunkOfUnit := { | chunk |
    self:resolveJumps.
    chunk := dictionary:new.
    chunk:atPut("slots", self:localNames:size).
    chunk:atPut("names", self:names).
    chunk:atPut("constants", self:constants).
    chunk:atPut("code", self:code).
    chunk:atPut("lines", self:lineRuns).
    chunk:atPut("files", [self:unitPath]).
    chunk:atPut("fileRuns", [[self:code:size, #0]]).
    chunk:atPut("slotNames", self:localNames).
    chunk:atPut("methods", self:methods).
    chunk }.

sola:pushBlock := { kind | | f |
    f := makeFrame:value(kind, self:atLine).
    self:blocks:add(f).
    f }.

sola:innermost := {
    self:blocks:size:equals(#0):ifElse(
        { nil }, { self:blocks:at(self:blocks:size) }) }.

sola:popBlock := { what | | f |
    f := self:innermost.
    f:isNil:ifTrue({ self:fail("{} with no block open":fill([what])) }).
    self:blocks:removeLast.
    f }.

; The innermost frame of one kind, which is what EXIT looks for.
sola:enclosing := { kind | | found, i |
    found := nil.
    i := self:blocks:size.
    { found:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
        self:blocks:at(i):kind:equals(kind):ifTrue({ found := self:blocks:at(i) }).
        i := i:sub(#1) }).
    found }.

sola:openFrame := { what, kind | | f |
    f := self:innermost.
    f:isNil:or({ f:kind:equals(kind):not }):ifTrue({
        self:fail("{} with no {} open":fill([what, self:openerName(kind)])) }).
    f }.

sola:openerName := { kind |
    [ { kind:equals('if) },     { "IF" },
      { kind:equals('select) }, { "SELECT CASE" },
      { kind:equals('for) },    { "FOR" },
      { kind:equals('do) },     { "DO" },
                                { "WHILE" } ]:ifElseIf }.

sola:closerName := { kind |
    [ { kind:equals('if) },     { "END IF" },
      { kind:equals('select) }, { "END SELECT" },
      { kind:equals('for) },    { "NEXT" },
      { kind:equals('do) },     { "LOOP" },
                                { "WEND" } ]:ifElseIf }.

; **Nothing may sit between SELECT CASE and its first CASE.** There is nowhere
; for it to go: the subject has been stored and the next thing control reaches
; has to be a test. QBasic refuses it and so does this, rather than emitting
; something that runs once and looks deliberate.
sola:guardSelect := { kind | | f |
    f := self:innermost.
    f:notNil:and({ f:kind:equals('select) }):and({ f:top:equals(#0) })
        :and({ ['case, 'caseelse, 'endselect]:indexOf(kind):isNil }):ifTrue({
        self:fail("nothing may come between SELECT CASE and its first CASE") }) }.

; ---------------------------------------------------------------------------
; IF
;
; Each arm's test jumps past its own body when it fails, and each body jumps to
; the end when it is done. `pending` is the one test waiting to be told where
; "past this body" is; `exits` are the bodies waiting to be told where the end
; is. An `IF` with no `ELSE` never fills `exits` at all, because the last test
; falls straight out.

emitters:atPut('ifline, { m, st | | over, past |
    m:emitCondition(st:expr).
    over := m:branchHole.
    m:emitStatement(st:then).
    st:otherwise:isNil:ifElse(
        { m:fillBranch(over) },
        { past := m:hole.
          m:fillBranch(over).
          m:emitStatement(st:otherwise).
          m:fillJump(past) }) }).

emitters:atPut('ifblock, { m, st | | f |
    m:emitCondition(st:expr).
    f := m:pushBlock('if).
    f:pending:add([m:branchHole, 'branch]) }).

emitters:atPut('elseif, { m, st | | f |
    f := m:openFrame("ELSEIF", 'if).
    f:seenElse:ifTrue({ m:fail("ELSEIF after ELSE") }).
    f:exits:add([m:hole, 'jump]).
    m:fillAll(f:pending).
    f:pending := array:new.
    m:emitCondition(st:expr).
    f:pending:add([m:branchHole, 'branch]) }).

emitters:atPut('else, { m, st | | f |
    f := m:openFrame("ELSE", 'if).
    f:seenElse:ifTrue({ m:fail("ELSE twice in one IF") }).
    f:exits:add([m:hole, 'jump]).
    m:fillAll(f:pending).
    f:pending := array:new.
    f:seenElse := true }).

emitters:atPut('endif, { m, st | | f |
    f := m:openFrame("END IF", 'if).
    m:popBlock("END IF").
    m:fillAll(f:pending).
    m:fillAll(f:exits) }).

; ---------------------------------------------------------------------------
; SELECT CASE
;
; The subject goes into a global of its own, named with a space in it so that
; nothing a BASIC program can spell will collide with it -- the tokeniser cannot
; produce such a name, which makes the guarantee structural rather than a
; convention about prefixes.

emitters:atPut('select, { m, st | | f, slot |
    m:emitExpression(st:expr).
    slot := m:newSlot("select subject").
    m:emitSetLocal(slot).
    m:emitPop.
    f := m:pushBlock('select).
    f:subject := slot.
    f:subjectType := st:expr:type }).

emitters:atPut('case, { m, st | | f, count, i, misses, toBody |
    f := m:openFrame("CASE", 'select).
    f:seenElse:ifTrue({ m:fail("CASE after CASE ELSE") }).
    m:closeCaseArm(f).

    ; Alternatives are an OR: the first that matches runs the body, and only
    ; when the last one fails does control go on to the next CASE. So every
    ; alternative but the last needs a jump *to* the body, and its failures land
    ; on the alternative after it.
    count := st:alternatives:size.
    toBody := array:new.
    i := #1.
    { i:lessOrEqual(count) }:whileTrue({
        misses := m:emitAlternative(f:subject, f:subjectType,
                                    st:alternatives:at(i)).
        i:equals(count):ifElse(
            { misses:do({ at | f:pending:add([at, 'branch]) }) },
            { toBody:add([m:hole, 'jump]).
              misses:do({ at | m:fillBranch(at) }) }).
        i := i:add(#1) }).
    m:fillAll(toBody) }).

emitters:atPut('caseelse, { m, st | | f |
    f := m:openFrame("CASE ELSE", 'select).
    f:seenElse:ifTrue({ m:fail("CASE ELSE twice in one SELECT") }).
    m:closeCaseArm(f).
    f:seenElse := true }).

; The arm before this one, if there was one, leaves; and the test that sent
; control here is told where here is.
sola:closeCaseArm := { f |
    f:top:notEquals(#0):ifTrue({ f:exits:add([self:hole, 'jump]) }).
    self:fillAll(f:pending).
    f:pending := array:new.
    f:top := #1 }.

emitters:atPut('endselect, { m, st | | f |
    f := m:openFrame("END SELECT", 'select).
    m:popBlock("END SELECT").
    f:top:equals(#0):ifTrue({ m:fail("SELECT CASE with no CASE in it") }).
    m:fillAll(f:pending).
    m:fillAll(f:exits) }).

; A value, a range, or a comparison. Answers the holes to fill when it does
; **not** match -- a range is two of them, because it is an AND and either half
; can refuse.
sola:emitAlternative := { slot, t, alt | | misses |
    misses := array:new.
    alt:at(#1):equals("value"):ifTrue({
        self:emitLocal(slot).
        self:emitTyped(alt:at(#2), t).
        self:emitSend("equals", #1).
        misses:add(self:branchHole) }).
    alt:at(#1):equals("range"):ifTrue({
        self:emitLocal(slot).
        self:emitTyped(alt:at(#2), t).
        self:emitSend("greaterOrEqual", #1).
        misses:add(self:branchHole).
        self:emitLocal(slot).
        self:emitTyped(alt:at(#3), t).
        self:emitSend("lessOrEqual", #1).
        misses:add(self:branchHole) }).
    alt:at(#1):equals("is"):ifTrue({
        self:emitLocal(slot).
        self:emitTyped(alt:at(#3), t).
        self:emitSend(selectors:at(alt:at(#2)), #1).
        misses:add(self:branchHole) }).
    misses }.

; ---------------------------------------------------------------------------
; FOR
;
; The counter is an ordinary global, because that is what a BASIC loop variable
; is: readable after the loop and assignable inside it. The limit and the step
; are globals too, named the way the SELECT subject is, because they are
; evaluated once and the body may change what they were computed from.

; **A written-out step fixes the direction at compile time**, which is worth the
; ten lines because it is nearly every loop: `FOR I = 1 TO 10` and
; `FOR I = 10 TO 1 STEP -1` both know which way they run before they start.
sola:literalStep := { n |
    n:isNil:ifElse(
        { 1.0 },
        { n:kind:equals('number):ifElse(
            { self:asDouble(n:value) },
            { n:kind:equals('negate):and({ n:left:kind:equals('number) }):ifElse(
                { self:asDouble(n:left:value):negated },
                { nil }) }) }) }.

emitters:atPut('for, { m, st | | f, step, t |
    t := m:typeOfName(st:name).
    t:equals('string):ifTrue({ m:fail("a FOR counts, so its variable is a number") }).
    m:beginAssign(st:name). m:emitTyped(st:expr, t). m:endAssign(st:name).

    f := m:pushBlock('for).
    f:name := st:name.
    f:varType := t.
    f:limitSlot := m:newSlot("for limit").
    m:emitTyped(st:limit, t). m:emitSetLocal(f:limitSlot). m:emitPop.

    step := m:literalStep(st:step).
    f:step := step.
    step:isNil:ifTrue({
        f:stepSlot := m:newSlot("for step").
        m:emitTyped(st:step, t). m:emitSetLocal(f:stepSlot). m:emitPop }).

    f:top := m:here.
    m:emitForTest(f).
    f:pending:add([m:branchHole, 'branch]) }).

; **The test is before the body**, so a loop whose range is already empty runs
; no times, which is the standard's rule and the one people rely on.
;
; When the step is not a literal its sign is not known until the loop starts, so
; neither is which comparison to make. Rather than emit both and pick at run
; time, the test becomes `(limit - counter) * step >= 0`, which is `<=` when the
; step is positive and `>=` when it is negative, and runs forever on a step of
; nought exactly as BASIC does. **Where this is not exact** is a product that
; underflows to `-0.0`, which compares as `>= 0` and buys one extra iteration;
; a literal step never takes this path, so it is reachable only from
; `STEP <expression>`.
sola:emitForTest := { f |
    f:step:isNil:ifElse(
        { self:emitLocal(f:limitSlot).
          self:emitLoadVar(f:name).
          self:emitSend("sub", #1).
          self:emitLocal(f:stepSlot).
          self:emitSend("mul", #1).
          self:emitNumber(#0, f:varType).
          self:emitSend("greaterOrEqual", #1) },
        { self:emitLoadVar(f:name).
          self:emitLocal(f:limitSlot).
          self:emitSend(
              f:step:lessThan(0.0):ifElse({ "greaterOrEqual" }, { "lessOrEqual" }),
              #1) }) }.

emitters:atPut('next, { m, st |
    st:items:size:equals(#0):ifElse(
        { m:closeFor(nil) },
        { st:items:do({ name | m:closeFor(name) }) }) }).

sola:closeFor := { name | | f |
    f := self:innermost.
    f:isNil:or({ f:kind:equals('for):not }):ifTrue({
        self:fail(f:isNil:ifElse(
            { "NEXT with no FOR open" },
            { "NEXT closes the {} opened on line {}"
                :fill([self:openerName(f:kind), f:line]) })) }).
    name:notNil:and({ name:equals(f:name):not }):ifTrue({
        self:fail("NEXT {} closes the FOR on {}, which counts {}"
            :fill([name, f:line, f:name])) }).
    self:popBlock("NEXT").

    self:beginAssign(f:name).
    self:emitLoadVar(f:name).
    f:step:isNil:ifElse(
        { self:emitLocal(f:stepSlot) },
        { self:emitNumber(f:step, f:varType) }).
    self:emitSend("add", #1).
    self:endAssign(f:name).
    self:emitLoopTo(f:top).
    self:fillAll(f:pending).
    self:fillAll(f:exits) }.

; ---------------------------------------------------------------------------
; DO, LOOP, WHILE, WEND

emitters:atPut('do, { m, st | | f |
    f := m:pushBlock('do).
    f:top := m:here.
    st:test:equals('none):ifFalse({
        m:emitCondition(st:expr).
        st:test:equals('until):ifTrue({ m:emitSend("not", #0) }).
        f:pending:add([m:branchHole, 'branch]) }) }).

emitters:atPut('loop, { m, st | | f |
    f := m:openFrame("LOOP", 'do).
    m:popBlock("LOOP").
    st:test:equals('none):ifElse(
        { m:emitLoopTo(f:top) },
        { f:pending:size:notEquals(#0):ifTrue({
              m:fail("a DO tests at one end or at neither, not at both") }).
          m:emitCondition(st:expr).
          st:test:equals('until):ifTrue({ m:emitSend("not", #0) }).
          f:pending:add([m:branchHole, 'branch]).
          m:emitLoopTo(f:top) }).
    m:fillAll(f:pending).
    m:fillAll(f:exits) }).

emitters:atPut('while, { m, st | | f |
    f := m:pushBlock('while).
    f:top := m:here.
    m:emitCondition(st:expr).
    f:pending:add([m:branchHole, 'branch]) }).

emitters:atPut('wend, { m, st | | f |
    f := m:openFrame("WEND", 'while).
    m:popBlock("WEND").
    m:emitLoopTo(f:top).
    m:fillAll(f:pending).
    m:fillAll(f:exits) }).

; `EXIT FOR` and `EXIT DO` leave the innermost loop **of that kind**, which is
; why this searches the stack rather than looking at the top of it: an EXIT FOR
; inside an IF inside the loop is the ordinary way to write one.
emitters:atPut('exit, { m, st | | f |
    ["SUB", "FUNCTION"]:indexOf(st:target):notNil:ifElse(
        { m:inProcedure:ifFalse({
              m:fail("EXIT {} outside a {}":fill([st:target, st:target])) }).
          m:emitReturnValue.
          m:byte(RETURN) },
        { f := m:enclosing(st:target:equals("FOR"):ifElse({ 'for }, { 'do })).
          f:isNil:ifTrue({
              m:fail("EXIT {} with no {} loop around it"
                  :fill([st:target, st:target])) }).
          f:exits:add([m:hole, 'jump]) }) }).

emitters:atPut('call, { m, st | m:emitCall(st:name, st:items, true) }).

; ---------------------------------------------------------------------------
; Making an array
;
; A Solum array starts empty and grows, so `DIM` is a loop that adds the right
; number of noughts -- or empty strings. It runs where it is written, so a `DIM`
; inside a procedure makes a fresh array on every call, which is what BASIC does
; with one.

sola:emitStoreRaw := { name |
    self:isLocalName(name):ifElse(
        { self:emitSetLocal(self:slotFor(name)) },
        { self:emitStore(self:globalNameFor(name)) }).
    self:emitPop }.

sola:emitMakeArray := { name, bounds | | total, slot, top, done |
    total := #1.
    bounds:do({ b |
        b:at(#2):lessThan(b:at(#1)):ifTrue({
            self:fail("{}({} TO {}) has no elements"
                :fill([name, b:at(#1), b:at(#2)])) }).
        total := total:mul(b:at(#2):sub(b:at(#1)):add(#1)) }).

    self:emitGlobal("array").
    self:emitSend("new", #0).
    self:emitStoreRaw(name).

    slot := self:takeScratch.
    self:emitIntConst(total).
    self:emitSetLocal(slot).
    self:emitPop.
    top := self:here.
    self:emitLocal(slot). self:emitIntConst(#0). self:emitSend("greaterThan", #1).
    done := self:branchHole.
    self:emitRawVar(name).
    self:emitZero(self:typeOfName(name)).
    self:emitSend("add", #1).
    self:emitPop.
    self:emitLocal(slot). self:emitIntConst(#1). self:emitSend("sub", #1).
    self:emitSetLocal(slot). self:emitPop.
    self:emitLoopTo(top).
    self:fillBranch(done).
    self:dropScratch }.

emitters:atPut('dim, { m, st | | i |
    i := #1.
    { i:lessOrEqual(st:items:size) }:whileTrue({
        st:bounds:at(i):isNil:ifFalse({
            m:emitMakeArray(st:items:at(i), st:bounds:at(i)) }).
        i := i:add(#1) }) }).

emitters:atPut('arrayset, { m, st |
    m:isArray(st:name):ifFalse({
        m:fail("'{}' is not an array: DIM it before subscripting it"
            :fill([st:name])) }).
    m:emitRawVar(st:name).
    m:emitSubscript(st:name, st:subscripts).
    m:emitTyped(st:expr, m:typeOfName(st:name)).
    m:emitSend("atPut", #2).
    m:emitPop }).

; The runtime is asked once for a whole answer, already checked, and the
; fields are pulled out of it here. Everything that could need doing twice --
; counting the commas, deciding whether a field is a number, saying *Redo from
; start* and asking again -- is in the runtime where it is written once.
; A target is a name and, when it is an element, its subscripts. Filling one is
; the ordinary assignment in both halves -- what differs is only where the value
; is put.
sola:beginTarget := { target |
    target:at(#2):isNil:ifElse(
        { self:beginAssign(target:at(#1)) },
        { self:isArray(target:at(#1)):ifFalse({
              self:fail("'{}' is not an array":fill([target:at(#1)])) }).
          self:emitRawVar(target:at(#1)).
          self:emitSubscript(target:at(#1), target:at(#2)) }) }.

sola:endTarget := { target |
    target:at(#2):isNil:ifElse(
        { self:endAssign(target:at(#1)) },
        { self:emitSend("atPut", #2). self:emitPop }) }.

emitters:atPut('input, { m, st | | slot, i, name, spec |
    st:items:do({ each |
        each:at(#2):isNil:and({ m:isArray(each:at(#1)) }):ifTrue({
            m:fail("INPUT fills a variable or an element, and '{}' is a whole array"
                :fill([each:at(#1)])) }) }).
    spec := "".
    st:items:do({ each |
        spec := spec:concat(m:typeOfName(each:at(#1)):equals('string):ifElse(
            { "S" }, { "N" })) }).

    st:channel:isNil:ifElse(
        { m:emitGlobal("SOLAASK$").
          st:expr:isNil:ifElse({ m:emitString("") }, { m:emitString(st:expr:value) }).
          m:emitIntConst(st:test:equals('comma):ifElse({ #0 }, { #1 })).
          m:emitString(spec).
          m:emitSend("value", #3) },
        { m:emitGlobal("SOLAFLINE$").
          m:emitTyped(st:channel, 'integer).
          m:emitSend("value", #1) }).
    slot := m:takeScratch.
    m:emitSetLocal(slot).
    m:emitPop.

    i := #1.
    { i:lessOrEqual(st:items:size) }:whileTrue({
        name := st:items:at(i):at(#1).
        m:beginTarget(st:items:at(i)).
        m:typeOfName(name):equals('string):ifElse({ nil }, {
            m:emitGlobal("SOLAVAL#") }).
        m:emitGlobal("SOLAFIELD$").
        m:emitLocal(slot).
        m:emitIntConst(i).
        m:emitSend("value", #2).
        m:typeOfName(name):equals('string):ifElse(
            { nil },
            { m:emitSend("value", #1).
              m:coerce('double, m:typeOfName(name)) }).
        m:endTarget(st:items:at(i)).
        i := i:add(#1) }).
    m:dropScratch }).

emitters:atPut('lineinput, { m, st | | name |
    name := st:items:at(#1):at(#1).
    m:typeOfName(name):equals('string):ifFalse({
        m:fail("LINE INPUT reads text, and '{}' is a number":fill([name])) }).
    m:beginTarget(st:items:at(#1)).
    st:channel:isNil:ifElse(
        { m:emitGlobal("SOLAASKLINE$").
          st:expr:isNil:ifElse({ m:emitString("") }, { m:emitString(st:expr:value) }).
          m:emitSend("value", #1) },
        { m:emitGlobal("SOLAFLINE$").
          m:emitTyped(st:channel, 'integer).
          m:emitSend("value", #1) }).
    m:endTarget(st:items:at(#1)) }).

; ---------------------------------------------------------------------------
; The file statements

emitters:atPut('open, { m, st |
    m:runtime("SOLAOPEN", {
        m:emitTyped(st:channel, 'integer).
        m:emitTyped(st:expr, 'string).
        m:emitIntConst(st:test) }, #3) }).

emitters:atPut('close, { m, st |
    st:items:size:equals(#0):ifElse(
        { m:runtime("SOLACLOSEALL", { nil }, #0) },
        { st:items:do({ each |
            m:runtime("SOLACLOSE", { m:emitTyped(each, 'integer) }, #1) }) }) }).

; `WRITE` puts commas between its items and quotes round its text, which is the
; form `INPUT #` reads back -- where `PRINT #`'s zones and spacing are for a
; person to look at.
emitters:atPut('write, { m, st | | i, item |
    m:onChannel(st, {
        i := #1.
        { i:lessOrEqual(st:items:size) }:whileTrue({
            item := st:items:at(i).
            i:equals(#1):ifFalse({ m:runtime("SOLAOUT", { m:emitString(",") }, #1) }).
            m:runtime("SOLAOUT", {
                item:type:equals('string):ifElse(
                    { m:emitString("\"").
                      m:emitTyped(item, 'string).
                      m:emitSend("concat", #1).
                      m:emitString("\"").
                      m:emitSend("concat", #1) },
                    { m:emitExpression(item).
                      m:emitSend("asString", #0) }) }, #1).
            i := i:add(#1) }).
        m:runtime("SOLAEOL", { nil }, #0) }) }).

emitters:atPut('randomize, { m, st |
    m:emitGlobal("random").
    m:emitTyped(st:expr, 'integer).
    m:emitSend("new", #1).
    m:emitStore(randomName).
    m:emitPop }).

; SHARED and STATIC did their work before the body was emitted -- they are in
; force for the whole procedure wherever they are written, so reading them in
; order would be the wrong answer for a listing that puts them at the bottom.
emitters:atPut('shared, { m, st | nil }).
emitters:atPut('static, { m, st | nil }).

; ---------------------------------------------------------------------------
; Procedures
;
; A `SUB` is a **block**, bound to a global with the procedure's name, and a call
; is `value`. That is the whole mapping, and it is a close fit rather than a
; contrivance: a block has its own frame, takes arguments in slots 1..n, and
; answers its last expression, which is what a procedure needs.
;
; **It never captures its home frame**, which matters more than it looks.
; ROADMAP 3.1 says a block that reads the frame it was written in cannot outlive
; it -- and a SolaBasic procedure has no reason to, because every name it uses is
; either its own slot or a global. So the flags say block-and-not-capturing, the
; procedure escapes freely, and the limitation that would have been in the way is
; not.
;
; **What it does meet is 3.5.** Each call is a real frame, so a recursive
; procedure runs out at about 254 levels. SOLABASIC.md predicted exactly that.

routine := object:new.
routine:name := "".
routine:kind := 'sub.
routine:params := nil.
routine:body := nil.
routine:line := #1.
routine:byref := nil.       ; one boolean per parameter
routine:arrayParams := nil. ; one boolean per parameter
routine:fromRuntime := false.

sola:routines := nil.
sola:routineOrder := nil.

; Procedures are lifted out of the listing before anything is emitted, which is
; what makes a call to something defined further down work and DECLARE useless.
sola:extractRoutines := { | rest, current |
    rest := array:new.
    current := nil.
    self:statements:do({ st |
        self:atLine := st:line.
        current:isNil:ifElse(
            { ['sub, 'function]:indexOf(st:kind):notNil:ifElse(
                { current := self:beginRoutine(st) },
                { ['endsub, 'endfunction]:indexOf(st:kind):notNil:ifTrue({
                      self:fail("{} with no procedure open"
                          :fill([st:kind:equals('endsub):ifElse(
                              { "END SUB" }, { "END FUNCTION" })])) }).
                  rest:add(st) }) },
            { ['sub, 'function]:indexOf(st:kind):notNil:ifTrue({
                  self:fail("a procedure cannot be written inside another") }).
              self:closesRoutine(current, st:kind):ifElse(
                  { ; a label on the closing line belongs to the body, so that
                    ; `GOTO Done` where `Done:` is the last line still lands.
                    st:label:notNil:ifTrue({
                        current:body:add(self:labelOnly(st:label, st:line)) }).
                    current := nil },
                  { current:body:add(st) }) }) }).
    current:notNil:ifTrue({
        self:atLine := current:line.
        self:fail("this {} is never closed by its END {}"
            :fill([current:kind:asString:asUppercase,
                   current:kind:asString:asUppercase])) }).
    self:statements := rest }.

sola:beginRoutine := { st | | r |
    self:routines:includes(st:name):ifTrue({
        self:fail("there are two procedures called '{}'":fill([st:name])) }).
    r := routine:new.
    r:name := st:name.
    r:kind := st:kind.
    r:params := st:items.
    r:arrayParams := st:arrayParams.
    r:fromRuntime := self:inPrelude.
    r:body := array:new.
    r:line := st:line.
    self:routines:atPut(st:name, r).
    self:routineOrder:add(r).
    r }.

sola:closesRoutine := { r, kind |
    r:kind:equals('sub):ifElse(
        { kind:equals('endsub) }, { kind:equals('endfunction) }) }.

; ---------------------------------------------------------------------------
; Which parameters are by reference
;
; QBasic passes by reference: assigning to a parameter assigns to the caller's
; variable. Passing everything by value instead would leave `SWAP`-shaped
; programs running and answering *differently*, which is the one outcome this
; project does not take -- so the analysis is here.
;
; **A parameter is by reference when the procedure assigns to it, or hands it on
; to somewhere that does.** The second half is why this is a fixed point rather
; than one pass: `A` passes its parameter to `B`, `B` passes it to `C`, and `C`
; assigns to it, so all three are by reference and finding that out takes as
; many rounds as the chain is long. It settles because a parameter only ever
; turns from by-value to by-reference and never back.

sola:analyseByRef := { | changed |
    self:routineOrder:do({ r |
        r:byref := r:params:collect({ p | self:assignsTo(r:body, p) }) }).
    changed := true.
    { changed }:whileTrue({
        changed := false.
        self:routineOrder:do({ r |
            self:callsIn(r:body):do({ c |
                self:propagate(r, c):ifTrue({ changed := true }) }) }) }) }.

sola:propagate := { r, call | | callee, changed, i, arg, at |
    changed := false.
    self:routines:includes(call:at(#1)):ifTrue({
        callee := self:routines:at(call:at(#1)).
        i := #1.
        { i:lessOrEqual(call:at(#2):size)
            :and({ i:lessOrEqual(callee:byref:size) }) }:whileTrue({
            callee:byref:at(i):ifTrue({
                arg := call:at(#2):at(i).
                arg:kind:equals('variable):and({ arg:grouped:not }):ifTrue({
                    at := r:params:indexOf(arg:name).
                    at:notNil:and({ r:byref:at(at):not }):ifTrue({
                        r:byref:atPut(at, true).
                        changed := true }) }) }).
            i := i:add(#1) }) }).
    changed }.

sola:assignsTo := { body, name | | found |
    found := false.
    body:do({ st | self:assignsIn(st, name):ifTrue({ found := true }) }).
    found }.

sola:assignsIn := { st, name | | found |
    st:kind:equals('group):ifElse({
        found := false.
        st:body:do({ each | self:assignsIn(each, name):ifTrue({ found := true }) }).
        found }, {
    st:kind:equals('let):and({ st:name:equals(name) })
        :or({ st:kind:equals('for):and({ st:name:equals(name) }) })
        :or({ ['input, 'lineinput]:indexOf(st:kind):notNil
              :and({ | hit |
                  hit := false.
                  st:items:do({ each |
                      each:at(#1):equals(name):ifTrue({ hit := true }) }).
                  hit }) })
        :or({ st:then:notNil:and({ self:assignsIn(st:then, name) }) })
        :or({ st:otherwise:notNil:and({ self:assignsIn(st:otherwise, name) }) }) }) }.

; Every call written in a body, statement and expression alike, as
; [name, arguments].
sola:callsIn := { body | | found |
    found := array:new.
    body:do({ st | self:callsInStatement(st, found) }).
    found }.

sola:callsInStatement := { st, found |
    st:kind:equals('call):ifTrue({
        found:add([st:name, st:items]).
        st:items:do({ a | self:callsInExpression(a, found) }) }).
    st:kind:equals('print):ifTrue({
        st:items:do({ a | self:isPlacement(a):ifFalse({
            self:callsInExpression(a, found) }) }) }).
    self:callsInExpression(st:expr, found).
    self:callsInExpression(st:limit, found).
    self:callsInExpression(st:step, found).
    st:subscripts:notNil:ifTrue({
        st:subscripts:do({ a | self:callsInExpression(a, found) }) }).
    self:inputTargetsDo(st, { a | self:callsInExpression(a, found) }).
    st:alternatives:notNil:ifTrue({
        st:alternatives:do({ alt |
            alt:at(#1):equals("is"):ifElse(
                { self:callsInExpression(alt:at(#3), found) },
                { self:callsInExpression(alt:at(#2), found).
                  alt:at(#1):equals("range"):ifTrue({
                      self:callsInExpression(alt:at(#3), found) }) }) }) }).
    st:then:notNil:ifTrue({ self:callsInStatement(st:then, found) }).
    st:otherwise:notNil:ifTrue({ self:callsInStatement(st:otherwise, found) }).
    st:kind:equals('group):ifTrue({
        st:body:do({ each | self:callsInStatement(each, found) }) }) }.

sola:callsInExpression := { n, found |
    n:isNil:ifFalse({
        n:kind:equals('call):ifTrue({
            found:add([n:name, n:args]).
            n:args:do({ a | self:callsInExpression(a, found) }) }).
        self:callsInExpression(n:left, found).
        self:callsInExpression(n:right, found) }) }.

; The names a body hands to a by-reference parameter as a plain variable. Those
; are the ones that have to live in a box, because the callee will reach into it.
sola:boxesFor := { body | | names |
    names := array:new.
    self:callsIn(body):do({ c |
        self:routines:includes(c:at(#1)):ifTrue({ | callee, i, arg |
            callee := self:routines:at(c:at(#1)).
            i := #1.
            { i:lessOrEqual(c:at(#2):size)
                :and({ i:lessOrEqual(callee:byref:size) }) }:whileTrue({
                callee:byref:at(i):ifTrue({
                    arg := c:at(#2):at(i).
                    arg:kind:equals('variable):and({ arg:grouped:not }):ifTrue({
                        names:indexOf(arg:name):isNil:ifTrue({
                            names:add(arg:name) }) }) }).
                i := i:add(#1) }) }) }).
    names }.

; ---------------------------------------------------------------------------
; A procedure, compiled

; A STATIC survives between calls, so it cannot be a frame slot -- a frame is
; new every call. It is a global of its own instead, named after the procedure
; that owns it and with spaces in the name so that nothing a BASIC program can
; spell will collide with it.
; "1 argument" and "2 arguments", because a message that says "1 argument(s)"
; was written by somebody who did not want to look at it again.
sola:countOf := { n, what |
    n:asString:concat(" "):concat(what):concat(n:equals(#1):ifElse({ "" }, { "s" })) }.

sola:staticName := { routineName, name |
    "static ":concat(routineName):concat(" "):concat(name) }.

; **And it is given its nought before anything runs**, because the first thing a
; counter does is read itself. A global that was never assigned is an undefined
; name, not a zero.
sola:emitStaticInitialisers := {
    self:routineOrder:do({ r |
        r:body:do({ st |
            st:kind:equals('static):ifTrue({
                st:items:do({ n |
                    self:emitZero(self:typeOfName(n)).
                    self:emitStore(self:staticName(r:name, n)).
                    self:emitPop }) }) }) }) }.

; What a call answers: a builtin says so itself, and a FUNCTION says so with
; the suffix on its own name, exactly as a variable does.
; **A FUNCTION of no arguments is written without brackets**, the same as a
; supplied one -- `x = Total` calls `FUNCTION Total`. The parser cannot know,
; because procedures are collected after the whole listing is read, so the
; decision waits until there is something to ask.
;
; Inside the function itself the name is its answer and not a call to itself,
; which is what `returnName` is doing here.
sola:isBareCall := { name |
    self:routines:includes(name)
        :and({ self:routines:at(name):params:size:equals(#0) })
        :and({ self:returnName:equals(name):not }) }.

sola:emitConstantValue := { name | | pair |
    pair := self:constants2:at(name).
    pair:at(#2):equals('string):ifElse(
        { self:emitString(pair:at(#1)) },
        { self:emitNumber(pair:at(#1), pair:at(#2)) }) }.

; ---------------------------------------------------------------------------
; A subscript, turned into one index
;
; A SolaBasic array is a Solum array, which is one-dimensional and counts from
; one. So `a(i)` is `i - low + 1`, and a second dimension multiplies by the size
; of the ones inside it -- the strides are constant because the bounds are, so
; all of that arithmetic that can be done at compile time is.
;
; **Every subscript of a multi-dimensional array is checked.** One out of range
; would otherwise land on a different element rather than off the end: `a(1, 9)`
; in an eight-by-eight is index 9, which is `a(2, 1)`, and answering the wrong
; element quietly is the one thing this must not do. A one-dimensional array
; needs no check, because there is nowhere for a bad subscript to land except
; outside the array, and the machine refuses that itself.

sola:emitSubscript := { name, subs | | bounds, count, strides, i, k, stride |
    bounds := self:boundsOf(name).
    count := bounds:size.
    subs:size:equals(count):ifFalse({
        self:fail("{} has {} and was given {}"
            :fill([name, self:countOf(count, "subscript"), subs:size])) }).

    strides := array:new.
    i := #1.
    { i:lessOrEqual(count) }:whileTrue({
        stride := #1.
        k := i:add(#1).
        { k:lessOrEqual(count) }:whileTrue({
            stride := stride:mul(
                bounds:at(k):at(#2):sub(bounds:at(k):at(#1)):add(#1)).
            k := k:add(#1) }).
        strides:add(stride).
        i := i:add(#1) }).

    i := #1.
    { i:lessOrEqual(count) }:whileTrue({
        self:emitOneSubscript(name, subs:at(i), bounds:at(i), i, count:greaterThan(#1)).
        self:emitIntConst(bounds:at(i):at(#1)).
        self:emitSend("sub", #1).
        strides:at(i):equals(#1):ifFalse({
            self:emitIntConst(strides:at(i)).
            self:emitSend("mul", #1) }).
        i:equals(#1):ifFalse({ self:emitSend("add", #1) }).
        i := i:add(#1) }).
    self:emitIntConst(#1).
    self:emitSend("add", #1) }.

sola:emitOneSubscript := { name, node, bound, which, checked | | slot, fine |
    checked:ifElse(
        { slot := self:intoScratchAs(node, 'integer).
          self:emitLocal(slot).
          self:emitIntConst(bound:at(#1)).
          self:emitSend("lessThan", #1).
          fine := self:branchHole.
          self:emitRaise("subscript {} of {} is below {}"
              :fill([which, name, bound:at(#1)])).
          self:fillBranch(fine).
          self:emitLocal(slot).
          self:emitIntConst(bound:at(#2)).
          self:emitSend("greaterThan", #1).
          fine := self:branchHole.
          self:emitRaise("subscript {} of {} is above {}"
              :fill([which, name, bound:at(#2)])).
          self:fillBranch(fine).
          self:emitLocal(slot).
          self:dropScratch },
        { self:emitTyped(node, 'integer) }) }.

; Stopping the program with something to read. `raise` answers, as far as the
; verifier is concerned, so its answer is popped -- it never gets there.
sola:emitRaise := { message |
    self:emitGlobal("error").
    self:emitString(message).
    self:emitSend("raise", #1).
    self:emitPop }.

sola:typeOfCall := { n | | answers |
    self:isArray(n:name):ifElse({ self:typeOfName(n:name) }, {
    builtins:includes(n:name):ifElse(
        { answers := builtins:at(n:name):at(#2).
          answers:equals('sameAsArg):ifElse(
              { n:args:size:equals(#0):ifElse(
                  { 'double },
                  { n:args:at(#1):type:equals('integer):ifElse(
                      { 'integer }, { 'double }) }) },
              { answers }) },
        { self:routines:includes(n:name):ifElse(
            { self:typeOfName(n:name) },
            { self:fail("there is no SUB, FUNCTION or array called '{}' -- an "
                :concat("array is DIMmed before it is used"):fill([n:name])) }) }) }) }.

; ---------------------------------------------------------------------------
; What shape an array parameter has
;
; The bounds of an array are settled while compiling, and a parameter's are not
; -- they arrive with whatever is passed. **So they are read off the call
; sites.** Every array handed to a given parameter is looked at, and if they all
; agree the parameter has that shape; if two disagree the listing is refused,
; naming both, rather than a wrong element being answered quietly.
;
; That is what lets a two-dimensional array be passed at all. A descriptor
; travelling with the array would be the other way, and would cost every
; subscript in the language a lookup to buy a case this one refuses out loud.

sola:arrayShapes := nil.

sola:shapeKey := { name, i | name:concat(" "):concat(i:asString) }.

sola:sameShape := { a, b | | same, i |
    a:size:equals(b:size):ifElse(
        { same := true.
          i := #1.
          { i:lessOrEqual(a:size) }:whileTrue({
              a:at(i):at(#1):equals(b:at(i):at(#1))
                  :and({ a:at(i):at(#2):equals(b:at(i):at(#2)) }):ifFalse({
                  same := false }).
              i := i:add(#1) }).
          same },
        { false }) }.

sola:resolveArrayShapes := {
    self:arrayShapes := dictionary:new.
    self:routineOrder:do({ r | self:shapesFromCalls(r:body) }).
    self:shapesFromCalls(self:statements) }.

sola:shapesFromCalls := { body |
    self:callsIn(body):do({ c |
        self:routines:includes(c:at(#1)):ifTrue({ | callee, i, arg, key, bounds |
            callee := self:routines:at(c:at(#1)).
            i := #1.
            { i:lessOrEqual(c:at(#2):size)
                :and({ i:lessOrEqual(callee:params:size) }) }:whileTrue({
                callee:arrayParams:at(i):and({
                    c:at(#2):at(i):kind:equals('arrayref) }):ifTrue({
                    arg := c:at(#2):at(i).
                    self:arrays:includes(arg:name):ifTrue({
                        bounds := self:arrays:at(arg:name):at(#1).
                        key := self:shapeKey(c:at(#1), i).
                        self:arrayShapes:includes(key):ifElse(
                            { self:sameShape(self:arrayShapes:at(key), bounds):ifFalse({
                                  self:fail("{}'s {} is given arrays of two shapes, "
                                      :concat("and its subscripts are worked out while ")
                                      :concat("compiling")
                                      :fill([c:at(#1), callee:params:at(i)])) }) },
                            { self:arrayShapes:atPut(key, bounds) }) }) }).
                i := i:add(#1) }) }) }) }.

sola:emitReturnValue := {
    self:returnName:equals(""):ifElse(
        { self:emitNil },
        { self:emitLoadVar(self:returnName) }) }.

sola:emitRoutine := { r | | method, index, i |
    self:pushUnit.
    self:inProcedure := true.
    r:fromRuntime:ifTrue({ self:unitPath := "the SolaBasic runtime" }).
    self:atLine := r:line.
    self:returnName := r:kind:equals('function):ifElse({ r:name }, { "" }).

    r:body:do({ st |
        st:kind:equals('shared):ifTrue({
            st:items:do({ n | self:shared:add(n) }) }).
        st:kind:equals('static):ifTrue({
            st:items:do({ n |
                self:statics:atPut(n, self:staticName(r:name, n)) }) }) }).

    ; Slots 1..n are the parameters, in the order they were written, because
    ; that is where a block's arguments arrive.
    r:params:do({ p | self:newLocal(p) }).
    i := #1.
    { i:lessOrEqual(r:params:size) }:whileTrue({
        r:arrayParams:at(i):ifTrue({ | key |
            key := self:shapeKey(r:name, i).
            self:arrayParams:atPut(r:params:at(i),
                self:arrayShapes:includes(key):ifElse(
                    { self:arrayShapes:at(key) },
                    { [[self:optionBase, nil]] })) }).
        i := i:add(#1) }).
    i := #1.
    { i:lessOrEqual(r:params:size) }:whileTrue({
        r:byref:at(i):ifTrue({ self:boxed:add(r:params:at(i)) }).
        i := i:add(#1) }).
    self:boxesFor(r:body):do({ n |
        self:boxed:indexOf(n):isNil:ifTrue({
            self:boxed:add(n).
            self:toBox:add(n) }) }).

    ; A FUNCTION answers by assigning to its own name, so the name is a local
    ; and the body's last act is to push it.
    r:kind:equals('function):ifTrue({ self:newLocal(r:name) }).

    self:mark(r:line).
    r:kind:equals('function):ifTrue({
        self:emitZero(self:typeOfName(r:name)).
        self:emitSetLocal(self:slotFor(r:name)).
        self:emitPop }).
    self:statementsOfScope := r:body.
    self:emitVariableInitialisers(
        r:params:copyFrom(#1, r:params:size):add(r:name)).
    self:emitBoxes.
    r:body:do({ st | self:emitStatement(st) }).
    self:checkBlocksClosed.
    self:mark(self:atLine).
    self:emitReturnValue.
    self:byte(RETURN).

    method := self:chunkOfUnit.
    method:atPut("name", r:name).
    method:atPut("arity", r:params:size).
    ; Flag 1 says block. Flag 2 would say it reaches out of its own frame, and
    ; nothing here ever does -- see the note above about 3.1.
    method:atPut("flags", #1).
    self:popUnit.

    index := self:methods:size.
    self:methods:add(method).
    self:byte(BLOCK).
    self:u16(index).
    self:emitStore(r:name).
    self:emitPop }.

; ---------------------------------------------------------------------------
; A call
;
; The block, then the arguments, then `value`. A by-reference argument that is a
; plain variable hands over **the box itself**, so the callee's `atPut` writes
; the caller's storage and there is nothing to copy back.
;
; An argument at a by-reference position that is *not* a plain variable -- an
; expression, or a name in brackets -- gets a box of its own that nobody keeps.
; That is QBasic's rule and it is what `CALL Foo((x))` is for.

sola:emitCall := { name, args, asStatement | | r, i, arg, wanted |
    builtins:includes(name):ifTrue({
        self:emitBuiltin(name, args).
        asStatement:ifTrue({ self:emitPop }) }).
    builtins:includes(name):ifFalse({
    self:routines:includes(name):ifFalse({
        self:fail("there is no SUB or FUNCTION called '{}'":fill([name])) }).
    r := self:routines:at(name).
    args:size:equals(r:params:size):ifFalse({
        self:fail("{} takes {} and was given {}"
            :fill([name, self:countOf(r:params:size, "argument"),
                   args:size])) }).

    self:emitGlobal(name).
    i := #1.
    { i:lessOrEqual(args:size) }:whileTrue({
        arg := args:at(i).
        wanted := self:typeOfName(r:params:at(i)).
        arg:kind:equals('arrayref):ifTrue({
            r:arrayParams:at(i):ifFalse({
                self:fail("{}'s {} is not an array":fill([name, r:params:at(i)])) }).
            self:emitRawVar(arg:name) }).
        arg:kind:equals('arrayref):ifElse({ nil }, {
        r:byref:at(i):ifElse(
            { arg:kind:equals('variable):and({ arg:grouped:not }):ifElse(
                { ; The box is handed over as it stands, so the two names have to
                  ; agree about what is in it: the callee writes through it and
                  ; the caller reads back what it wrote.
                  self:typeOfName(arg:name):equals(wanted):ifFalse({
                      self:fail("{} and {}'s {} are different types, and a "
                          :concat("variable passed by reference must match")
                          :fill([arg:name, name, r:params:at(i)])) }).
                  self:emitRawVar(arg:name) },
                { self:emitGlobal("array").
                  self:emitTyped(arg, wanted).
                  self:emitSend("of", #1) }) },
            { self:emitTyped(arg, wanted) }) }).
        i := i:add(#1) }).
    self:emitSend("value", args:size).
    asStatement:ifTrue({ self:emitPop }) }) }.

; ---------------------------------------------------------------------------
; The supplied functions
;
; **Each one is emitted where it is called rather than being a procedure that is
; called.** There is nowhere to put a library: the `.sob` this compiler writes is
; the whole program, and none of `lib/` is in it. So a builtin is a short
; sequence of instructions, and the ones that need to decide something -- `SGN`,
; `INSTR`, the clamping in `LEFT$` -- decide it with the same jumps a `SELECT
; CASE` uses.
;
; An entry is `[argument types, what it answers, how, detail]`, and
; `'sameAsArg` answers whatever its argument was, which is how `ABS` and `INT`
; keep an Integer an Integer.
;
; **`how` is a symbol and not a block, and that is 3.1's doing.** The first
; version of this had a helper that built the emitting block and stored it --
; and the block read the helper's parameters, so it captured a frame that had
; already returned by the time anything called it.
; [3.1](../docs/ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) says a
; block that reads its home frame cannot outlive it, and the machine said so
; exactly: *block outlived the frame it was written in*. The blocks further down
; are written at the top level, read nothing but their own parameters, and are
; fine; the two shapes that were not are a symbol and a selector instead.

sola:builtinArg := { args, i, t | self:emitTyped(args:at(i), t) }.

; A builtin of one argument that is one send.
sola:simpleBuiltin := { name, argType, answers, selector |
    builtins:atPut(name, [[argType], answers, 'simple, selector]) }.

sola:simpleBuiltin("ABS",   'double, 'sameAsArg, "abs").
sola:simpleBuiltin("ATN",   'double, 'double, "atan").
sola:simpleBuiltin("COS",   'double, 'double, "cos").
sola:simpleBuiltin("SIN",   'double, 'double, "sin").
sola:simpleBuiltin("TAN",   'double, 'double, "tan").
sola:simpleBuiltin("EXP",   'double, 'double, "exp").
sola:simpleBuiltin("LOG",   'double, 'double, "log").
sola:simpleBuiltin("SQR",   'double, 'double, "sqrt").
sola:simpleBuiltin("LEN",   'string, 'integer, "size").
sola:simpleBuiltin("UCASE$", 'string, 'string, "asUppercase").
sola:simpleBuiltin("LCASE$", 'string, 'string, "asLowercase").

sola:simpleBuiltin("CHR$",  'integer, 'string, "asCharacter").

; `ABS` on an Integer must stay an Integer, so the argument is not forced to a
; Double first. The table above says `'double`; this overrides it.
builtins:atPut("ABS", [['numeric], 'sameAsArg, 'block,
    { m, args | m:emitExpression(args:at(#1)). m:emitSend("abs", #0) }]).

; **`VAL` is strict here**, where BASIC's is lenient: the whole string has to be
; a number, and `VAL("12ab")` is an error rather than `12`. Reading a number out
; of the front of a string wants a scanner, and there is not one in the emitted
; program -- see the reference manual, which says so where somebody will look.
builtins:atPut("STR$", [['numeric], 'string, 'block,
    { m, args |
        args:at(#1):type:equals('string):ifTrue({
            m:fail("STR$ turns a number into text, and was given text") }).
        m:emitExpression(args:at(#1)).
        m:emitSend("asString", #0) }]).

; Writing a finished line, which is the one thing the runtime below cannot do
; for itself: SolaBasic has no way to put text on the terminal except `PRINT`,
; and `PRINT` is what it is implementing.
builtins:atPut("SOLAWRITE", [['string], 'string, 'block,
    { m, args | m:builtinArg(args, #1, 'string). m:emitSend("display", #0) }]).

; The same, without ending the line. `INPUT "NAME"; N$` has to show its prompt
; and then read the answer beside it, which is the one thing `display` cannot
; do -- and the reason basic.sol's header says its line buffer stops being
; enough at stage four.
builtins:atPut("SOLAWRITERAW", [['string], 'string, 'block,
    { m, args |
        m:emitGlobal("system").
        m:builtinArg(args, #1, 'string).
        m:emitSend("write", #1) }]).

; One line of standard input, or the empty string once there is no more. The
; machine answers nil at the end and SolaBasic has no nil to answer with.
builtins:atPut("SOLAREAD$", [[], 'string, 'block,
    { m, args | | slot, empty, done |
        m:emitGlobal("system").
        m:emitSend("readLine", #0).
        slot := m:takeScratch.
        m:emitSetLocal(slot). m:emitPop.
        m:emitLocal(slot). m:emitSend("notNil", #0).
        empty := m:branchHole.
        m:emitLocal(slot).
        done := m:hole.
        m:fillBranch(empty).
        ; **A NUL says the input ran out**, which an ordinary line cannot: the
        ; empty string is a blank line somebody typed and has to stay one.
        m:emitIntConst(#0).
        m:emitSend("asCharacter", #0).
        m:fillJump(done).
        m:dropScratch }]).

; **Whether anybody is watching.** QuickBASIC echoes an answer it read from a
; redirected file, so that a transcript reads the way the session looked; at a
; terminal it does not, because the terminal has already shown what was typed.
; There is no way here to ask whether *input* is a terminal, so this asks about
; output, which is the same thing every time it matters.
builtins:atPut("SOLAPIPED%", [[], 'integer, 'block,
    { m, args |
        m:emitGlobal("system").
        m:emitSend("terminalSize", #0).
        m:emitSend("isNil", #0).
        m:materialise('integer) }]).

; Whole-file reading and writing, which is all the machine offers -- there is
; no streaming here, so a channel open for reading holds the file and a channel
; open for writing holds what has been written until it is closed.
builtins:atPut("SOLAREADFILE$", [['string], 'string, 'block,
    { m, args |
        m:emitGlobal("system").
        m:builtinArg(args, #1, 'string).
        m:emitSend("readFile", #1) }]).

builtins:atPut("SOLAEXISTS%", [['string], 'integer, 'block,
    { m, args |
        m:emitGlobal("system").
        m:builtinArg(args, #1, 'string).
        m:emitSend("fileExists", #1).
        m:materialise('integer) }]).

builtins:atPut("SOLAWRITEFILE", [['string, 'string], 'string, 'block,
    { m, args |
        m:emitGlobal("system").
        m:builtinArg(args, #1, 'string).
        m:builtinArg(args, #2, 'string).
        m:emitSend("writeFile", #2) }]).

builtins:atPut("SOLAAPPENDFILE", [['string, 'string], 'string, 'block,
    { m, args |
        m:emitGlobal("system").
        m:builtinArg(args, #1, 'string).
        m:builtinArg(args, #2, 'string).
        m:emitSend("appendFile", #2) }]).

; `EOF(n)` is the runtime's answer, not an instruction -- it asks the channel.
builtins:atPut("EOF", [['integer], 'integer, 'block,
    { m, args |
        m:emitGlobal("SOLAFEOF%").
        m:builtinArg(args, #1, 'integer).
        m:emitSend("value", #1) }]).

builtins:atPut("SOLAFAIL", [['string], 'string, 'block,
    { m, args |
        m:emitGlobal("error").
        m:builtinArg(args, #1, 'string).
        m:emitSend("raise", #1) }]).

; `TAB` and `SPC` are not functions -- they move the place the next thing goes,
; which only means anything inside a PRINT. They are here so that a call to one
; has a type, and they refuse to be emitted anywhere else.
builtins:atPut("TAB", [['integer], 'integer, 'block,
    { m, args | m:fail("TAB moves PRINT along, so it only goes inside one") }]).
builtins:atPut("SPC", [['integer], 'integer, 'block,
    { m, args | m:fail("SPC moves PRINT along, so it only goes inside one") }]).

builtins:atPut("VAL", [['string], 'double, 'block,
    { m, args | m:builtinArg(args, #1, 'string). m:emitSend("asFloat", #0) }]).

builtins:atPut("ASC", [['string], 'integer, 'block,
    { m, args |
        m:builtinArg(args, #1, 'string).
        m:emitIntConst(#1). m:emitSend("at", #1).
        m:emitSend("asByte", #0) }]).

; `INT` is the floor and `FIX` cuts towards nought, and they differ only for a
; negative: INT(-2.5) is -3 and FIX(-2.5) is -2.
sola:roundingBuiltin := { name, selector |
    builtins:atPut(name, [['numeric], 'sameAsArg, 'rounding, selector]) }.
sola:roundingBuiltin("INT", "floor").
sola:roundingBuiltin("FIX", "truncated").

; `SGN` needs its argument twice and there is no instruction that duplicates the
; top of the stack, so it goes into a scratch slot first.
builtins:atPut("SGN", [['double], 'integer, 'block,
    { m, args | | x, notNegative, isZero, fromNegative, fromPositive |
        x := m:intoScratchAs(args:at(#1), 'double).
        m:emitLocal(x). m:emitConst(0.0). m:emitSend("lessThan", #1).
        notNegative := m:branchHole.
        m:emitIntConst(#-1).
        fromNegative := m:hole.

        m:fillBranch(notNegative).
        m:emitLocal(x). m:emitConst(0.0). m:emitSend("greaterThan", #1).
        isZero := m:branchHole.
        m:emitIntConst(#1).
        fromPositive := m:hole.

        m:fillBranch(isZero).
        m:emitIntConst(#0).

        ; **Three arms and three jumps.** An earlier draft had two arms sharing
        ; one hole, which patched it twice and sent the first arm wherever the
        ; second one landed. The verifier refused the file rather than running
        ; it -- *bytecode is internally inconsistent*, at load, exit 65 -- which
        ; is the whole reason a Solum-emitted `.sob` is checked before it runs.
        m:fillJump(fromNegative).
        m:fillJump(fromPositive).
        m:dropScratch }]).

; **`INSTR` answers 0 when it does not find it**, where the machine answers nil.
builtins:atPut("INSTR", [['string, 'string], 'integer, 'block,
    { m, args | | found, zero, done |
        args:size:equals(#3):ifElse(
            { m:builtinArg(args, #2, 'string).
              m:builtinArg(args, #3, 'string).
              m:builtinArg(args, #1, 'integer).
              m:emitSend("indexOf", #2) },
            { m:builtinArg(args, #1, 'string).
              m:builtinArg(args, #2, 'string).
              m:emitSend("indexOf", #1) }).
        found := m:takeScratch.
        m:emitSetLocal(found). m:emitPop.
        m:emitLocal(found). m:emitSend("notNil", #0).
        zero := m:branchHole.
        m:emitLocal(found).
        done := m:hole.
        m:fillBranch(zero).
        m:emitIntConst(#0).
        m:fillJump(done).
        m:dropScratch }]).

; ---------------------------------------------------------------------------
; The ones that take a piece of a string
;
; `copyFrom` refuses a range outside the string and BASIC clamps, so the bounds
; are pushed into a slot and squared up with two comparisons before they are
; used. That is what most of the length here is.

sola:emitClampLow := { slot, low | | fine |
    self:emitLocal(slot). self:emitIntConst(low). self:emitSend("lessThan", #1).
    fine := self:branchHole.
    self:emitIntConst(low). self:emitSetLocal(slot). self:emitPop.
    self:fillBranch(fine) }.

sola:emitClampToSize := { slot, strSlot | | fine |
    self:emitLocal(slot).
    self:emitLocal(strSlot). self:emitSend("size", #0).
    self:emitSend("greaterThan", #1).
    fine := self:branchHole.
    self:emitLocal(strSlot). self:emitSend("size", #0).
    self:emitSetLocal(slot). self:emitPop.
    self:fillBranch(fine) }.

builtins:atPut("LEFT$", [['string, 'integer], 'string, 'block,
    { m, args | | str, n |
        str := m:intoScratchAs(args:at(#1), 'string).
        n := m:intoScratchAs(args:at(#2), 'integer).
        m:emitClampLow(n, #0).
        m:emitClampToSize(n, str).
        m:emitLocal(str). m:emitIntConst(#1). m:emitLocal(n).
        m:emitSend("copyFrom", #2).
        m:dropScratch. m:dropScratch }]).

builtins:atPut("RIGHT$", [['string, 'integer], 'string, 'block,
    { m, args | | str, n |
        str := m:intoScratchAs(args:at(#1), 'string).
        n := m:intoScratchAs(args:at(#2), 'integer).
        m:emitClampLow(n, #0).
        m:emitClampToSize(n, str).
        ; from = size - n + 1
        m:emitLocal(str). m:emitSend("size", #0).
        m:emitLocal(n). m:emitSend("sub", #1).
        m:emitIntConst(#1). m:emitSend("add", #1).
        m:emitSetLocal(n). m:emitPop.
        m:emitLocal(str). m:emitLocal(n).
        m:emitLocal(str). m:emitSend("size", #0).
        m:emitSend("copyFrom", #2).
        m:dropScratch. m:dropScratch }]).

; `MID$(s, start)` and `MID$(s, start, length)`. A start past the end is the
; empty string rather than an error, which is BASIC's rule.
builtins:atPut("MID$", [['string, 'integer], 'string, 'block,
    { m, args | | str, from, last, empty, done |
        str := m:intoScratchAs(args:at(#1), 'string).
        from := m:intoScratchAs(args:at(#2), 'integer).
        last := m:takeScratch.
        m:emitClampLow(from, #1).

        args:size:equals(#3):ifElse(
            { m:emitLocal(from).
              m:builtinArg(args, #3, 'integer).
              m:emitSend("add", #1).
              m:emitIntConst(#1). m:emitSend("sub", #1) },
            { m:emitLocal(str). m:emitSend("size", #0) }).
        m:emitSetLocal(last). m:emitPop.
        m:emitClampToSize(last, str).

        m:emitLocal(from).
        m:emitLocal(last).
        m:emitSend("greaterThan", #1).
        empty := m:branchHole.
        m:emitString("").
        done := m:hole.
        m:fillBranch(empty).
        m:emitLocal(str). m:emitLocal(from). m:emitLocal(last).
        m:emitSend("copyFrom", #2).
        m:fillJump(done).
        m:dropScratch. m:dropScratch. m:dropScratch }]).

; ---------------------------------------------------------------------------
; The ones that need a loop
;
; A loop in a builtin is the same `LOOP` and `JUMP_IF_FALSE` a `WHILE` compiles
; to, which is why these cost lines here and nothing new in the machine.

sola:emitTrim := { args, fromLeft | | str, i, top, out |
    str := self:intoScratchAs(args:at(#1), 'string).
    i := self:takeScratch.
    fromLeft:ifElse(
        { self:emitIntConst(#1) },
        { self:emitLocal(str). self:emitSend("size", #0) }).
    self:emitSetLocal(i). self:emitPop.

    top := self:here.
    ; while i is in range and the character there is a space
    fromLeft:ifElse(
        { self:emitLocal(i).
          self:emitLocal(str). self:emitSend("size", #0).
          self:emitSend("lessOrEqual", #1) },
        { self:emitLocal(i). self:emitIntConst(#1).
          self:emitSend("greaterOrEqual", #1) }).
    out := self:branchHole.
    self:emitLocal(str). self:emitLocal(i). self:emitSend("at", #1).
    self:emitString(" "). self:emitSend("equals", #1).
    out := [out, self:branchHole].
    self:emitLocal(i).
    self:emitIntConst(fromLeft:ifElse({ #1 }, { #-1 })).
    self:emitSend("add", #1).
    self:emitSetLocal(i). self:emitPop.
    self:emitLoopTo(top).
    self:fillBranch(out:at(#1)).
    self:fillBranch(out:at(#2)).

    fromLeft:ifElse(
        { self:emitLocal(str). self:emitLocal(i).
          self:emitLocal(str). self:emitSend("size", #0) },
        { self:emitLocal(str). self:emitIntConst(#1). self:emitLocal(i) }).
    self:emitSend("copyFrom", #2).
    self:dropScratch. self:dropScratch }.

builtins:atPut("LTRIM$", [['string], 'string, 'block,
    { m, args | m:emitTrim(args, true) }]).
builtins:atPut("RTRIM$", [['string], 'string, 'block,
    { m, args | m:emitTrim(args, false) }]).

; `STRING$(n, s)` is `s`'s first character n times; `SPACE$(n)` is that with a
; space.
sola:emitRepeatString := { countNode, charNode | | out, i, n, top, done |
    n := self:intoScratchAs(countNode, 'integer).
    out := self:takeScratch.
    i := self:takeScratch.
    charNode:isNil:ifElse(
        { self:emitString(" ") },
        { self:emitTyped(charNode, 'string).
          self:emitIntConst(#1). self:emitSend("at", #1) }).
    self:emitSetLocal(out). self:emitPop.
    self:emitString("").
    self:emitSetLocal(i). self:emitPop.

    top := self:here.
    self:emitLocal(n). self:emitIntConst(#0). self:emitSend("greaterThan", #1).
    done := self:branchHole.
    self:emitLocal(i). self:emitLocal(out). self:emitSend("concat", #1).
    self:emitSetLocal(i). self:emitPop.
    self:emitLocal(n). self:emitIntConst(#1). self:emitSend("sub", #1).
    self:emitSetLocal(n). self:emitPop.
    self:emitLoopTo(top).
    self:fillBranch(done).
    self:emitLocal(i).
    self:dropScratch. self:dropScratch. self:dropScratch }.

builtins:atPut("SPACE$", [['integer], 'string, 'block,
    { m, args | m:emitRepeatString(args:at(#1), nil) }]).
builtins:atPut("STRING$", [['integer, 'string], 'string, 'block,
    { m, args | m:emitRepeatString(args:at(#1), args:at(#2)) }]).

; ---------------------------------------------------------------------------
; RND, and the generator it reads from
;
; One generator for the program, made before its first line runs. `RANDOMIZE`
; replaces it with one seeded to repeat.

randomName := "the random generator".

builtins:atPut("RND", [[], 'double, 'block,
    { m, args |
        m:emitGlobal(randomName).
        m:emitSend("fraction", #0) }]).

sola:emitRandomGenerator := {
    self:emitGlobal("random").
    self:emitSend("new", #0).
    self:emitStore(randomName).
    self:emitPop }.

; ---------------------------------------------------------------------------
; Emitting one, and checking it was called properly

sola:emitBuiltin := { name, args | | entry, how |
    entry := builtins:at(name).
    self:checkBuiltinArity(name, args, entry).
    how := entry:at(#3).
    [ { how:equals('simple) },
        { self:builtinArg(args, #1, entry:at(#1):at(#1)).
          self:emitSend(entry:at(#4), #0) },
      { how:equals('rounding) },
        { args:at(#1):type:equals('integer):ifElse(
            { self:emitExpression(args:at(#1)) },
            { self:builtinArg(args, #1, 'double).
              self:emitSend(entry:at(#4), #0).
              self:emitSend("asFloat", #0) }) },
        { entry:at(#4):value(self, args) } ]:ifElseIf }.

sola:checkBuiltinArity := { name, args, entry | | least, most |
    least := entry:at(#1):size.
    most := least.
    ["MID$", "INSTR"]:indexOf(name):notNil:ifTrue({ most := #3 }).
    args:size:lessThan(least):or({ args:size:greaterThan(most) }):ifTrue({
        self:fail("{} takes {} and was given {}"
            :fill([name, self:countOf(least, "argument"), args:size])) }) }.

; `IF <condition> THEN GOTO <label>` is the condition, a conditional jump over
; the `GOTO`, and the `GOTO`.
;
; `OP_JUMP_IF_FALSE` carries the name of the selector it was inlined from so
; that a non-boolean reports the same *does not understand* a real send would.
; There is no real send here to name, so it names `ifTrue` -- which is the
; message a condition that is not a boolean has failed to understand, and is
; what the reader of the error needs to be told.


; A condition that is already a comparison answers a boolean. Anything else is
; a number, and BASIC's rule is that a non-zero number is true -- so it is
; compared with nought rather than handed to the machine, which would refuse it.
sola:emitCondition := { n | self:emitTyped(n, 'boolean) }.

; The items of one PRINT are joined and shown once, so that `PRINT "x = "; x`
; is one line. **This is not BASIC's PRINT**: there are no print zones, no
; leading space in front of a positive number and no trailing space after one,
; and `,` does the same thing as `;`. That is stage 6 and this is stage 3.
; A call into the runtime: the block, its arguments, `value`, and the answer
; thrown away.
; A statement that names a file number does its work with the runtime pointed
; at that channel, and puts it back on the screen afterwards.
sola:onChannel := { st, body |
    st:channel:isNil:ifElse(
        { body:value },
        { self:emitTyped(st:channel, 'integer).
          self:emitStore("SOLACH%").
          self:emitPop.
          body:value.
          self:emitIntConst(#0).
          self:emitStore("SOLACH%").
          self:emitPop }) }.

sola:runtime := { name, emitArgs, argc |
    self:emitGlobal(name).
    emitArgs:value.
    self:emitSend("value", argc).
    self:emitPop }.

sola:isPlacement := { item |
    item:notNil:and({ item:kind:equals('call) })
        :and({ ["TAB", "SPC"]:indexOf(item:name):notNil }) }.

; A string goes out as it is; a number is turned into text and then given the
; sign character and the trailing space that make BASIC output look the way it
; does.
; **A comparison is `-1` or `0` here, like anywhere else it is used as a
; number.** Emitting it without saying so printed `true`, and then the runtime's
; exponent swap turned that into `truD` -- which is what a real QuickBASIC found
; on the first run of the oracle harness, and what eleven recorded transcripts
; had not, because none of them thought to print a comparison.
sola:emitItemText := { item |
    item:type:equals('string):ifElse(
        { self:emitTyped(item, 'string) },
        { self:emitGlobal("SOLASIGN$").
          self:emitTyped(item,
              item:type:equals('boolean):ifElse({ 'integer }, { item:type })).
          self:emitSend("asString", #0).
          self:emitSend("value", #1) }) }.

sola:emitFinalFlush := { | done |
    self:hasPrelude:ifTrue({
        self:emitGlobal("SOLABUF$").
        self:emitSend("size", #0).
        self:emitIntConst(#0).
        self:emitSend("greaterThan", #1).
        done := self:branchHole.
        self:runtime("SOLAEOL", { nil }, #0).
        self:fillBranch(done).
        ; A file open for writing has not been written yet, so stopping the
        ; program has to close it.
        self:runtime("SOLACLOSEALL", { nil }, #0) }) }.

; ---------------------------------------------------------------------------
; PRINT USING
;
; The format is walked by the runtime rather than by the compiler, because it is
; an expression and may be a variable -- so nothing about it is known until the
; program runs. The runtime keeps its place between items, which is what lets a
; format shorter than the list of items start again from the beginning.

sola:emitPrintUsing := { st | | i, item |
    self:runtime("SOLAUSTART", { self:emitTyped(st:using, 'string) }, #1).
    i := #1.
    { i:lessOrEqual(st:items:size) }:whileTrue({
        item := st:items:at(i).
        item:isNil:ifFalse({
            self:runtime("SOLAOUT", {
                self:emitGlobal("SOLAUONE$").
                item:type:equals('string):ifElse(
                    { self:emitConst(0.0).
                      self:emitTyped(item, 'string).
                      self:emitIntConst(#0) },
                    { self:emitTyped(item, 'double).
                      self:emitString("").
                      self:emitIntConst(#1) }).
                self:emitSend("value", #3) }, #1) }).
        i := i:add(#1) }).
    self:runtime("SOLAOUT", {
        self:emitGlobal("SOLAUTAIL$").
        self:emitSend("value", #0) }, #1).
    st:seps:at(st:seps:size):equals("none"):ifTrue({
        self:runtime("SOLAEOL", { nil }, #0) }) }.

sola:emitPrint := { st |
    self:onChannel(st, { self:emitPrintBody(st) }) }.

sola:emitPrintBody := { st | | i, item |
    st:using:notNil:ifTrue({ self:emitPrintUsing(st) }).
    st:using:notNil:ifElse({ nil }, {
    st:items:size:equals(#0):ifElse(
        { self:runtime("SOLAEOL", { nil }, #0) },
        { i := #1.
          { i:lessOrEqual(st:items:size) }:whileTrue({
              item := st:items:at(i).
              item:isNil:ifFalse({
                  self:isPlacement(item):ifElse(
                      { self:runtime(
                            item:name:equals("TAB"):ifElse({ "SOLATAB" }, { "SOLASPC" }),
                            { self:emitTyped(item:args:at(#1), 'integer) }, #1) },
                      { self:runtime("SOLAOUT", { self:emitItemText(item) }, #1) }) }).
              st:seps:at(i):equals("comma"):ifTrue({
                  self:runtime("SOLAZONE", { nil }, #0) }).
              i := i:add(#1) }).
          st:seps:at(st:seps:size):equals("none"):ifTrue({
              self:runtime("SOLAEOL", { nil }, #0) }) }) }) }.

; ---------------------------------------------------------------------------
; Which line a byte came from
;
; Run-length encoded, because neighbouring instructions almost always share a
; line. A mark is dropped at each statement and the runs are the gaps between
; them, so the total is the size of the code and the loader can rebuild the
; parallel array it wants.

sola:mark := { line |
    self:lineMarks:add([self:here, line]) }.

sola:lineRuns := { | runs, i, at, next, line |
    runs := array:new.
    i := #1.
    { i:lessOrEqual(self:lineMarks:size) }:whileTrue({
        at := self:lineMarks:at(i):at(#1).
        line := self:lineMarks:at(i):at(#2).
        next := i:equals(self:lineMarks:size):ifElse(
            { self:code:size },
            { self:lineMarks:at(i:add(#1)):at(#1) }).
        next:greaterThan(at):ifTrue({
            runs:size:notEquals(#0):and({
                runs:at(runs:size):at(#2):equals(line) }):ifElse(
                { runs:at(runs:size):atPut(#1,
                    runs:at(runs:size):at(#1):add(next:sub(at))) },
                { runs:add([next:sub(at), line]) }) }).
        i := i:add(#1) }).
    runs }.

; ---------------------------------------------------------------------------
; The whole of it

sola:compile := { source, path |
    self:path := path.
    self:statements := array:new.
    self:unitStack := array:new.
    self:routines := dictionary:new.
    self:routineOrder := array:new.
    self:defaultTypes := dictionary:new.
    self:arrays := dictionary:new.
    self:sharedNames := array:new.
    self:declaredTypes := dictionary:new.
    self:constants2 := dictionary:new.
    self:optionBase := #0.
    self:baseFixed := false.
    self:freshUnit.

    self:readStatements(source).
    self:extractRoutines.
    self:hasPrelude := self:usesPrint.
    ; The runtime's own names have to be known before its source is read, so
    ; that its procedures see globals where they would otherwise make locals --
    ; and so that its arrays are arrays.
    self:hasPrelude:ifTrue({
        preludeGlobals:do({ each |
            self:sharedNames:add(each:at(#1)).
            each:size:equals(#3):ifTrue({
                self:declareArray(each:at(#1), [[#1, each:at(#3)]], true) }) }).
        self:readPrelude }).
    self:analyseByRef.
    self:resolveArrayShapes.

    self:atLine := #1.
    self:mark(#1).
    self:boxesFor(self:statements):do({ n |
        self:boxed:add(n). self:toBox:add(n) }).

    ; Procedures first, so that every name a call needs is bound before the
    ; module's first line runs.
    self:emitRandomGenerator.
    self:hasPrelude:ifTrue({
        preludeGlobals:do({ each |
            each:size:equals(#2):ifElse(
                { self:emitZero(each:at(#2)).
                  self:emitStore(each:at(#1)).
                  self:emitPop },
                { self:emitMakeArray(each:at(#1), [[#1, each:at(#3)]]) }) }) }).
    self:emitStaticInitialisers.
    self:routineOrder:do({ r | self:emitRoutine(r) }).
    self:statementsOfScope := self:statements.
    self:emitVariableInitialisers([]).
    self:emitBoxes.
    self:statements:do({ st | self:emitStatement(st) }).
    self:checkBlocksClosed.

    ; The last instruction of every chunk is a HALT and the verifier requires
    ; it. A label on the line after the last statement is a real thing to
    ; write -- `GOTO Done` where `Done:` is the end of the program -- so the
    ; HALT is where any such label lands, and it is marked before it is emitted.
    self:atLine := self:statements:size:equals(#0):ifElse(
        { #1 }, { self:statements:at(self:statements:size):line:add(#1) }).
    self:mark(self:atLine).
    self:trailingLabels.
    self:needsHalt:ifTrue({ self:emitFinalFlush. self:byte(HALT) }).

    self:chunkOfUnit }.

; **The chunk's last instruction must be a HALT and the verifier requires it**,
; so one is added -- unless the program already ends in `END`, which is that
; instruction, and nothing is waiting for an offset behind it. A trailing label
; is what makes the difference: `GOTO Done` where `Done:` is the last line of
; the program needs somewhere to land, and that somewhere is the HALT.
sola:needsHalt := {
    self:pendingLabels:size:notEquals(#0):or({
        self:statements:size:equals(#0):or({
            self:statements:at(self:statements:size):kind:notEquals('end) }) }) }.

; **A block left open is reported where it was opened, not at the end of the
; file**, because the end of the file is where you already know something is
; wrong and the opening line is the one you have to go and look at.
sola:checkBlocksClosed := { | f |
    self:blocks:size:notEquals(#0):ifTrue({
        f := self:innermost.
        self:atLine := f:line.
        self:fail("this {} is never closed by its {}"
            :fill([self:openerName(f:kind), self:closerName(f:kind)])) }) }.

; A label with no statement after it is a label on the HALT.
sola:trailingLabels := {
    self:pendingLabels:do({ pending |
        self:atLine := pending:at(#2).
        self:labelAt:includes(pending:at(#1)):ifTrue({
            self:fail("the label '{}' is used twice":fill([pending:at(#1)])) }).
        self:labelAt:atPut(pending:at(#1), self:here) }) }.

sola:pendingLabels := nil.

sola:readStatements := { source | | line, st |
    self:pendingLabels := array:new.
    line := #0.
    source:split("\n"):do({ text |
        line := line:add(#1).
        self:parseLine(text, line):do({ st |
            ; A bare label on a line of its own belongs to the next statement
            ; there is, which may be none -- in which case it is the HALT's.
            st:kind:equals('rem):and({ st:label:notNil }):ifElse(
                { self:pendingLabels:add([st:label, line]) },
                { self:pendingLabels:do({ pending |
                      self:statements:add(
                          self:labelOnly(pending:at(#1), pending:at(#2))) }).
                  self:pendingLabels := array:new.
                  self:statements:add(st) }) }) }) }.

; A statement that is nothing but a label, so that the label gets an offset.
sola:labelOnly := { label, line | | st |
    st := stmt:new. st:kind := 'rem. st:label := label. st:line := line. st }.


; ---------------------------------------------------------------------------
; PRINT's rules, written in SolaBasic
;
; **The runtime is written in the language it serves**, compiled by this same
; compiler and emitted into the program that needs it. That is not a flourish:
; `PRINT`'s rules are a line buffer, three loops and a decision about a leading
; nought, and every one of those is easier to read as BASIC than as a sequence
; of `emit` calls -- which is what `SGN` had to be, and what got `SGN` wrong the
; first time.
;
; It costs a reserved prefix. These are ordinary names to the compiler, so a
; listing that wrote `SOLAOUT` would collide with one; four letters are reserved
; in `wordToken` instead of a renaming pass.
;
; **The numbers here are QBasic's and are not all settled.** A print zone is 14
; and the margin is 80; the digits a Double shows come from the machine's own
; shortest round-trip rather than from a count BASIC fixes, and the exponent
; letter is `D` because SolaBasic's only float is a Double. Stage 7 is where
; those get held against a real QuickBASIC -- see SOLABASIC.md.

; The runtime's own variables. They are module-level globals that every one of
; its procedures shares, and the prelude has no module-level lines to declare
; them on -- so the compiler makes them, and puts them where a procedure will
; find them rather than shadow them.
channels := #15.

preludeGlobals := [
    ["SOLABUF$", 'string],  ["SOLACH%", 'integer],
    ["SOLAFMODE%", 'integer, channels],
    ["SOLAFPATH$", 'string, channels],
    ["SOLAFBUF$", 'string, channels],
    ["SOLAFPOS%", 'integer, channels],
    ["SOLAUF$", 'string],   ["SOLAUP%", 'integer],
    ["SOLAUKIND%", 'integer], ["SOLAUEND%", 'integer],
    ["SOLAUINT%", 'integer],  ["SOLAUDEC%", 'integer],
    ["SOLAUCOM%", 'integer],  ["SOLAUFILL$", 'string],
    ["SOLAUDOL%", 'integer],  ["SOLAULEAD%", 'integer],
    ["SOLAUTRL$", 'string],   ["SOLAUEXP%", 'integer],
    ["SOLAUW%", 'integer]].

prelude := "
FUNCTION SOLASIGN$ (T$)
  U$ = T$
  IF LEFT$(U$, 2) = \"0.\" THEN
    U$ = MID$(U$, 2)
  ELSEIF LEFT$(U$, 3) = \"-0.\" THEN
    U$ = \"-\" + MID$(U$, 3)
  END IF
  P% = INSTR(U$, \"e\")
  IF P% > 0 THEN U$ = LEFT$(U$, P% - 1) + \"D\" + MID$(U$, P% + 1)
  IF LEFT$(U$, 1) = \"-\" THEN
    SOLASIGN$ = U$ + \" \"
  ELSE
    SOLASIGN$ = \" \" + U$ + \" \"
  END IF
END FUNCTION

SUB SOLAEOL
  SHARED SOLABUF$, SOLACH%
  IF SOLACH% <> 0 THEN
    SOLAFBUF$(SOLACH%) = SOLAFBUF$(SOLACH%) + CHR$(10)
  ELSE
    SOLAWRITE SOLABUF$
    SOLABUF$ = \"\"
  END IF
END SUB

SUB SOLARAW
  SHARED SOLABUF$
  SOLAWRITERAW SOLABUF$
  SOLABUF$ = \"\"
END SUB

' **A comma inside quotes does not separate**, which is what lets WRITE # and
' INPUT # round-trip a piece of text that has one in it.
FUNCTION SOLACOUNT% (S$)
  DIM N%
  DIM I%
  DIM Q%
  DIM C$
  N% = 1
  Q% = 0
  FOR I% = 1 TO LEN(S$)
    C$ = MID$(S$, I%, 1)
    IF C$ = CHR$(34) THEN Q% = 1 - Q%
    IF C$ = \",\" AND Q% = 0 THEN N% = N% + 1
  NEXT I%
  SOLACOUNT% = N%
END FUNCTION

' The quotes WRITE # puts round a piece of text are not part of it.
FUNCTION SOLAUNQUOTE$ (T$)
  IF LEN(T$) >= 2 THEN
    IF LEFT$(T$, 1) = CHR$(34) AND RIGHT$(T$, 1) = CHR$(34) THEN
      SOLAUNQUOTE$ = MID$(T$, 2, LEN(T$) - 2)
      EXIT FUNCTION
    END IF
  END IF
  SOLAUNQUOTE$ = T$
END FUNCTION

FUNCTION SOLAFIELD$ (S$, WHICH%)
  DIM N%
  DIM I%
  DIM START%
  DIM Q%
  DIM C$
  N% = 1
  START% = 1
  Q% = 0
  FOR I% = 1 TO LEN(S$)
    C$ = MID$(S$, I%, 1)
    IF C$ = CHR$(34) THEN Q% = 1 - Q%
    IF C$ = \",\" AND Q% = 0 THEN
      IF N% = WHICH% THEN
        SOLAFIELD$ = SOLAUNQUOTE$(LTRIM$(RTRIM$(MID$(S$, START%, I% - START%))))
        EXIT FUNCTION
      END IF
      N% = N% + 1
      START% = I% + 1
    END IF
  NEXT I%
  IF N% = WHICH% THEN
    SOLAFIELD$ = SOLAUNQUOTE$(LTRIM$(RTRIM$(MID$(S$, START%, LEN(S$) - START% + 1))))
  END IF
END FUNCTION

FUNCTION SOLANUMOK% (T$)
  DIM I%
  DIM C$
  DIM SEEN%
  DIM DOT%
  DIM EXPO%
  SOLANUMOK% = 0
  IF LEN(T$) = 0 THEN
    SOLANUMOK% = 1
    EXIT FUNCTION
  END IF
  I% = 1
  C$ = MID$(T$, 1, 1)
  IF C$ = \"+\" OR C$ = \"-\" THEN I% = 2
  SEEN% = 0
  DOT% = 0
  EXPO% = 0
  DO WHILE I% <= LEN(T$)
    C$ = MID$(T$, I%, 1)
    IF C$ >= \"0\" AND C$ <= \"9\" THEN
      SEEN% = 1
    ELSEIF C$ = \".\" AND DOT% = 0 AND EXPO% = 0 THEN
      DOT% = 1
    ELSEIF (C$ = \"E\" OR C$ = \"e\" OR C$ = \"D\" OR C$ = \"d\") AND SEEN% = 1 AND EXPO% = 0 THEN
      EXPO% = 1
      SEEN% = 0
      IF I% < LEN(T$) THEN
        C$ = MID$(T$, I% + 1, 1)
        IF C$ = \"+\" OR C$ = \"-\" THEN I% = I% + 1
      END IF
    ELSE
      EXIT FUNCTION
    END IF
    I% = I% + 1
  LOOP
  SOLANUMOK% = SEEN%
END FUNCTION

FUNCTION SOLAVAL# (T$)
  IF LEN(T$) = 0 THEN
    SOLAVAL# = 0
  ELSE
    SOLAVAL# = VAL(T$)
  END IF
END FUNCTION

FUNCTION SOLAASK$ (P$, Q%, SPEC$)
  DIM L$
  DIM OK%
  DIM I%
  DO
    CALL SOLAOUT(P$)
    IF Q% <> 0 THEN CALL SOLAOUT(\"? \")
    CALL SOLARAW
    L$ = SOLAREAD$
    IF L$ = CHR$(0) THEN SOLAFAIL \"Input past end of file\"
    IF SOLAPIPED% <> 0 THEN
      CALL SOLAOUT(L$)
      CALL SOLAEOL
    END IF
    OK% = 1
    IF SOLACOUNT%(L$) <> LEN(SPEC$) THEN OK% = 0
    IF OK% <> 0 THEN
      FOR I% = 1 TO LEN(SPEC$)
        IF MID$(SPEC$, I%, 1) = \"N\" THEN
          IF SOLANUMOK%(SOLAFIELD$(L$, I%)) = 0 THEN OK% = 0
        END IF
      NEXT I%
    END IF
    IF OK% <> 0 THEN EXIT DO
    PRINT \"Redo from start\"
  LOOP
  SOLAASK$ = L$
END FUNCTION

FUNCTION SOLAUINT$ (V#)
  SOLAUINT$ = STR$(V#)
END FUNCTION

FUNCTION SOLAUZERO$ (T$, N%)
  DIM R$
  R$ = T$
  DO WHILE LEN(R$) < N%
    R$ = \"0\" + R$
  LOOP
  SOLAUZERO$ = R$
END FUNCTION

FUNCTION SOLAUPAD$ (T$, N%, FILL$)
  DIM R$
  R$ = T$
  DO WHILE LEN(R$) < N%
    R$ = FILL$ + R$
  LOOP
  SOLAUPAD$ = R$
END FUNCTION

FUNCTION SOLAUCOMMA$ (T$)
  DIM R$
  DIM I%
  DIM N%
  R$ = \"\"
  N% = 0
  FOR I% = LEN(T$) TO 1 STEP -1
    R$ = MID$(T$, I%, 1) + R$
    N% = N% + 1
    IF N% MOD 3 = 0 AND I% > 1 THEN R$ = \",\" + R$
  NEXT I%
  SOLAUCOMMA$ = R$
END FUNCTION

FUNCTION SOLAUABS$ (V#, D%, WANTCOM%)
  DIM A#
  DIM W#
  DIM F#
  DIM SC#
  DIM R$
  A# = ABS(V#)
  SC# = 10# ^ D%
  A# = INT(A# * SC# + .5#) / SC#
  W# = INT(A#)
  R$ = SOLAUINT$(W#)
  IF WANTCOM% <> 0 THEN R$ = SOLAUCOMMA$(R$)
  IF D% > 0 THEN
    F# = INT((A# - W#) * SC# + .5#)
    R$ = R$ + \".\" + SOLAUZERO$(SOLAUINT$(F#), D%)
  END IF
  SOLAUABS$ = R$
END FUNCTION

SUB SOLAUSCAN (P%)
  SHARED SOLAUF$, SOLAUKIND%, SOLAUEND%, SOLAUINT%, SOLAUDEC%
  SHARED SOLAUCOM%, SOLAUFILL$, SOLAUDOL%, SOLAULEAD%, SOLAUTRL$
  SHARED SOLAUEXP%, SOLAUW%
  DIM I%
  DIM J%
  DIM C$
  DIM BS$
  BS$ = CHR$(92)
  SOLAUKIND% = 0
  SOLAUINT% = 0
  SOLAUDEC% = 0
  SOLAUCOM% = 0
  SOLAUFILL$ = \" \"
  SOLAUDOL% = 0
  SOLAULEAD% = 0
  SOLAUTRL$ = \"\"
  SOLAUEXP% = 0
  SOLAUW% = 0
  I% = P%
  SOLAUEND% = I% + 1
  C$ = MID$(SOLAUF$, I%, 1)
  IF C$ = \"!\" THEN
    SOLAUKIND% = 2
    SOLAUW% = 1
    EXIT SUB
  END IF
  IF C$ = \"&\" THEN
    SOLAUKIND% = 2
    SOLAUW% = -1
    EXIT SUB
  END IF
  IF C$ = BS$ THEN
    FOR J% = I% + 1 TO LEN(SOLAUF$)
      IF MID$(SOLAUF$, J%, 1) = BS$ THEN
        SOLAUKIND% = 2
        SOLAUW% = J% - I% + 1
        SOLAUEND% = J% + 1
        EXIT SUB
      END IF
    NEXT J%
    EXIT SUB
  END IF
  IF C$ = \"+\" THEN
    SOLAULEAD% = 1
    SOLAUINT% = 1
    I% = I% + 1
  END IF
  IF MID$(SOLAUF$, I%, 3) = \"**$\" THEN
    SOLAUFILL$ = \"*\"
    SOLAUDOL% = 1
    SOLAUINT% = SOLAUINT% + 3
    I% = I% + 3
  ELSEIF MID$(SOLAUF$, I%, 2) = \"**\" THEN
    SOLAUFILL$ = \"*\"
    SOLAUINT% = SOLAUINT% + 2
    I% = I% + 2
  ELSEIF MID$(SOLAUF$, I%, 2) = \"$$\" THEN
    SOLAUDOL% = 1
    SOLAUINT% = SOLAUINT% + 2
    I% = I% + 2
  END IF
  DO WHILE MID$(SOLAUF$, I%, 1) = \"#\"
    SOLAUINT% = SOLAUINT% + 1
    I% = I% + 1
  LOOP
  IF MID$(SOLAUF$, I%, 1) = \",\" THEN
    SOLAUCOM% = 1
    I% = I% + 1
  END IF
  IF MID$(SOLAUF$, I%, 1) = \".\" THEN
    I% = I% + 1
    DO WHILE MID$(SOLAUF$, I%, 1) = \"#\"
      SOLAUDEC% = SOLAUDEC% + 1
      I% = I% + 1
    LOOP
  END IF
  IF MID$(SOLAUF$, I%, 4) = \"^^^^\" THEN
    SOLAUEXP% = 1
    I% = I% + 4
  END IF
  IF MID$(SOLAUF$, I%, 1) = \"+\" OR MID$(SOLAUF$, I%, 1) = \"-\" THEN
    SOLAUTRL$ = MID$(SOLAUF$, I%, 1)
    I% = I% + 1
  END IF
  IF SOLAUINT% > 0 OR SOLAUDEC% > 0 THEN SOLAUKIND% = 1
  SOLAUEND% = I%
END SUB

FUNCTION SOLAUNUM$ (V#)
  SHARED SOLAUINT%, SOLAUDEC%, SOLAUCOM%, SOLAUFILL$, SOLAUDOL%
  SHARED SOLAULEAD%, SOLAUTRL$, SOLAUEXP%
  DIM B$
  DIM IP$
  DIM FP$
  DIM SG$
  DIM HEAD$
  DIM TAIL$
  DIM X$
  DIM D%
  DIM E%
  DIM M#
  M# = V#
  E% = 0
  IF SOLAUEXP% <> 0 AND M# <> 0 THEN
    DO WHILE ABS(M#) >= 10#
      M# = M# / 10#
      E% = E% + 1
    LOOP
    DO WHILE ABS(M#) < 1#
      M# = M# * 10#
      E% = E% - 1
    LOOP
  END IF
  B$ = SOLAUABS$(M#, SOLAUDEC%, SOLAUCOM%)
  D% = INSTR(B$, \".\")
  IF D% = 0 THEN
    IP$ = B$
    FP$ = \"\"
  ELSE
    IP$ = LEFT$(B$, D% - 1)
    FP$ = MID$(B$, D%)
  END IF
  SG$ = \"\"
  IF SOLAULEAD% <> 0 THEN
    IF M# < 0 THEN
      SG$ = \"-\"
    ELSE
      SG$ = \"+\"
    END IF
  ELSEIF SOLAUTRL$ = \"\" THEN
    IF M# < 0 THEN SG$ = \"-\"
  END IF
  HEAD$ = SG$ + IP$
  IF SOLAUDOL% <> 0 THEN HEAD$ = \"$\" + HEAD$
  TAIL$ = \"\"
  IF SOLAUTRL$ <> \"\" THEN
    IF M# < 0 THEN
      TAIL$ = \"-\"
    ELSEIF SOLAUTRL$ = \"+\" THEN
      TAIL$ = \"+\"
    ELSE
      TAIL$ = \" \"
    END IF
  END IF
  IF SOLAUEXP% <> 0 THEN
    ' D and not E, because SolaBasic's only float is a Double and QuickBASIC
    ' writes a Double's exponent with a D. Plain PRINT already did; this did
    ' not, and the comparison found the two disagreeing with each other.
    IF E% < 0 THEN
      X$ = \"D-\"
    ELSE
      X$ = \"D+\"
    END IF
    TAIL$ = X$ + SOLAUZERO$(SOLAUINT$(ABS(E%)), 2) + TAIL$
  END IF
  IF LEN(HEAD$) > SOLAUINT% THEN
    SOLAUNUM$ = \"%\" + HEAD$ + FP$ + TAIL$
  ELSE
    SOLAUNUM$ = SOLAUPAD$(HEAD$, SOLAUINT%, SOLAUFILL$) + FP$ + TAIL$
  END IF
END FUNCTION

FUNCTION SOLAUSTR$ (S$)
  SHARED SOLAUW%
  DIM R$
  IF SOLAUW% < 0 THEN
    SOLAUSTR$ = S$
  ELSE
    R$ = S$
    DO WHILE LEN(R$) < SOLAUW%
      R$ = R$ + \" \"
    LOOP
    SOLAUSTR$ = LEFT$(R$, SOLAUW%)
  END IF
END FUNCTION

SUB SOLAUSTART (F$)
  SHARED SOLAUF$, SOLAUP%
  SOLAUF$ = F$
  SOLAUP% = 1
END SUB

FUNCTION SOLAUONE$ (V#, S$, ISNUM%)
  SHARED SOLAUF$, SOLAUP%, SOLAUKIND%, SOLAUEND%
  DIM OUT$
  DIM C$
  DIM GUARD%
  OUT$ = \"\"
  GUARD% = 0
  DO
    GUARD% = GUARD% + 1
    IF GUARD% > 500 THEN EXIT DO
    IF SOLAUP% > LEN(SOLAUF$) THEN SOLAUP% = 1
    IF LEN(SOLAUF$) = 0 THEN EXIT DO
    C$ = MID$(SOLAUF$, SOLAUP%, 1)
    IF C$ = \"_\" THEN
      OUT$ = OUT$ + MID$(SOLAUF$, SOLAUP% + 1, 1)
      SOLAUP% = SOLAUP% + 2
    ELSE
      CALL SOLAUSCAN(SOLAUP%)
      IF SOLAUKIND% = 0 THEN
        OUT$ = OUT$ + C$
        SOLAUP% = SOLAUP% + 1
      ELSE
        IF SOLAUKIND% = 1 THEN
          OUT$ = OUT$ + SOLAUNUM$(V#)
        ELSE
          OUT$ = OUT$ + SOLAUSTR$(S$)
        END IF
        SOLAUP% = SOLAUEND%
        EXIT DO
      END IF
    END IF
  LOOP
  SOLAUONE$ = OUT$
END FUNCTION

FUNCTION SOLAUTAIL$
  SHARED SOLAUF$, SOLAUP%, SOLAUKIND%
  DIM OUT$
  DIM C$
  DIM GUARD%
  OUT$ = \"\"
  GUARD% = 0
  DO WHILE SOLAUP% <= LEN(SOLAUF$)
    GUARD% = GUARD% + 1
    IF GUARD% > 500 THEN EXIT DO
    C$ = MID$(SOLAUF$, SOLAUP%, 1)
    IF C$ = \"_\" THEN
      OUT$ = OUT$ + MID$(SOLAUF$, SOLAUP% + 1, 1)
      SOLAUP% = SOLAUP% + 2
    ELSE
      CALL SOLAUSCAN(SOLAUP%)
      IF SOLAUKIND% <> 0 THEN EXIT DO
      OUT$ = OUT$ + C$
      SOLAUP% = SOLAUP% + 1
    END IF
  LOOP
  SOLAUTAIL$ = OUT$
END FUNCTION

FUNCTION SOLAASKLINE$ (P$)
  DIM L$
  CALL SOLAOUT(P$)
  CALL SOLARAW
  L$ = SOLAREAD$
  IF L$ = CHR$(0) THEN SOLAFAIL \"Input past end of file\"
  IF SOLAPIPED% <> 0 THEN
    CALL SOLAOUT(L$)
    CALL SOLAEOL
  END IF
  SOLAASKLINE$ = L$
END FUNCTION

SUB SOLAOUT (T$)
  SHARED SOLABUF$, SOLACH%
  IF SOLACH% <> 0 THEN
    SOLAFBUF$(SOLACH%) = SOLAFBUF$(SOLACH%) + T$
  ELSE
    IF LEN(SOLABUF$) > 0 THEN
      IF LEN(SOLABUF$) + LEN(T$) > 80 THEN CALL SOLAEOL
    END IF
    SOLABUF$ = SOLABUF$ + T$
  END IF
END SUB

' ---------------------------------------------------------------------------
' Channels
'
' A channel open for reading holds the whole file and a position in it; one open
' for writing holds what has been written and puts it out when it is closed.
' There is no streaming underneath, so there is none here.

SUB SOLAOPEN (N%, PATH$, MODE%)
  IF N% < 1 OR N% > 15 THEN SOLAFAIL \"Bad file number\"
  IF SOLAFMODE%(N%) <> 0 THEN SOLAFAIL \"File already open\"
  SOLAFMODE%(N%) = MODE%
  SOLAFPATH$(N%) = PATH$
  SOLAFPOS%(N%) = 1
  IF MODE% = 1 THEN
    IF SOLAEXISTS%(PATH$) = 0 THEN SOLAFAIL \"File not found\"
    SOLAFBUF$(N%) = SOLAREADFILE$(PATH$)
  ELSE
    SOLAFBUF$(N%) = \"\"
  END IF
END SUB

SUB SOLACLOSE (N%)
  IF N% < 1 OR N% > 15 THEN SOLAFAIL \"Bad file number\"
  IF SOLAFMODE%(N%) = 2 THEN
    SOLAWRITEFILE SOLAFPATH$(N%), SOLAFBUF$(N%)
  END IF
  IF SOLAFMODE%(N%) = 3 THEN
    SOLAAPPENDFILE SOLAFPATH$(N%), SOLAFBUF$(N%)
  END IF
  SOLAFMODE%(N%) = 0
  SOLAFBUF$(N%) = \"\"
END SUB

SUB SOLACLOSEALL
  DIM I%
  FOR I% = 1 TO 15
    IF SOLAFMODE%(I%) <> 0 THEN CALL SOLACLOSE(I%)
  NEXT I%
END SUB

FUNCTION SOLAFEOF% (N%)
  IF SOLAFPOS%(N%) > LEN(SOLAFBUF$(N%)) THEN
    SOLAFEOF% = -1
  ELSE
    SOLAFEOF% = 0
  END IF
END FUNCTION

FUNCTION SOLAFLINE$ (N%)
  DIM P%
  DIM E%
  DIM R$
  IF SOLAFMODE%(N%) <> 1 THEN SOLAFAIL \"File not open for reading\"
  P% = SOLAFPOS%(N%)
  IF P% > LEN(SOLAFBUF$(N%)) THEN SOLAFAIL \"Input past end of file\"
  E% = INSTR(P%, SOLAFBUF$(N%), CHR$(10))
  IF E% = 0 THEN
    R$ = MID$(SOLAFBUF$(N%), P%)
    SOLAFPOS%(N%) = LEN(SOLAFBUF$(N%)) + 1
  ELSE
    R$ = MID$(SOLAFBUF$(N%), P%, E% - P%)
    SOLAFPOS%(N%) = E% + 1
  END IF
  IF RIGHT$(R$, 1) = CHR$(13) THEN R$ = LEFT$(R$, LEN(R$) - 1)
  SOLAFLINE$ = R$
END FUNCTION

SUB SOLAPAD (N%)
  SHARED SOLABUF$
  DO WHILE LEN(SOLABUF$) < N%
    SOLABUF$ = SOLABUF$ + \" \"
  LOOP
END SUB

SUB SOLAZONE
  SHARED SOLABUF$
  IF LEN(SOLABUF$) >= 70 THEN
    CALL SOLAEOL
  ELSE
    DO
      SOLABUF$ = SOLABUF$ + \" \"
    LOOP UNTIL LEN(SOLABUF$) MOD 14 = 0
  END IF
END SUB

SUB SOLATAB (N%)
  SHARED SOLABUF$
  M% = N%
  IF M% < 1 THEN M% = 1
  IF LEN(SOLABUF$) > M% - 1 THEN CALL SOLAEOL
  CALL SOLAPAD(M% - 1)
END SUB

SUB SOLASPC (N%)
  SHARED SOLABUF$
  IF N% > 0 THEN CALL SOLAPAD(LEN(SOLABUF$) + N%)
END SUB
".

; The runtime is read in only when the listing prints, so a program that never
; does carries none of it.
sola:usesPrint := { | found |
    found := false.
    self:statements:do({ st |
        self:printsIn(st):ifTrue({ found := true }) }).
    self:routineOrder:do({ r |
        r:body:do({ st | self:printsIn(st):ifTrue({ found := true }) }) }).
    found }.

sola:printsIn := { st | | found |
    st:kind:equals('group):ifElse({
        found := false.
        st:body:do({ each | self:printsIn(each):ifTrue({ found := true }) }).
        found }, {
    ['print, 'input, 'lineinput, 'open, 'close, 'write]:indexOf(st:kind):notNil
        :or({ st:then:notNil:and({ self:printsIn(st:then) }) })
        :or({ st:otherwise:notNil:and({ self:printsIn(st:otherwise) }) }) }) }.

sola:readPrelude := { | saved |
    saved := self:statements.
    self:statements := array:new.
    self:inPrelude := true.
    self:readStatements(prelude).
    self:extractRoutines.
    self:inPrelude := false.
    self:statements := saved }.

; ---------------------------------------------------------------------------
; The command line

demo := "' Stage 2's structure and stage 3's jumps, in one program. The GOTO\n"
    :concat("' leaves a block and lands just before NEXT, which is how BASIC\n")
    :concat("' spells what a later language calls `continue`.\n")
    :concat("total = 0\n")
    :concat("FOR i = 1 TO 10\n")
    :concat("  IF i = 7 THEN GOTO Skip\n")
    :concat("  SELECT CASE i\n")
    :concat("  CASE 1, 2, 3\n")
    :concat("    PRINT i; \" small\"\n")
    :concat("  CASE 4 TO 6\n")
    :concat("    PRINT i; \" middle\"\n")
    :concat("  CASE IS >= 9\n")
    :concat("    PRINT i; \" large\"\n")
    :concat("  CASE ELSE\n")
    :concat("    PRINT i; \" none of those\"\n")
    :concat("  END SELECT\n")
    :concat("  total = total + i\n")
    :concat("Skip:\n")
    :concat("NEXT i\n")
    :concat("PRINT \"total \"; total\n")
    :concat("k = 0\n")
    :concat("DO\n")
    :concat("  k = k + 1\n")
    :concat("  IF k = 3 THEN EXIT DO\n")
    :concat("LOOP\n")
    :concat("PRINT \"left the DO at \"; k\n")
    :concat("FUNCTION Triangle (n)\n")
    :concat("  IF n <= 1 THEN\n")
    :concat("    Triangle = 1\n")
    :concat("  ELSE\n")
    :concat("    Triangle = n + Triangle(n - 1)\n")
    :concat("  END IF\n")
    :concat("END FUNCTION\n")
    :concat("PRINT \"the tenth triangular number is \"; Triangle(10)\n")
    :concat("END\n").

source := nil.
inPath := "demo.bas".
outPath := "build/sola/demo.sob".

system:arguments:size:equals(#0):ifElse(
    { source := demo },
    { inPath := system:arguments:at(#1).
      source := system:readFile(inPath).
      source:isNil:ifTrue({ error:raise("cannot read {}":fill([inPath])) }).
      outPath := system:arguments:size:greaterOrEqual(#2):ifElse(
          { system:arguments:at(#2) },
          { inPath:concat(".sob") }) }).

system:arguments:size:equals(#0):ifTrue({
    system:isDirectory("build/sola"):ifFalse({
        system:isDirectory("build"):ifFalse({ system:makeDirectory("build") }).
        system:makeDirectory("build/sola") }).
    "":display.
    "compiling the demonstration, which is:":display.
    "":display.
    demo:display }).

bytes := sob:file(sola:compile(source, inPath)).
system:writeFile(outPath, bytes).

"":display.
"{} -> {}, {} bytes":fill([inPath, outPath, bytes:size:asString]):display.
"":display.
"run it:  ./bin/solvm {}":fill([outPath]):display.
"see it:  ./bin/solvm --dump {}":fill([outPath]):display.
"":display.
