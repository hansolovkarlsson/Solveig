; manifest.sol -- read a JSON file, describe it, query it, write it back.
;
; Run with:  ./bin/solas examples/manifest.sol && ./bin/solvm examples/manifest.sob
; Over a file of your own:  ./bin/solvm examples/manifest.sob path/to/file.json
; With a path to pull out:  ./bin/solvm examples/manifest.sob file.json server.port
;
; It is called manifest.sol and not json.sol because a file that includes a
; library of its own name finds *itself* on the search path first, and, a file
; being compiled once, that include quietly does nothing. The reference warns
; about this and calls it occasionally a trap; it took about a minute to fall
; into, and what it costs is that the program compiles cleanly and then fails at
; run time with `undefined name 'json'`. See ROADMAP 6.18.
;
; The parser itself is [lib/json.sol](../lib/json.sol) and is on the search
; path, so this says `@include "json.sol".` and does not say where it lives.
; Splitting it that way was the point: a JSON reader is library code, and the
; program above it is the thing that finds out whether the library is any good.
;
; The third program here written to do a job rather than to show a feature.
; log.sol reads lines and tallies them; evaluator.sol parses one expression and
; folds it to a number; this one reads a *tree* and has to walk, query and
; rebuild it without knowing its shape in advance. That is the ground the other
; two never touched, and it is where the findings below came from.
;
; Three things it found, in the order they bit:
;
;   1. A recursive-descent parser spends the frame budget several times over per
;      level of the document. 62 frames (ROADMAP 3.5) is 28 levels of JSON --
;      and 18 if the value dispatch goes through a dictionary of blocks. The
;      limit is not felt as "62 recursions"; it is felt as a document that is
;      too deep, which is a different and much smaller number.
;   2. A character has no number (ROADMAP 6.12), so `A` needs the alphabet
;      written down as a literal to look "A" up in, and `é` cannot be read
;      at all. UTF-8 in the text itself passes through perfectly, because a
;      string is bytes -- so the format's *escape* is the only part that fails.
;   3. `null` and a missing name both arrive as nil, so `at(name, nil)` cannot
;      tell them apart and `includes` has to be asked. Every other format this
;      language has met so far draws no such line, and it was invisible until
;      one did.

@include "json.sol".

; ---------------------------------------------------------------------------
; Where the document comes from

sample := "{
  \"name\": \"solveig\",
  \"version\": \"0.3.0\",
  \"server\": { \"host\": \"localhost\", \"port\": 8080, \"tls\": false },
  \"limits\": { \"frames\": 64, \"depth\": null },
  \"tags\": [\"small\", \"c11\", \"no-dependencies\"],
  \"builds\": [
    { \"target\": \"solas\", \"ok\": true,  \"seconds\": 1.4 },
    { \"target\": \"solvm\", \"ok\": true,  \"seconds\": 2.1 },
    { \"target\": \"solis\", \"ok\": false, \"seconds\": 0.9 }
  ]
}".

path := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1) },
    { | fallback |
      fallback := "build/example.json".
      system:writeFile(fallback, sample).
      fallback }).

