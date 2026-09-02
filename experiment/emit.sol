; emit.sol -- a .sob written by Solum, which is disasm.sol backwards.
;
; Run with:  ./bin/solas programs/emit.sol && ./bin/solvm programs/emit.sob
; Somewhere else:  ./bin/solvm programs/emit.sob build/emit
;
; The eleventh program, and the first stage of asking whether **Solas could be
; written in Solum** -- see
; [ideas.md](../docs/ideas.md#solas-written-in-solum--self-hosting). Not a
; compiler. There is no lexer here and no parser: two chunks are written out by
; hand, byte by byte, and handed to the machine.
;
; **That is the whole point of doing this first.** A compiler is a front end and
; a back end, and the front end is ordinary work in any language -- scanning
; characters and building a tree is what `lib/json.sol` and `lib/html.sol`
; already do. The back end is the half that could turn out to be impossible,
; because it has to produce an exact binary file, and a language that cannot
; write a NUL byte or an i64 cannot do it at all. So the back end goes first,
; on the smallest input there is, and either it works or the question is
; answered cheaply.
;
; What it produces is compared against what `solas` produces from the same two
; programs, byte for byte. Not "runs the same" -- the same file.
;
;   "hi":display.     94 bytes    names, code, line runs, files, slot names
;   #45:print.        98 bytes    all of that and the constant table
;
; Between them they exercise every section of the format that a chunk with no
; methods has.

; ---------------------------------------------------------------------------
; The bytes
;
; All of it moved to [sob.sol](../lib/sob.sol) once a second program wanted it:
; this one, which builds chunks by hand, and
; [compile.sol](compile.sol), which builds them from source. What is left here
; is the chunks themselves, which is what this program is about.

@include "sob.sol".

; ---------------------------------------------------------------------------
; The instructions
;
; The opcode numbers are the order of the enum in
; solum/include/solum/bytecode.h, which is the one thing about the format a
; reader cannot look up -- BYTECODE.md describes every instruction and gives no
; byte for any of them, which is ROADMAP 6.x territory and was found by
; disasm.sol. Only the four this program needs are named.

CONST  := #0.
STRING := #9.
SEND   := #11.
POP    := #18.
HALT   := #20.

; A u16 operand inside the code, little-endian since version 14 -- before that
; the tables were little-endian and these were big, which is the whole reason
; there was a version 14.
operand := { n | [n:bitAnd(#255), n:shiftRight(#8):bitAnd(#255)] }.

; ---------------------------------------------------------------------------
; The two programs, by hand
;
; Each is what `solas` produces for one line of Solum. The line numbers are the
; interesting part of the shape: the statement is line 1 and the HALT the
; compiler adds is line 2, which is one past the end of a one-line file.

; "hi":display.
hello := dictionary:new.
hello:atPut("slots", #1).
hello:atPut("names", ["hi", "display"]).
hello:atPut("constants", []).
hello:atPut("code",
    [STRING]:add(operand:value(#0):at(#1)):add(operand:value(#0):at(#2))
        :add(SEND):add(operand:value(#1):at(#1)):add(operand:value(#1):at(#2)):add(#0)
        :add(POP)
        :add(HALT)).
hello:atPut("lines", [[#8, #1], [#1, #2]]).
hello:atPut("files", ["hi.sol"]).
hello:atPut("fileRuns", [[#9, #0]]).
hello:atPut("slotNames", [""]).
hello:atPut("methods", []).

; #45:print.
number := dictionary:new.
number:atPut("slots", #1).
number:atPut("names", ["print"]).
number:atPut("constants", [[#1, #45]]).
number:atPut("code",
    [CONST]:add(operand:value(#0):at(#1)):add(operand:value(#0):at(#2))
        :add(SEND):add(operand:value(#0):at(#1)):add(operand:value(#0):at(#2)):add(#0)
        :add(POP)
        :add(HALT)).
number:atPut("lines", [[#8, #1], [#1, #2]]).
number:atPut("files", ["num.sol"]).
number:atPut("fileRuns", [[#9, #0]]).
number:atPut("slotNames", [""]).
number:atPut("methods", []).

; ---------------------------------------------------------------------------
; Writing them

; **The directory is made if it is not there**, because a program that fails on
; a clean checkout because a build directory is missing is a program nobody can
; run twice.
where := system:arguments:size:equals(#0):ifElse(
    { "build/emit" },
    { system:arguments:at(#1) }).

system:isDirectory(where):ifFalse({ system:makeDirectory(where) }).

"":display.
"writing into {}":fill([where]):display.

[[hello, "hi.sob", "hi.sol"], [number, "num.sob", "num.sol"]]:do({ job |
    | path, text |
    path := where:concat("/"):concat(job:at(#2)).
    text := sob:file(job:at(#1)).
    system:writeFile(path, text).
    "  {}  {} bytes":fill([job:at(#2), text:size:asString("4")]):display }).

"":display.
"check them against the compiler:":display.
"  printf '\"hi\":display.\\n' > hi.sol && ./bin/solas hi.sol":display.
"  cmp hi.sob {}/hi.sob":fill([where]):display.
"  ./bin/solvm {}/hi.sob":fill([where]):display.
"":display.
