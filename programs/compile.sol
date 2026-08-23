; compile.sol -- the compiler with a command line on it.
;
; Run with:  ./bin/solas programs/compile.sol && ./bin/solvm programs/compile.sob
; A file:    ./bin/solvm programs/compile.sob examples/hello.sol -o hello.sob
; Elsewhere: ./bin/solvm programs/compile.sob prog.sol -I some/lib
;
; The twelfth program. Everything it does is in
; [lib/compiler.sol](../lib/compiler.sol) and the three libraries under it; this
; is the argument handling, the search path, and writing the file -- which is
; all a compiler's front door ever is.
;
; **It compiles 42 of this repository's 46 `.sol` files to bytes identical to
; what `solas` produces.** The four it cannot are not a construct it lacks:
; they nest deeper than the parser has frames for. See
; [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-62-levels).

@include "compiler.sol".

; ---------------------------------------------------------------------------
; What was asked for
;
; `compile <source.sol> [-o <out.sob>]`, and with nothing at all it compiles the
; example it was written for, which is the convention every program here
; follows.

given := system:arguments.
given:size:equals(#0):ifTrue({
    "":display.
    "no file given, so: examples/hello.sol":display.
    given := ["examples/hello.sol"] }).

source := given:at(#1).
output := nil.

; **The search path has to be given**, where `solas` works its default out from
; where its own binary sits -- `bin/../lib`. A Solum program cannot see the path
; it was started with, so `-I` says it, and `lib` is the default because that is
; where this repository keeps its library. Compiling from another directory
; means saying so.
compiler:search := ["lib"].
given:indexOf("-I"):isNil:ifFalse({
    compiler:search := [].
    #1:toDo(given:size, { i |
        given:at(i):equals("-I"):and({ i:lessThan(given:size) }):ifTrue({
            compiler:search := compiler:search:add(given:at(i:inc)) }) }) }).
given:indexOf("-o"):isNil:ifElse(
    { output := source:copyFrom(#1, source:size:sub(#4)):concat(".sob") },
    { output := given:at(given:indexOf("-o"):inc) }).

source:size:greaterThan(#4)
    :and({ source:copyFrom(source:size:sub(#3), source:size):equals(".sol") })
    :ifFalse({
        "not a .sol file: {}":fill([source]):display.
        system:exit(#1) }).

system:fileExists(source):ifFalse({
    "no such file: {}":fill([source]):display.
    system:exit(#1) }).

; The path goes into the file's own table, so it is what a stack trace will name
; -- and it has to be spelled the way the compiler being compared against was
; given it, or the bytes differ over nothing else.
text := sob:file(compiler:compile(system:readFile(source), source)).
system:writeFile(output, text).

"":display.
"{}  ->  {}  ({} bytes)":fill([source, output, text:size]):display.
"":display.