system:fileExists(path):ifFalse({
    "no such file: {}":fill([path]):display.
    system:exit(#1) }).

; A parse error is the normal way for this program to end, not an exception to
; it, so it is caught and reported rather than left to the VM. The library says
; what went wrong and where in the text; only this level knows the file name.
doc := { json:read(system:readFile(path)) }:onError({ e |
    "{}: {}":fill([path, e:message]):display.
    system:exit(#1) }).

; ---------------------------------------------------------------------------
; Describing it
;
; Walking a tree whose shape is not known in advance is the one thing a
; dictionary and an array have to be told apart for. `isKindOf` is the whole
; test, and the order matters only in that nil has to be asked about first --
; it answers `isKindOf(object)` like everything else does.

kinds := dictionary:new.
deepest := #0.

kindOf := { v |
    v:isNil:ifElse({ 'null }, {
    v:isKindOf(dictionary):ifElse({ 'object }, {
    v:isKindOf(array):ifElse({ 'array }, {
    v:isKindOf(string):ifElse({ 'string }, {
    v:isKindOf(boolean):ifElse({ 'boolean }, {
    v:isKindOf(integer):ifElse({ 'integer }, { 'float }) }) }) }) }) }) }.

walk := { v, level |
    kinds:atPut(kindOf:value(v), kinds:at(kindOf:value(v), #0):add(#1)).
    level:greaterThan(deepest):ifTrue({ deepest := level }).
    v:isKindOf(dictionary):ifTrue({
        v:do({ each | walk:value(each, level:add(#1)) }) }).
    v:isKindOf(array):ifTrue({
        v:do({ each | walk:value(each, level:add(#1)) }) }) }.

walk:value(doc, #1).

"":display.
"{} -- {} bytes":fill([path, system:fileSize(path)]):display.
"{} values, nested {} deep":fill([
    kinds:values:inject(#0, { total, n | total:add(n) }), deepest]):display.
; Sorted on the text rather than on the keys, because a symbol has no
; `lessThan`. Symbols are values and compare by content, so they make good
; dictionary keys; ordering them is a different question and the answer today is
; that you cannot. Converting to strings to sort, and back to look up, is the
; whole of the workaround -- see ROADMAP 6.19.
kinds:keys:collect({ k | k:asString }):sorted:do({ name |
    "  {} {}":fill([kinds:at(name:asSymbol):asString("4"), name]):display }).

; ---------------------------------------------------------------------------
; Pulling one thing out
;
; A dotted path is how every tool that reads JSON on a command line addresses
; one value, and it is `split` plus a fold. `inject` carries the value found so
; far, which is exactly the shape of walking down a path -- the accumulator and
; the element are different types, which a fold is allowed to do.

lookup := { root, dotted |
    dotted:split("."):inject(root, { here, step |
        here:isNil:ifElse({ nil }, {
        here:isKindOf(dictionary):ifElse(
            { here:at(step, nil) },
            { here:isKindOf(array):ifElse(
                { | n |
                  n := { step:asInteger }:onError({ nil }).
                  n:isNil:or({ n:lessThan(#1) }):or({ n:greaterThan(here:size) })
                      :ifElse({ nil }, { here:at(n) }) },
                { nil }) }) }) }) }.

system:arguments:size:greaterThan(#1):ifTrue({ | wanted, found |
    wanted := system:arguments:at(#2).
    found := lookup:value(doc, wanted).
    "":display.
    ; nil here means "no such path" *or* "the path is there and holds null",
    ; and the only way to tell is to ask again. A tool that reported "not found"
    ; for a name whose value is null would be wrong in the one case the format
    ; went to the trouble of expressing.
    found:isNil:ifElse(
        { "{}: nothing there, or null":fill([wanted]):display },
        { "{}: {}":fill([wanted, found:asJson]):display }).
    system:exit(#0) }).

; ---------------------------------------------------------------------------
; Changing it and writing it back
;
; A read document is ordinary dictionaries and arrays, so editing it needs
; nothing the language did not already have.

failed := doc:at("builds"):select({ b | b:at("ok"):not }).
doc:atPut("failures", failed:collect({ b | b:at("target") })).
doc:at("server"):atPut("port", #9090).

out := "build/example-out.json".
system:writeFile(out, json:write(doc)).

"":display.
"{} builds, {} failed":fill([
    doc:at("builds"):size, failed:size]):display.
"rewritten to {} ({} bytes)":fill([out, system:fileSize(out)]):display.

; The proof that the two halves agree: read back what was just written, write it
; again, and compare the text. Sorted names and a fixed number spelling are what
; make that hold -- without them the same document would write two ways.
again := json:read(system:readFile(out)).
"reads back identical: {}":fill([
    again:asJson:equals(doc:asJson)]):display.
