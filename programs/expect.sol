; expect.sol -- check that what is written down is true.
;
; Run with:  ./bin/solas programs/expect.sol && ./bin/solvm programs/expect.sob
; Over the documentation:  ./bin/solvm programs/expect.sob docs
; A directory or one file:  ./bin/solvm programs/expect.sob docs/GUIDE.md
;
; Two subjects, one job. `examples/` carries 402 claims in comments; `docs/` and
; the two pages at the root carry 327 more inside ``` fences, in the same
; notation. Nothing checked either until this existed, and both are read far
; more than anything else here.
;
; The ninth program here, and the one with the narrowest customer: this
; repository. The job is real all the same. `examples/` carries inline
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
; hypothetical, and nothing here detects it -- an earlier version of this
; comment said the report gives the distance to the match, and it never did.
; Which is the same fault the program was written to catch, sitting in the
; program, in the one place it does not look: prose.

@include "scan.sol".

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

; On a cursor from `scan.sol`, which is the only one of this program's four
; scanning sites that a cursor fits. `wordBefore` runs *backwards* from the end
; of a line; `markersIn` searches for a substring rather than reading characters;
; and `asCount` filters every character rather than stopping at one. A cursor is
; forward, character-at-a-time, and stops -- so it is right here and wrong for
; those three, which stay as they are. That is worth writing down, because the
; survey behind COMPLETED.md 5.5 counted all four as scanning.
string:commentAt := { | s, inString, c, found |
    s := scan:on(self). inString := false. found := nil.
    { found:isNil:and({ s:atEnd:not }) }:whileTrue({
        c := s:next.
        inString:ifElse(
            { c:equals("\\"):ifElse(
                { s:step },
                { c:equals("\""):ifTrue({ inString := false }) }) },
            { c:equals("\""):ifTrue({ inString := true }).
              c:equals(";"):ifTrue({ found := s:pos:sub(#1) }) }) }).
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

; A claim that reads like a complaint is one.
;
; The reference writes
;
;     m:value.                 ; solvm: nil does not understand 'x'
;
; on one line where the guide writes the same thing on two, and only the
; two-line form was ever recognised. On one line it was read as a claim about
; what that line *printed*, which it cannot be -- so the block failed with an
; error nobody had documented, and went in the not-checked pile with everything
; it claimed. Both forms say the same thing and both are now read that way.
;
; Answers [errors, codeWithoutThem]: the second is what may be built on, since
; the line that raised the error is exactly the line that stops the program.
errorsIn := { source | | errors, rest |
    errors := array:new. rest := array:new.
    source:split("\n"):do({ text | | cut, claim |
        cut := text:commentAt.
        claim := cut:isNil:ifElse(
            { "" },
            { text:copyFrom(cut:add(#1), text:size):claimIn }).
        claim:isDocumentedOutput:ifElse(
            { errors:add(claim) },
            { rest:add(text) }) }).
    [errors, rest:join("\n"):concat("\n")] }.

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

; The lines between a pair of ``` fences, each with the line it started on and
; the word written after the opening fence.
;
; **A tagged fence is not Solum.** The documents already write ```sh for a shell
; transcript and ```c for a C excerpt -- 31 blocks between them -- and running
; those through a Solum compiler was only ever harmless because they fail to
; compile and land in the not-checked pile. Reading the tag says so on purpose
; instead, and leaves ```text for a block that is Solum-shaped but is not a
; program: a REPL session, a syntax exhibit, a sketch that predates the language.
blocksIn := { source | | out, n, inBlock, cur, start, tag |
    out := array:new. n := #0. inBlock := false. cur := array:new. start := #0.
    tag := "".
    source:split("\n"):do({ line |
        n := n:add(#1).
        line:size:greaterOrEqual(#3):and({ line:copyFrom(#1, #3):equals("```") })
            :ifElse(
                { inBlock:ifElse(
                    { out:add([start, cur, tag]).
                      cur := array:new. inBlock := false },
                    { inBlock := true. start := n.
                      tag := line:copyFrom(#4, line:size):trim }) },
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
notReached := #0.
notCompiled := #0.
ranError := #0.
continued := #0.
tagged := #0.
docsClaims := #0.
docsFiles := #0.
exampleClaims := #0.
exampleFiles := #0.
seen := array:new.
skipped := array:new.

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

; **Emptied before anything runs, so that a run cannot inherit its own past.**
; A block from the guide asks `system:modifiedAt("notes.txt")` and no block
; creates that file; the reference's block, further down the alphabet, does.
; The guide's therefore failed on a clean tree and passed on every run after,
; off the leftovers of the one before -- 588 claims the first time and 589
; every time since. A checker whose answer depends on how often it has been run
; is worth less than no checker, because it agrees with you eventually.
;
; `rm -rf` on a literal path this file chose, never on anything from a document.
system:run(["rm", "-rf", sandbox]).

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

checkSol := { path | | source, expected, name, output, before |
    source := system:readFile(path).
    seen:add(path).
    before := checked.
    expected := expectationsIn:value(source).
    unchecked := unchecked:add(silentPrintsIn:value(source)).

    expected:size:equals(#0):ifFalse({
        files := files:add(#1).
        name := path:split("/"):last(#1):at(#1).
        name := name:copyFrom(#1, name:size:sub(#4)).

        output := runFile:value(path, name, false, false).
        output:isNil:ifElse(
            { failures:add([path, #0, "would not compile", ""]) },
            { checked := checked:add(matchAll:value(expected, output, path)) }).

        path:indexOf("examples/"):equals(#1):ifTrue({
            exampleClaims := exampleClaims:add(checked:sub(before)).
            exampleFiles := exampleFiles:add(#1) }) }) }.

; ---------------------------------------------------------------------------
; A block that continues the one above it
;
; **This is where the claims were.** For a long time a block that would not run
; alone was counted and dropped, on the reading that it "continues one further
; up, or shows syntax rather than a program" -- both real, and both true of
; blocks carrying claims nobody was checking. Counting them found 42 such blocks
; holding **54 written claims**, against 672 checked: one claim in thirteen,
; silently taken on trust.
;
; The split says where they were, and it is not where it looked. Ten blocks
; failed to *compile*, and held 2 claims between them -- those are the shell and
; REPL transcripts, and they are as harmless as they seemed. Thirty-one compiled
; and then failed at *run* time, and those held the other 52. A name defined in
; the block above is not a fragment showing syntax; it is a program with its
; first half on the previous page.
;
; So give it its first half. **A document is read as a document**: the page
; carries a context, each block adds to it, and a block that will not run alone
; is run again on everything accepted before it. That is what the prose already
; says out loud -- *continuing the `point` above* stands 370 lines and ninety
; blocks after the `point` in question -- and it is why the obvious cheaper
; thing does not work. Prepending a fixed window of the nearest blocks recovers
; 24 of the 54 at a depth of five and not one more at twenty, because the
; distance is not the problem: what is between them is.
;
; **The context cannot satisfy the block's claims**, which is the part that has
; to be right or none of this checks anything. How much the context alone writes
; is known before the block is appended, and the block is judged only on what
; came after -- so a `true` printed on the previous page cannot stand in for a
; `true` claimed on this one.

; How many lines a run really wrote: the blank that a final newline leaves
; behind is not one of them.
realSize := { lines | | n |
    n := lines:size.
    { n:greaterThan(#0):and({ lines:at(n):trim:equals("") }) }:whileTrue({
        n := n:sub(#1) }).
    n }.

; Does this block end in a finished statement? The last line that is not blank,
; with any comment taken off it, has to end in a `.`.
;
; This is the condition that is easy to leave out, and `{ self:n:add(#1) }` --
; the reference showing what a slot holds, written without a `.` because it is a
; value and not a statement -- is why it is here. Appending anything to a block
; like that stops the result compiling, and it took the rest of the page with it.
terminated := { code | | lines, i, last |
    lines := code:split("\n"). i := lines:size. last := "".
    { last:equals(""):and({ i:greaterThan(#0) }) }:whileTrue({ | text, cut |
        text := lines:at(i).
        cut := text:commentAt.
        cut:isNil:ifFalse({ text := text:copyFrom(#1, cut:sub(#1)) }).
        last := text:trim.
        i := i:sub(#1) }).
    last:equals(""):not:and({ last:at(last:size):equals(".") }) }.

; ---------------------------------------------------------------------------
; Did the program reach the end?
;
; It has to be asked out loud, because the answer is not visible in the output.
; `system:exit` **unwinds** -- that is the documented behaviour, and the
; reference documents it in a block of its own -- so a program that stops early
; stops silently, with no complaint to notice and every line it did print still
; there. That block joined the reference's context on page 801, and from there
; the page's context was a program that exited before reaching anything, for
; ninety blocks: each one accepted, each one having produced nothing, and every
; claim in the rest of the document quietly unchecked.
;
; So the context run is asked to say so. A line is appended that prints a word
; nothing else prints, and if the word comes back the program ran to the end and
; may be built on. It costs one line of output, which is taken off again before
; anything is compared.
reachedTheEnd := "-- expect.sol ran to the end --".

sentinel := "\"":concat(reachedTheEnd):concat("\":display.\n").

; The block's own output: everything after the context's line count, plus any
; complaint found in front of it.
;
; The second half is not a hedge. With stderr merged the two streams interleave
; by buffering rather than by source, so a `solvm:` line the block produced can
; land ahead of output the context printed before it. Taking the context's line
; *count* off the front therefore does not reliably take the context's *lines*
; off the front: it left `solvm: undefined name 'animal'` sitting in the part
; being skipped, and the block was accepted as having run -- then reported for
; every claim it did not make. The context always runs clean, which is what puts
; it in the context at all, so a complaint anywhere in the combined run is the
; block's, wherever it landed.
theirsAlone := { lines, before | | out, i |
    out := array:new.
    i := #1.
    { i:lessOrEqual(before) }:whileTrue({
        lines:at(i):isDocumentedOutput:ifTrue({ out:add(lines:at(i)) }).
        i := i:add(#1) }).
    { i:lessOrEqual(lines:size) }:whileTrue({
        out:add(lines:at(i)).
        i := i:add(#1) }).
    out }.

; ---------------------------------------------------------------------------
; Counts stated in prose
;
; **The third gap, and the one that kept happening.** The checker reads comments
; in `.sol` files and fenced blocks in `.md` files, and a sentence is neither. A
; number in a sentence has no notation saying what it counts, which is the whole
; difficulty -- so it is given one:
;
;     [expect.sol](../programs/expect.sol) checks 729<!--count claims--> claims
;
; The comment renders as nothing and the reader sees the sentence. What it buys
; is that the number now says what it is a count *of*, which is the one thing
; missing, and the table below says how to recount it.
;
; What went stale without it, each found by reading rather than by running:
; `README.md`, `programs.md` and ROADMAP 3.16 all said *589 claims* for three
; releases after it stopped being 589; `programs.md` said *the nine files in
; programs/*, *one of these seven* and *what the seven have in common* on a page
; describing ten; `class-and-instance.md` said `integer` has 24 slots, three
; times, where it has 38; and ROADMAP 3.14 said `float` answers 21 messages
; where it answers 29, which is the count the entry's whole argument rests on.
;
; A name the table does not know is a failure, so a marker cannot be misspelled
; into silence -- which is the failure mode this entry is about.

marker := "<!--count ".

; A number written for a person: digits, with the thousands separators a reader
; wants, or the small ones spelled out, because a page that says *ten programs*
; is right to.
numberWords := ["zero", "one", "two", "three", "four", "five", "six", "seven",
                "eight", "nine", "ten", "eleven", "twelve", "thirteen",
                "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                "nineteen", "twenty"].

; And the tens, so that *twenty-six examples* is a number this can read. The
; alternative was to list every word up to ninety-nine, and the one after that
; was to ask the prose to write `26`, which is the thing the comment below
; refuses to do about emphasis marks and is no more reasonable here.
tensWords := ["twenty", "thirty", "forty", "fifty",
              "sixty", "seventy", "eighty", "ninety"].

hyphenated := { t | | at, tens, units |
    at := t:indexOf("-").
    at:isNil:ifElse(
        { nil },
        { tens  := tensWords:indexOf(t:copyFrom(#1, at:sub(#1))).
          units := numberWords:indexOf(t:copyFrom(at:add(#1), t:size)).
          tens:isNil:or({ units:isNil }):or({ units:greaterThan(#10) }):ifElse(
              { nil },
              { tens:add(#1):mul(#10):add(units:sub(#1)) }) }) }.

asCount := { text | | t, at, digits, i, c, ok |
    t := text:trim:asLowercase.
    at := numberWords:indexOf(t).
    at:isNil:ifTrue({ | pair |
        pair := hyphenated:value(t).
        pair:notNil:ifTrue({ at := pair:add(#1) }) }).
    at:isNil:ifElse(
        { digits := "". ok := true. i := #1.
          { i:lessOrEqual(t:size) }:whileTrue({
              c := t:at(i).

              ; A separator or an emphasis mark is not part of the number.
              ; `**729` is 729, and a checker that says otherwise is asking
              ; the prose to be written for it.
              ",*_`":indexOf(c):isNil:ifTrue({
                  "0123456789":indexOf(c):isNil:ifElse(
                      { ok := false },
                      { digits := digits:concat(c) }) }).
              i := i:add(#1) }).
          ok:and({ digits:notEquals("") }):ifElse(
              { digits:asInteger(#10) },
              { nil }) },
        { at:sub(#1) }) }.

; The word immediately before a position: the number the marker is attached to.
wordBefore := { text | | i |
    i := text:size.
    { i:greaterThan(#0):and({ text:at(i):equals(" "):not }) }:whileTrue({
        i := i:sub(#1) }).
    i:equals(text:size):ifElse(
        { "" },
        { text:copyFrom(i:add(#1), text:size) }) }.

; Every marker in a document, with the number it is attached to. More than one
; to a line, because a sentence may state two counts and often does.
stated := array:new.

markersIn := { path, source | | n |
    n := #0.
    ; **Walked with an index rather than by re-slicing.** This used to cut the
    ; line down after every marker it found, and cut it again to look for the
    ; closing `-->`, because `indexOf` could only search from the beginning.
    ; `indexOf(what, #from)` -- [6.37](../docs/COMPLETED.md#637-indexof-cannot-say-where-to-start--done),
    ; which lib/pattern.sol wanted first and this file wanted second -- makes it
    ; a walk over one string, and the copies go away with the arithmetic that
    ; kept track of where the slices had come from.
    source:split("\n"):do({ line | | from, at, close, name |
        n := n:add(#1).
        from := #1.
        { at := line:indexOf(marker, from). at:notNil }:whileTrue({
            close := line:indexOf("-->", at:add(marker:size)).
            close:isNil:ifElse(
                { from := line:size:add(#1) },
                { name := line:copyFrom(at:add(marker:size), close:sub(#1)):trim.
                  stated:add(["{}:{}":fill([path, n]), name,
                              wordBefore:value(line:copyFrom(#1, at:sub(#1)))]).
                  from := close:add(#3) }) }) }).
    nil }.

; ---------------------------------------------------------------------------
; A .md file, checked block by block

checkMarkdown := { path | | source, name, n, expected, parts, output, label,
                           context, contextLines, clean, joined, before |
    source := system:readFile(path).
    markersIn:value(path, source).
    seen:add(path).
    before := checked.
    name := path:split("/"):last(#1):at(#1).
    name := name:split("."):at(#1).
    n := #0.
    context := "".
    contextLines := #0.

    blocksIn:value(source):do({ block | | code, outputs, tag, alone, spare |
        n := n:add(#1).
        parts := splitBlock:value(block:at(#2)).
        code := parts:at(#1).
        outputs := parts:at(#2).

        ; A fence with a word after it says what it holds, and it is not Solum.
        block:at(#3):equals(""):ifElse({

        ; An error written on the line that raised it, added to the ones written
        ; underneath. **Only the first is reachable**, exactly as for those: the
        ; error stops the program, so a block showing three refusals documents
        ; three and produces one. The rest are counted as never run rather than
        ; reported as missing.
        spare := errorsIn:value(code):at(#1).
        spare:size:greaterThan(#0):ifTrue({
            outputs:size:equals(#0):ifElse(
                { outputs:add(spare:at(#1)).
                  notReached := notReached:add(spare:size:sub(#1)) },
                { notReached := notReached:add(spare:size) }) }).

        ; The claims written on printing lines, then the output the block says
        ; the program makes. Both are lines of what it produced, in order, so
        ; one list checks both.
        expected := expectationsIn:value(code).
        unchecked := unchecked:add(silentPrintsIn:value(code)).
        notReached := notReached:add(parts:at(#3)).

        code:trim:equals(""):ifFalse({
            label := "{}:{}":fill([path, block:at(#1)]).
            tag := name:concat("-"):concat(n:asString).

            ; **Every block with code is run, including the ones that claim
            ; nothing.** A block that only binds a name checks nothing itself
            ; and is the whole reason the next one works, so whether it runs has
            ; to be known before the next one is offered it.
            alone := runSource:value(code, tag, true).
            clean := alone:notNil:and({ failed:value(alone, outputs):not }).
            output := clean:ifElse({ alone }, { nil }).

            ; And on the page's context, which is a second run and the reason
            ; this is not free -- `make test` goes from seven seconds to twenty
            ; on account of it. It happens even when the block stood on its own,
            ; because the context's line count has to stay *exact*: a block that
            ; ran alone still adds its output to the page, and adding up what it
            ; wrote by itself instead of measuring the two together would put
            ; every claim under it one line out. Being one line out is not a
            ; failure that shows: it is a claim matched against somebody else's
            ; output.
            ;
            ; What can be skipped is the block that could not join the context
            ; anyway -- one that documents an error, or does not end in a
            ; finished statement -- and that has already been checked on its own.
            context:equals("")
                :or({ clean:and({ outputs:size:greaterThan(#0)
                                      :or({ terminated:value(code):not }) }) })
                :ifElse(
                { joined := clean:ifElse({ realSize:value(alone) }, { nil }) },
                { | both, ask, reached |
                  ask := terminated:value(code).
                  both := runSource:value(
                      context:concat(code)
                             :concat(ask:ifElse({ sentinel }, { "" })),
                      tag:concat("-x"), true).
                  reached := both:notNil:and({ ask })
                      :and({ realSize:value(both):greaterThan(#0) })
                      :and({ both:at(realSize:value(both)):trim
                                 :equals(reachedTheEnd) }).
                  reached:ifTrue({
                      both := both:first(realSize:value(both):sub(#1)) }).
                  both:notNil:and({ failed:value(both, outputs):not })
                       :and({ realSize:value(both)
                                  :greaterOrEqual(contextLines) })
                       :ifElse(
                      { | wrote |
                        wrote := realSize:value(both).

                        ; The context grows only if the program reached the end
                        ; of itself; the block is checked on what it wrote
                        ; either way. Two questions, and answering both from one
                        ; number is what let `system:exit` through.
                        joined := reached:ifElse({ wrote }, { nil }).
                        ; **More than the context alone wrote**, or the block
                        ; never ran: an error further up stops the program where
                        ; it stands, and an empty tail then contradicts nothing
                        ; and checks nothing. Accepting equality here passed
                        ; nine blocks of the reference that had produced not one
                        ; line, and reported every claim in them as unmet. The
                        ; context may still grow -- a block that binds a name
                        ; and prints nothing is exactly what the next one wants.
                        output:isNil
                            :and({ wrote:greaterThan(contextLines) })
                            :ifTrue({
                                continued := continued:add(#1).
                                output := theirsAlone:value(both,
                                    contextLines) }) },
                      { joined := nil }) }).

            ; The two categories, kept apart because they were guessed at the
            ; wrong way round for a year: a block that will not compile is a
            ; transcript, and a block that compiles and then fails is a program
            ; missing its first half.
            clean:ifFalse({
                expected:size:add(outputs:size):greaterThan(#0):ifTrue({
                    alone:isNil
                        :ifTrue({ notCompiled := notCompiled:add(#1) }).
                    alone:isNil:not
                        :ifTrue({ ranError := ranError:add(#1) }) }) }).

            ; A block that ran neither way is set aside for the report, which
            ; turns it into a failure. It used to be a count, on the reading
            ; that such a block continues one above or shows syntax rather than
            ; a program -- and a block nobody checks is cheap, where a *claim*
            ; nobody checks is the thing this program exists to stop.
            expected:size:add(outputs:size):equals(#0):ifFalse({
                output:isNil:ifElse(
                    { skipped:add([label, expected:size]) },
                    { blocks := blocks:add(#1).
                      checked := checked:add(
                          matchAll:value(expected, output, label)).
                      checked := checked:add(
                          matchAnywhere:value(outputs, output, label)) }) }).

            ; **What the page carries forward.** A block joins the context when
            ; it ran, ends in a finished statement, and documents no error --
            ; the last because an error stops the program where it stands, so
            ; anything appended after one never runs at all. That does not fail,
            ; because an empty tail contradicts nothing; it just checks nothing,
            ; which is worse.
            ;
            ; A block that ran neither way leaves the context alone rather than
            ; resetting it: a transcript in the middle of a page is an aside,
            ; not a new beginning, and the blocks under it still mean what the
            ; ones above it set up.
            joined:notNil:and({ outputs:size:equals(#0) })
                          :and({ terminated:value(code) })
                          :ifTrue({
                context := context:concat(code).
                contextLines := joined }) }) },

        { tagged := tagged:add(#1) }) }).

    ; What the documents alone account for, since `programs.md` states that
    ; separately from the total and both numbers have to stay true.
    path:indexOf("docs/"):equals(#1):ifTrue({
        docsClaims := docsClaims:add(checked:sub(before)).
        docsFiles := docsFiles:add(#1) }).

    files := files:add(#1) }.

; **A suffix is not a substring.** These questions are about how a name ends,
; and `indexOf` answers a different one: it found `.sol` in `hello.sol.bak` and
; `.md` in `draft.md.orig`, called both of them files to check, and would have
; handed `a.md.sol` to the markdown checker. Nothing in the tree is named that
; way today, which is exactly how it went unnoticed. Named for the question it
; answers, so the next reader does not have to spot the difference.
string:endsWith := { suffix |
    self:size:greaterOrEqual(suffix:size):and({
        self:copyFrom(self:size:sub(suffix:size):add(#1), self:size)
            :equals(suffix) }) }.

check := { path |
    path:endsWith(".md"):ifElse(
        { checkMarkdown:value(path) },
        { checkSol:value(path) }) }.

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
                  name:endsWith(".sol"):or({ name:endsWith(".md") })
              }):ifTrue({
                  check:value(subject:concat("/"):concat(name)) }) }) },
        { system:fileExists(subject):ifFalse({
              "no such file or directory: {}":fill([subject]):display.
              system:exit(#1) }).
          check:value(subject) }) }).

; ---------------------------------------------------------------------------
; Recounting what the prose said
;
; **Two kinds of count, and only one of them survives a partial run.** How many
; programs there are, or how many slots `integer` has, is true whatever this
; program was pointed at. How many claims held is a fact about *this run*, so
; when the run did not cover everything those markers are reported as skipped
; rather than compared against a total that means something narrower.
;
; Completeness is not taken on trust from the command line: it is whether every
; file this program would check was in fact checked.

solFilesIn := { dir | | n |
    n := #0.
    system:filesIn(dir):do({ name |
        name:endsWith(".sol"):ifTrue({ n := n:add(#1) }) }).
    n }.

wanted := array:new.
system:filesIn("examples"):sorted:do({ name |
    name:endsWith(".sol"):ifTrue({
        wanted:add("examples/":concat(name)) }) }).
system:filesIn("docs"):sorted:do({ name |
    name:equals("CHANGELOG.md"):not:and({ name:endsWith(".md") }):ifTrue({
        wanted:add("docs/":concat(name)) }) }).
wanted:add("README.md").
wanted:add("index.md").

complete := true.
wanted:do({ path | seen:indexOf(path):isNil:ifTrue({ complete := false }) }).

; What each name counts. A marker naming something not here is a failure: a
; checker that shrugs at a name it does not know is the silence this was written
; to end.
count := dictionary:new.
count:atPut("programs",      solFilesIn:value("programs")).
count:atPut("examples",      solFilesIn:value("examples")).
count:atPut("library",       solFilesIn:value("lib")).
count:atPut("integer-slots", integer:slots:size).
count:atPut("float-slots",   float:slots:size).
count:atPut("string-slots",  string:slots:size).
count:atPut("array-slots",   array:slots:size).
count:atPut("object-slots",  object:slots:size).

; **What a class holds and what a value answers are two numbers**, and since
; 1.6 they are different: a class object's slots carry the class side as well
; as the instance side, so `integer:slots:size` is 38 where an integer answers
; 35. ROADMAP 3.14 said `float` answers 21 messages and rested an argument
; about size on it; it answers 26, and had for five releases.
answers := { class, sample | | n |
    n := #0.
    class:slots:do({ s | sample:respondsTo(s):ifTrue({ n := n:add(#1) }) }).
    n }.
count:atPut("integer-answers", answers:value(integer, #45)).
count:atPut("float-answers",   answers:value(float, 1.5)).
count:atPut("string-answers",  answers:value(string, "a")).
count:atPut("array-answers",   answers:value(array, [#1])).

; **How many distinct messages the language has**, which is the number this
; repository has got wrong most often: it is stated in the README and in the
; repository's description on GitHub, and went 125 to 124 to 123 in one evening,
; by hand, from grep, twice. The reference's index has been held to the registry
; by a test all along; nothing held the prose to the index.
;
; A name a class holds is a **message** when it is built in and a **slot** when
; it has a value, and `slotAt` is what tells them apart: it refuses the first
; kind and answers the second. Without that, `system:arguments` and
; `error:message` count as messages and the total is two too many.
messages := { names |
    [integer, float, string, array, dictionary, symbol, boolean, block,
     time, error, object, random, system]:do({ class |
        class:slots:do({ s |
            names:indexOf(s):isNil:ifTrue({
                { class:slotAt(s) }:onError({ e | names:add(s) }) }) }) }).
    names:size }.
count:atPut("messages", messages:value(array:new)).

; The ones that are facts about this run.
perRun := ["claims", "checked-files", "docs-claims", "docs-documents",
           "examples-claims", "examples-files"].
complete:ifTrue({
    count:atPut("claims",         checked).
    count:atPut("checked-files",  files).
    count:atPut("docs-claims",    docsClaims).
    count:atPut("docs-documents", docsFiles).
    count:atPut("examples-claims", exampleClaims).
    count:atPut("examples-files",  exampleFiles) }).

recounted := #0.
deferred := #0.
stated:do({ c | | name, want, got |
    name := c:at(#2).
    count:at(name, nil):isNil:ifElse(
        { perRun:indexOf(name):notNil:and({ complete:not }):ifElse(
            { deferred := deferred:add(#1) },
            { failures:add([c:at(#1), #0,
                  "nothing counts '":concat(name):concat("'"), ""]) }) },
        { want := count:at(name).
          got := asCount:value(c:at(#3)).
          got:isNil:ifElse(
              { failures:add([c:at(#1), #0,
                    "'":concat(c:at(#3))
                        :concat("' is not a number this can read"), ""]) },
              { got:equals(want):ifElse(
                  { recounted := recounted:add(#1) },
                  { failures:add([c:at(#1), #0,
                        "says {} {}, and there are {}"
                            :fill([c:at(#3), name, want]), ""]) }) }) }) }).

; ---------------------------------------------------------------------------
; Where a program says it comes in the order
;
; Seven of the ten open with a line reading *The fifth program here, and the
; first that writes to the filesystem*, and [programs.md](../docs/programs.md)
; puts them in that order under its headings. Nothing held the two together, and
; this entry names *"the fifth program here"* as its own example of a number in
; a sentence that nothing counts.
;
; **This one needs no marker, because the phrase is the marker.** It is written
; the same way in every file that uses it, which is what makes it findable --
; and a count that is already stated in a fixed form does not need a second
; notation bolted to it.

ordinals := ["first", "second", "third", "fourth", "fifth", "sixth", "seventh",
             "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth",
             "fourteenth", "fifteenth", "sixteenth", "seventeenth",
             "eighteenth", "nineteenth", "twentieth"].

; **Longer than the list of programs, and guarded anyway.** This has to be
; extended by hand when a program is added, and the failure when somebody
; forgets used to be `index #14 is out of bounds for an array of size 13` --
; a crash, in the checker, on the run that was supposed to report the mistake.
; The guard below is what makes forgetting a *report* instead, and the spare
; words are so that it usually need not be remembered at all.
ordinalWord := { n |
    n:isNil:ifElse({ "nowhere" }, {
        n:greaterThan(ordinals:size)
            :ifElse({ "at position {}":fill([n]) }, { ordinals:at(n) }) }) }.

placed := #0.
system:fileExists("docs/programs.md"):ifTrue({ | order |

    ; The order the page puts them in: the first word of every `## ` heading
    ; that names a file in programs/.
    order := array:new.
    system:readFile("docs/programs.md"):split("\n"):do({ line | | name |
        line:size:greaterThan(#3):and({ line:copyFrom(#1, #3):equals("## ") })
            :ifTrue({
                name := line:copyFrom(#4, line:size):trim:split(" "):at(#1).
                system:fileExists("programs/":concat(name):concat(".sol"))
                    :ifTrue({ order:add(name) }) }) }).

    system:filesIn("programs"):sorted:do({ file | | path, source, at, word, was |
        file:endsWith(".sol"):ifTrue({
            path := "programs/":concat(file).
            source := system:readFile(path).

            ; The line has to *open* with it. Looking anywhere in the file finds
            ; this program's own paragraph about the convention, and a checker
            ; that reports its own documentation has learnt nothing.
            word := nil.
            source:split("\n"):do({ line |
                word:isNil:and({ line:size:greaterThan(#6) })
                    :and({ line:copyFrom(#1, #6):equals("; The ") })
                    :and({ line:indexOf(" program here"):notNil }):ifTrue({
                        at := line:indexOf(" program here").
                        word := line:copyFrom(#7, at:sub(#1)):trim
                                    :asLowercase }) }).
            word:notNil:ifTrue({
                was := order:indexOf(file:copyFrom(#1, file:size:sub(#4))).
                ordinals:indexOf(word):equals(was):ifElse(
                    { placed := placed:add(#1) },
                    { failures:add([path, #0,
                          "calls itself the {} program, and programs.md puts it {}"
                              :fill([word, ordinalWord:value(was)]), ""]) }) }) }) }) }).

; ---------------------------------------------------------------------------
; The report

"":display.
"{} file{} with expectations, {} claim{} checked"
    :fill([files, files:equals(#1):ifElse({""},{"s"}),
           checked, checked:equals(#1):ifElse({""},{"s"})]):display.
blocks:greaterThan(#0):ifTrue({
    "{} of them in fenced blocks, {} standing alone and {} given the page above"
        :fill([blocks, blocks:sub(continued), continued]):display }).
tagged:greaterThan(#0):ifTrue({
    "{} fence{} name{} a language and {} not Solum"
        :fill([tagged,
               tagged:equals(#1):ifElse({""},{"s"}),
               tagged:equals(#1):ifElse({"s"},{""}),
               tagged:equals(#1):ifElse({"is"},{"are"})]):display }).
notCompiled:add(ranError):greaterThan(#0):ifTrue({
    "{} would not compile alone and {} compiled and then failed alone; {} ran "
        :concat("once given the page above")
        :fill([notCompiled, ranError, continued]):display }).
notReached:greaterThan(#0):ifTrue({
    "{} line{} sit after an error a block documents, and never run"
        :fill([notReached, notReached:equals(#1):ifElse({""},{"s"})]):display }).
unchecked:greaterThan(#0):ifTrue({
    "{} line{} print without saying what, and are not checked"
        :fill([unchecked, unchecked:equals(#1):ifElse({""},{"s"})]):display }).
placed:greaterThan(#0):ifTrue({
    "{} program{} say where {} come{} in the order, and are there"
        :fill([placed, placed:equals(#1):ifElse({""},{"s"}),
               placed:equals(#1):ifElse({"it"},{"they"}),
               placed:equals(#1):ifElse({"s"},{""})]):display }).
recounted:add(deferred):greaterThan(#0):ifTrue({
    "{} count{} stated in prose, recounted{}"
        :fill([recounted, recounted:equals(#1):ifElse({""},{"s"}),
               deferred:greaterThan(#0):ifElse(
                   { "; {} more want the whole set to be checked"
                         :fill([deferred]) },
                   { "" })]):display }).
stopped:greaterThan(#0):ifTrue({
    "{} run{} ended with a non-zero status, which is what a documented error "
        :concat("does")
        :fill([stopped, stopped:equals(#1):ifElse({""},{"s"})]):display }).

; **A block that will not run is now a failure**, which it was not for most of
; this program's life, and the change is the whole point of the exercise that
; produced it. The old reading was that such a block "continues one further up,
; or shows syntax rather than a program" -- both real, and both also true of a
; block with a typo in it. `README.md`'s opening snippet, the four lines that
; introduce the language to everybody who arrives, was missing the `.` after
; `a := #45` and had been seen and skipped on every run for months.
;
; The objection to closing this was that the convention would have to be applied
; to 42 blocks before it could be enforced on the 43rd. It was applied to 14 of
; them; the other 28 turned out to be programs that ran perfectly once the page
; they were written under was given to them, and 8 were broken and had been for
; a long time. **What a block that is not a program needs is a word after its
; fence** -- `text` for a session or a sketch, `sh` for a shell transcript, `c`
; for C -- which the documents were already doing for the last two, and which a
; reader can see, unlike a silence in a count.
skipped:do({ b |
    failures:add([b:at(#1), #0,
        "did not run, alone or after the page above it; tag the fence "
            :concat("with a language if it is not a program"), ""]) }).

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
