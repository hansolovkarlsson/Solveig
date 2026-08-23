; expect.sol -- check that what is written down is true.
;
; Run with:  ./bin/solas programs/expect.sol && ./bin/solvm programs/expect.sob
; Over the documentation:  ./bin/solvm programs/expect.sob docs
; A directory or one file:  ./bin/solvm programs/expect.sob docs/GUIDE.md
;
; Two subjects, one job. `examples/` carries about four hundred claims in
; comments; `docs/` carries two hundred more inside ``` fences, in the same
; notation. Nothing checked either until this existed, and both are read far
; more than anything else here.
;
; The ninth program here, and the one with the narrowest customer: this
; repository. The job is real all the same. `examples/` carries 276 inline
; expectations --
;
;     #2:add(#3):print.                ; #5
;     "abc":asUppercase:display.       ; ABC
;
; -- and until this existed nothing checked a single one of them. The test suite
; compiles every example and never runs one. So those comments were held true by
; somebody having looked, once, at the time, which is the same standing the
; `.sob` format table had when [disasm.sol](disasm.sol) found it three sections
; out of date.
;
; They are also the first thing a newcomer reads, which makes them the
; documentation with the widest audience and the least checking.
;
; ---------------------------------------------------------------------------
; What counts as an expectation, and why the rule is narrow
;
; A line qualifies when it has live code that prints, and a comment after it:
;
;     b:at(#1):print.              ; #7 -- the change is visible through b
;     ^ code, and it prints        ^ the expectation, up to the prose
;
; That excludes a commented-out demonstration -- the ones showing what an error
; looks like, which begin with `;` and never run -- and it excludes prose
; comments on lines that print nothing. The rule is deliberately narrow: a
; checker that guesses is worse than one that says what it did not check, so
; every line it declined to read is counted and reported.
;
; ---------------------------------------------------------------------------
; How the comparison works, and what it will not catch
;
; **In order, as a subsequence.** Each expectation must appear in the output,
; and after the one before it. Not line-for-line, because one statement can
; print many lines -- a `do:` over an array, a loop -- and demanding equal
; counts would fail every file that has one.
;
; The cost is that an expectation can be satisfied by a later line that happens
; to match. In a file where every other value is `true` that is not
; hypothetical, so the report says how far apart the match was found when it was
; not the next line.

; Several subjects at once, because there are three: the examples, the
; documents, and the two pages at the root that belong to neither.
subjects := system:arguments:size:equals(#0):ifElse(
    { ["examples"] },
    { system:arguments }).

; ---------------------------------------------------------------------------
; Reading the expectations out of a source file
;
; The comment character has to be found outside a string, because a program
; about text has string literals with semicolons in them. Tracking the quotes is
; four lines and guessing is a bug that would only show up in the file it was
; least convenient to be wrong about.

string:commentAt := { | i, inString, c, found |
    i := #1. inString := false. found := nil.
    { found:isNil:and({ i:lessOrEqual(self:size) }) }:whileTrue({
        c := self:at(i).
        inString:ifElse(
            { c:equals("\\"):ifElse(
                { i := i:add(#1) },
                { c:equals("\""):ifTrue({ inString := false }) }) },
            { c:equals("\""):ifTrue({ inString := true }).
              c:equals(";"):ifTrue({ found := i }) }).
        i := i:add(#1) }).
    found }.

; The value a comment claims, with any aside after ` -- ` taken off. That is one
; of three conventions the examples turned out to use, and the checker had to
; learn all three rather than declare the other two wrong:
;
;     ; #5                       the value alone
;     ; #7 -- and why           an aside after a dash
;     ; #8 distinct words       an aside with no dash at all
;
; The third is why matching is by prefix below rather than by equality. Reading
; them as errors would have been the checker insisting on a convention the
; examples never agreed to.
; And a comment that *opens* with `--` is an aside in full, claiming nothing.
; Three lines in examples/ print something no comment could pin down -- a
; timestamp, a duration at the clock's floor, and one describing what happened
; rather than what appeared -- and marking them is better than either dropping
; the check or leaving three permanent failures for a reader to learn to ignore.
string:claimIn := { | cut, text |
    text := self:trim.
    text:size:greaterOrEqual(#2):and({ text:copyFrom(#1, #2):equals("--") })
        :ifTrue({ text := "" }).
    cut := text:indexOf(" -- ").
    (cut:isNil:ifElse({ text }, { text:copyFrom(#1, cut:sub(#1)) })):trim }.

; Does `line` satisfy `claim`? Equal, or the claim is that line followed by
; prose -- which is the third convention above, and the space or comma is what
; keeps `#1` from satisfying a claim of `#12`.
satisfies := { line, claim |
    line:equals("") :ifElse(
        { false },
        { claim:equals(line):or({
              claim:size:greaterThan(line:size):and({
                  claim:copyFrom(#1, line:size):equals(line) }):and({
                  " ,.":indexOf(claim:at(line:size:add(#1))):notNil }) }) }) }.

expectationsIn := { source | | out, cut, code, claim |
    out := array:new.
    source:split("\n"):do({ text |
        cut := text:commentAt.
        cut:notNil:ifTrue({
            code := text:copyFrom(#1, cut:sub(#1)).
            claim := text:copyFrom(cut:add(#1), text:size):claimIn.
            code:indexOf(":print"):notNil:or({ code:indexOf(":display"):notNil })
                :and({ claim:notEquals("") })
                :ifTrue({ out:add(claim) }) }) }).
    out }.

; Lines that print and say nothing about it, which is what the report counts as
; unchecked rather than passing over.
silentPrintsIn := { source | | count, cut, code |
    count := #0.
    source:split("\n"):do({ text |
        cut := text:commentAt.
        code := cut:isNil:ifElse({ text }, { text:copyFrom(#1, cut:sub(#1)) }).
        code:indexOf(":print"):notNil:or({ code:indexOf(":display"):notNil })
            :and({ cut:isNil:or({
                text:copyFrom(cut:add(#1), text:size):claimIn:equals("") }) })
            :ifTrue({ count := count:add(#1) }) }).
    count }.

; ---------------------------------------------------------------------------
; Fenced blocks, for the documentation
;
; The guide and the reference make the same kind of claim the examples do, in
; the same notation, inside ``` fences -- and until this nothing checked one of
; those either. They are the two documents a newcomer actually reads.
;
; Three things differ from a .sol file.
;
;   1. **A block is its own program.** Almost all of them turn out to be
;      self-contained: 78 of the 80 that carry a claim compile on their own,
;      which says something good about how the documents were written.
;
;   2. **A claim may sit on a line that prints nothing.** `#4:timesCollect({...})
;      ; [#1, #4, #9, #16]` describes the *answer*, not output. The rule from
;      the examples -- the line must print -- excludes those, correctly, and
;      they are counted as unchecked rather than guessed at.
;
;   3. **A block may show an error.** The two that do not compile are not
;      broken; they carry the message inline as if it were code:
;
;          #2:add(1.5).
;          solvm: 'add' expects integer, got float (no implicit coercion)
;
;      Those lines are output, not program. They are the most valuable thing
;      here to check, because error wording drifts more than anything else in
;      the documents, and nothing has ever checked one.

string:isDocumentedOutput := { | t |
    t := self:trim.
    t:indexOf("solvm:"):equals(#1)
        :or({ t:indexOf("solas:"):equals(#1) })
        :or({ t:indexOf("solis:"):equals(#1) }) }.

; Did the run fail in a way the block did not say it would? An error nobody
; documented means the block needed something it did not carry.
failed := { output, documented | | bad |
    bad := false.
    output:do({ line |
        line:isDocumentedOutput:and({ documented:indexOf(line:trim):isNil })
            :ifTrue({ bad := true }) }).
    bad }.

; The lines between a pair of ``` fences, each with the line it started on.
blocksIn := { source | | out, n, inBlock, cur, start |
    out := array:new. n := #0. inBlock := false. cur := array:new. start := #0.
    source:split("\n"):do({ line |
        n := n:add(#1).
        line:size:greaterOrEqual(#3):and({ line:copyFrom(#1, #3):equals("```") })
            :ifElse(
                { inBlock:ifElse(
                    { out:add([start, cur]). cur := array:new. inBlock := false },
                    { inBlock := true. start := n }) },
                { inBlock:ifTrue({ cur:add(line) }) }) }).
    out }.

; A block splits at its first documented output: everything before is the
; program that produces it, and everything after is not reached, because the
; error stopped the run. Reported rather than guessed at.
;
; Answers [codeText, expectedOutputs, linesNotReached].
; Answers [codeText, expectedOutputs, linesNotReached].
;
; Only the **first** run of output lines is reachable. A page that shows four
; refusals in one block --
;
;     symbol:new.
;     solvm: a symbol is written 'name, or made from a string with asSymbol
;     block:new.
;     solvm: a block is written { ... } and compiled
;
; -- documents four errors and produces one, because the first stops the
; program. Checking the rest would be asking a run to do what no run does.
splitBlock := { lines | | code, outputs, unreached, seen, past |
    code := array:new. outputs := array:new.
    unreached := #0. seen := false. past := false.
    lines:do({ line |
        line:isDocumentedOutput:ifElse(
            { past:ifElse(
                { unreached := unreached:add(#1) },
                { seen := true. outputs:add(line:trim) }) },
            { seen:ifElse(
                { past := true.
                  line:trim:equals(""):ifFalse({
                      unreached := unreached:add(#1) }) },
                { code:add(line) }) }) }).
    [code:join("\n"):concat("\n"), outputs, unreached] }.

; ---------------------------------------------------------------------------
; Running one

failures := array:new.
stopped := #0.
checked := #0.
unchecked := #0.
files := #0.
blocks := #0.
standalone := #0.
notReached := #0.

; Writes `source`, compiles it, runs it, and answers its output as lines --
; or nil when it would not compile, which the caller reports.
;
; `mergeErrors` is for the documentation, where a block may show the error a
; statement makes and that message is the thing worth checking. The examples
; keep stdout alone, so that a complaint on stderr cannot accidentally satisfy
; a claim about what was printed.
; Compiles `sol` and runs it. The .sol file is compiled **where it lies**,
; because `@include` looks beside the including file first -- moving
; examples/include.sol to build/ and compiling it there loses library.sol, which
; is how this was found.
sandbox := "build/expect-run".

runFile := { sol, tag, mergeErrors, sandboxed | | sob, result, where |
    sob := "build/expect-":concat(tag):concat(".sob").

    system:run(["./bin/solas", sol, "-o", sob]):equals(#0):ifElse(
        { ; **Run somewhere it cannot do any harm.** This executes
          ; documentation, and documentation shows how to delete things:
          ; `system:run(["rm", name])`, `system:remove("build")`,
          ; `system:writeFile("notes.txt", ...)`. Most of those blocks name
          ; something undefined and fail before they reach the filesystem, but
          ; not all -- the writeFile one has literal arguments and put a file
          ; back into the repository that a commit had deliberately deleted,
          ; which is how this was noticed.
          ;
          ; So the run happens in a scratch directory. Anything a block writes
          ; by a relative name lands there, and anything it deletes was already
          ; disposable. Compiling still happens from the root, which is what
          ; `@include` needs to find the shipped library.
          ;
          ; Standard input comes from nowhere too, because the reference
          ; documents `readLine` and a block that calls one would otherwise wait
          ; for a person who is not there. That one hung.
          ; A shipped example is **not** sandboxed: those run from the repository
          ; root by the project's own convention -- walk.sol defaults its root to
          ; `examples` and time.sol stamps `examples/time.sol`, and both stop
          ; working anywhere else. Only a block from a document, which belongs to
          ; nowhere, is moved.
          sandboxed:ifTrue({
              system:isDirectory(sandbox):ifFalse({
                  system:makeDirectory(sandbox) }) }).
          where := sandboxed:ifElse(
              { "cd ":concat(sandbox):concat(" && ../../bin/solvm ../../") },
              { "./bin/solvm " }).
          result := system:capture(["/bin/sh", "-c",
              where:concat(sob)
                   :concat(mergeErrors:ifElse(
                       { " 2>&1" }, { " 2>/dev/null" }))
                   :concat(" < /dev/null")]).
          result:at("status"):equals(#0):ifFalse({ stopped := stopped:add(#1) }).
          result:at("output"):split("\n") },
        { nil }) }.

; The same for source that has no file of its own -- a fenced block. It goes to
; build/, which is right for it: a block in the documentation includes by name
; from the search path, never from beside a file it does not have.
runSource := { source, tag, mergeErrors | | sol |
    sol := "build/expect-":concat(tag):concat(".sol").
    system:writeFile(sol, source).
    runFile:value(sol, tag, mergeErrors, true) }.

; A line the block says the program writes, checked for presence and not for
; position.
;
; **Order is not assertable here.** With stderr merged into stdout the two
; interleave by buffering rather than by source: a `solvm:` complaint is
; unbuffered and arrives before a `print` that ran earlier. Requiring these in
; sequence with the claims reported a message that was word for word correct,
; which is how this was found.
matchAnywhere := { expected, output, subject | | ok |
    ok := #0.
    expected:do({ want | | seen |
        seen := false.
        output:do({ line | line:trim:equals(want):ifTrue({ seen := true }) }).
        seen:ifElse(
            { ok := ok:add(#1) },
            { failures:add([subject, #0, want,
                  "the run did not write this line"]) }) }).
    ok }.

; Each expectation must appear in the output, and after the one before it. Not
; line for line, because one statement can print many lines. Answers how many
; held; adds one report per subject on the first that did not.
matchAll := { expected, output, subject | | at, i, found, ok |
    at := #1. i := #1. ok := #0.
    { i:lessOrEqual(expected:size) }:whileTrue({
        found := nil.
        { found:isNil:and({ at:lessOrEqual(output:size) }) }:whileTrue({
            satisfies:value(output:at(at):trim, expected:at(i)):ifTrue({
                found := at }).

            ; A claim may describe several lines at once, which
            ; `#3:repeat({ "tick":display })` does -- three lines of output
            ; under one comment reading `tick tick tick`. Try the run of lines
            ; from here, joined, before giving up on this one.
            found:isNil:and({ at:lessThan(output:size) }):ifTrue({ | j, joined |
                j := at. joined := output:at(at):trim.
                { found:isNil:and({ j:lessThan(output:size) })
                      :and({ joined:size:lessOrEqual(expected:at(i):size) })
                }:whileTrue({
                    j := j:add(#1).
                    joined := joined:concat(" "):concat(output:at(j):trim).
                    satisfies:value(joined, expected:at(i)):ifTrue({
                        found := j }) }) }).

            at := at:add(#1) }).

        found:isNil:ifElse(
            { failures:add([subject, i, expected:at(i),
                  "no line of the output says this"]).
              i := expected:size:add(#1) },       ; one report per subject
            { at := found:add(#1).
              ok := ok:add(#1).
              i := i:add(#1) }) }).
    ok }.

; ---------------------------------------------------------------------------
; A .sol file, checked against its own comments

checkSol := { path | | source, expected, name, output |
    source := system:readFile(path).
    expected := expectationsIn:value(source).
    unchecked := unchecked:add(silentPrintsIn:value(source)).

    expected:size:equals(#0):ifFalse({
        files := files:add(#1).
        name := path:split("/"):last(#1):at(#1).
        name := name:copyFrom(#1, name:size:sub(#4)).

        output := runFile:value(path, name, false, false).
        output:isNil:ifElse(
            { failures:add([path, #0, "would not compile", ""]) },
            { checked := checked:add(matchAll:value(expected, output, path)) }) }) }.

; ---------------------------------------------------------------------------
; A .md file, checked block by block

checkMarkdown := { path | | source, name, n, expected, parts, output, label |
    source := system:readFile(path).
    name := path:split("/"):last(#1):at(#1).
    name := name:split("."):at(#1).
    n := #0.

    blocksIn:value(source):do({ block | | code, outputs |
        n := n:add(#1).
        parts := splitBlock:value(block:at(#2)).
        code := parts:at(#1).
        outputs := parts:at(#2).

        ; The claims written on printing lines, then the output the block says
        ; the program makes. Both are lines of what it produced, in order, so
        ; one list checks both.
        expected := expectationsIn:value(code).
        unchecked := unchecked:add(silentPrintsIn:value(code)).
        notReached := notReached:add(parts:at(#3)).

        ; A block with no code is an illustration -- what an error looks like,
        ; what a session looks like -- and there is nothing to run. Not
        ; checkable, and saying so is better than running the empty program and
        ; reporting that it did not produce the output.
        expected:size:add(outputs:size):equals(#0)
            :or({ code:trim:equals("") }):ifFalse({
            label := "{}:{}":fill([path, block:at(#1)]).
            output := runSource:value(code,
                name:concat("-"):concat(n:asString), true).

            ; A block that will not compile, or that fails with an error it did
            ; not document, is one that does not stand on its own -- it
            ; continues a block further up, or it is a fragment showing syntax
            ; rather than a program. **Not a failure, and not checked**: the two
            ; are different and a checker that confused them would be reporting
            ; the documentation for being written the way documentation is
            ; written. Counted, and the count is printed, because a checker that
            ; silently verified a quarter of its subject would be worse than
            ; none.
            output:isNil:ifElse(
                { standalone := standalone:add(#1) },
                { failed:value(output, outputs):ifElse(
                    { standalone := standalone:add(#1) },
                    { blocks := blocks:add(#1).
                      checked := checked:add(
                          matchAll:value(expected, output, label)).
                      checked := checked:add(
                          matchAnywhere:value(outputs, output, label)) }) }) }) }).

    files := files:add(#1) }.

check := { path |
    path:indexOf(".md"):isNil:ifElse(
        { checkSol:value(path) },
        { checkMarkdown:value(path) }) }.

; ---------------------------------------------------------------------------
; Running all of them

subjects:do({ subject |
    system:isDirectory(subject):ifElse(
        { system:filesIn(subject):sorted:do({ name |
              ; The changelog is skipped, and it is the only exception. It is a
              ; record of what was true at each release, so its snippets
              ; describe past states on purpose -- an entry from 0.4.0 showing
              ; what an error said then is right to keep saying it. Every other
              ; document describes the language as it is now, and is checked.
              name:equals("CHANGELOG.md"):not:and({
                  name:indexOf(".sol"):notNil:or({ name:indexOf(".md"):notNil })
              }):ifTrue({
                  check:value(subject:concat("/"):concat(name)) }) }) },
        { system:fileExists(subject):ifFalse({
              "no such file or directory: {}":fill([subject]):display.
              system:exit(#1) }).
          check:value(subject) }) }).

; ---------------------------------------------------------------------------
; The report

"":display.
"{} file{} with expectations, {} claim{} checked"
    :fill([files, files:equals(#1):ifElse({""},{"s"}),
           checked, checked:equals(#1):ifElse({""},{"s"})]):display.
blocks:greaterThan(#0):ifTrue({
    "{} of them fenced blocks that stand on their own"
        :fill([blocks]):display }).
standalone:greaterThan(#0):ifTrue({
    "{} block{} not checked: each continues one further up, or shows syntax "
        :concat("rather than a program")
        :fill([standalone, standalone:equals(#1):ifElse({""},{"s"})]):display }).
notReached:greaterThan(#0):ifTrue({
    "{} line{} sit after an error a block documents, and never run"
        :fill([notReached, notReached:equals(#1):ifElse({""},{"s"})]):display }).
unchecked:greaterThan(#0):ifTrue({
    "{} line{} print without saying what, and are not checked"
        :fill([unchecked, unchecked:equals(#1):ifElse({""},{"s"})]):display }).
stopped:greaterThan(#0):ifTrue({
    "{} ended with a non-zero status, which two of them do on purpose"
        :fill([stopped]):display }).

"":display.
failures:size:equals(#0):ifElse(
    { "every claim holds":display },
    { "{} to look at:":fill([failures:size]):display.
      failures:do({ f |
          f:at(#2):equals(#0):ifElse(
              { "  {}  {}":fill([f:at(#1), f:at(#3)]):display },
              { "  {}  claim {}: {}":fill([f:at(#1), f:at(#2), f:at(#3)]):display.
                "      {}":fill([f:at(#4)]):display }) }).
      system:exit(#1) }).
