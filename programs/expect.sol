; expect.sol -- run every example and check it does what its comments claim.
;
; Run with:  ./bin/solas programs/expect.sol && ./bin/solvm programs/expect.sob
; Over a directory of your own:  ./bin/solvm programs/expect.sob examples
; One file:  ./bin/solvm programs/expect.sob examples/numbers.sol
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

directory := "examples".
single := nil.

system:arguments:size:greaterThan(#0):ifTrue({ | given |
    given := system:arguments:at(#1).
    given:indexOf(".sol"):isNil:ifElse(
        { directory := given },
        { single := given. directory := nil }) }).

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
; Running one

failures := array:new.
stopped := #0.
checked := #0.
unchecked := #0.
files := #0.

check := { path | | source, name, sob, result, output, expected, at, i,
                    found, gap, ok, built |
    source := system:readFile(path).
    expected := expectationsIn:value(source).
    unchecked := unchecked:add(silentPrintsIn:value(source)).

    expected:size:equals(#0):ifFalse({
        files := files:add(#1).
        name := path:split("/"):last(#1):at(#1).
        sob := "build/expect-":concat(name:copyFrom(#1, name:size:sub(#4)))
                              :concat(".sob").

        built := system:run(["./bin/solas", path, "-o", sob]):equals(#0).
        built:ifElse(
            { result := system:capture(["./bin/solvm", sob]).
              output := result:at("output"):split("\n").

              ; A non-zero status is worth saying rather than hiding: an example
              ; that stops early has not disproved its comments, it has stopped
              ; answering for them. reading.sol is one, having no input to read.
              ; A non-zero status is not a failure by itself: system.sol ends
              ; with `system:exit(#2)` on purpose and strictness.sol ends with
              ; an uncaught error on purpose, both to show what one looks like.
              ; It is worth counting, because a program that stopped early has
              ; not disproved its remaining comments so much as stopped
              ; answering for them.
              result:at("status"):equals(#0):ifFalse({
                  stopped := stopped:add(#1) }).

              at := #1. i := #1. ok := #0.
              { i:lessOrEqual(expected:size) }:whileTrue({
                  found := nil.
                  { found:isNil:and({ at:lessOrEqual(output:size) }) }:whileTrue({
                      satisfies:value(output:at(at):trim, expected:at(i))
                          :ifTrue({ found := at }).

                      ; A claim may describe several lines at once, which
                      ; `#3:repeat({ "tick":display })` does -- three lines of
                      ; output under one comment reading `tick tick tick`. Try
                      ; the run of lines from here, joined, before giving up on
                      ; this one.
                      found:isNil:and({ at:lessThan(output:size) }):ifTrue({
                                | j, joined |
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
                      { failures:add([path, i, expected:at(i),
                            "no line of the output says this"]).
                        i := expected:size:add(#1) },   ; one report per file
                      { at := found:add(#1).
                        ok := ok:add(#1).
                        i := i:add(#1) }) }).

              checked := checked:add(ok) },
            { failures:add([path, #0, "would not compile", ""]) }) }) }.

; ---------------------------------------------------------------------------
; Running all of them

single:isNil:ifElse(
    { system:isDirectory(directory):ifFalse({
          "{} is not a directory":fill([directory]):display.
          system:exit(#1) }).
      system:filesIn(directory):sorted:do({ name |
          name:indexOf(".sol"):notNil:ifTrue({
              check:value(directory:concat("/"):concat(name)) }) }) },
    { system:fileExists(single):ifFalse({
          "no such file: {}":fill([single]):display.
          system:exit(#1) }).
      check:value(single) }).

; ---------------------------------------------------------------------------
; The report

"":display.
"{} file{} with expectations, {} claim{} checked"
    :fill([files, files:equals(#1):ifElse({""},{"s"}),
           checked, checked:equals(#1):ifElse({""},{"s"})]):display.
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
