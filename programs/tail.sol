; tail.sol -- the end of a file, without reading the rest of it.
;
; Run with:  ./bin/solas programs/tail.sol && ./bin/solvm programs/tail.sob
;
;     solvm tail.sob big.log                  the last ten lines
;     solvm tail.sob -n 50 big.log            the last fifty
;     solvm tail.sob -n +200 big.log          from line 200 to the end
;     solvm tail.sob -c 4096 big.log          the last four kilobytes
;     ... | solvm tail.sob -n 3               from a pipe, which cannot seek
;
; With no arguments it demonstrates itself on a file it writes, which is the
; house rule for these programs.
;
; ---------------------------------------------------------------------------
; The seventeenth program here, and the first written to check a call rather
; than to ask for one
;
; **This is the wrong way round on purpose, and the reasoning is in
; [ideas.md](../docs/ideas.md#tail-and-the-file-this-language-cannot-read--scoped-2026-08-31).**
; The rule here is that a program asks and a page does not, so the plan was to
; write this on the whole-file read and let it press on
; [3.22](../docs/COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done).
;
; That plan was wrong for a reason worth keeping: **the evidence arrived before
; the program did.** A sparse file is 3 GB and 8 KB of disk, and on one of those
; `fileSize` answered and `readFile` refused — the language could measure a file
; and not read a byte of it, which is as clear as evidence gets and took four
; seconds. A `tail` written on the whole-file read would have re-proved that and
; said nothing about the shape of the fix, **because it could not have called
; it**.
;
; So the range was built first and this is its first caller. The question it
; exists to answer is not *is something missing* but **is what was built usable**
; — and the answer is at the bottom of this file, after the code.
;
; ---------------------------------------------------------------------------
; What is here
;
;   -n N     the last N lines; ten by default
;   -n +N    from line N to the end
;   -c N     the last N bytes
;   -c +N    from byte N to the end
;   -q -v    never or always print the `==> name <==` heading
;
; Several files are taken, and standard input when none is named. Left out:
; `-f`, `-F` and `-r`. The first of those has a finding of its own and no way to
; be checked by an oracle that expects a program to stop, and it is named at the
; bottom rather than half-built here.

; ---------------------------------------------------------------------------
; Reading backwards
;
; **A chunk at a time, from the end, until enough newlines have gone by.** Eight
; kilobytes is the chunk, which holds the last ten lines of every log this was
; tried on, so the usual answer costs one read.
;
; The entry that closed said the price of a range is that *a record spanning two
; chunks becomes the caller's problem*. It does, and `back` below is that
; problem being solved: the running total `found` is what carries across a
; boundary, and a line split between two chunks is simply one whose newline was
; counted in the earlier one.

chunkSize := #8192.

tail := object:new.

; The last `n` lines of a file, as one string, keeping their terminators.
;
; **A newline at the very end terminates the last line rather than starting a
; new one**, so it is stepped over before the counting begins. Without that,
; `tail -n 1` on a file ending in a newline answers the empty string after it,
; which is what a first draft did and what the oracle caught in one case.
tail:lastLines := { path, n | | size, edge, at, from, chunk, pieces, newlines, take, part, found, start |
    size := system:fileSize(path).

    ; Written as one `ifElse` rather than as a guard and a return, because
    ; [3.2](../docs/ROADMAP.md#32-no-non-local-return) means there is nothing to
    ; return from. Three of these in this file; see the note at the bottom.
    size:equals(#0):or({ n:equals(#0) }):ifElse({ "" }, {

    edge := system:readFile(path, size, #1):equals("\n"):ifElse(
        { size:sub(#1) }, { size }).

    found := #0.
    start := #1.
    at := edge.

    { found:lessThan(n):and({ at:greaterOrEqual(#1) }) }:whileTrue({
        from := at:sub(chunkSize):add(#1).
        from:lessThan(#1):ifTrue({ from := #1 }).
        chunk := system:readFile(path, from, at:sub(from):add(#1)).

        ; `split` is the counting. A chunk with k newlines answers k+1 pieces,
        ; and the last `take` of them are the last `take` lines it holds --
        ; joined back up they are byte-for-byte the tail of the chunk, because
        ; `join` puts back exactly what `split` took out. That is why the offset
        ; below can be arithmetic rather than another search.
        pieces := chunk:split("\n").
        newlines := pieces:size:sub(#1).

        found:add(newlines):greaterOrEqual(n):ifElse(
            { take := n:sub(found).
              part := pieces:copyFrom(pieces:size:sub(take):add(#1), pieces:size)
                            :join("\n").
              start := from:add(chunk:size):sub(part:size).
              found := n },
            { found := found:add(newlines).
              at := from:sub(#1) }) }).

    system:readFile(path, start, size:sub(start):add(#1)) }) }.

; The last `n` bytes, which needs no searching at all -- the one place a range
; is the whole answer rather than the tool the answer is built from.
tail:lastBytes := { path, n | | size, start |
    size := system:fileSize(path).
    start := size:sub(n):add(#1).
    start:lessThan(#1):ifTrue({ start := #1 }).
    system:readFile(path, start, size:sub(start):add(#1)) }.

; ---------------------------------------------------------------------------
; Reading forwards
;
; `-n +N` and `-c +N` are the other half, and they are the half that cannot
; answer with one string: *from line 200 to the end* of a file too large to hold
; is still too large to hold. So these write as they go, a chunk at a time,
; which is what a range looks like when it is being used as a stream.

; Where line `n` begins, as a byte position; one past the end if there is no
; such line.
tail:startOfLine := { path, n | | size, at, chunk, pieces, newlines, want |
    size := system:fileSize(path).
    n:lessOrEqual(#1):ifElse({ #1 }, {

    want := n:sub(#1).                  ; newlines to cross
    at := #1.

    { want:greaterThan(#0):and({ at:lessOrEqual(size) }) }:whileTrue({
        chunk := system:readFile(path, at, chunkSize).
        pieces := chunk:split("\n").
        newlines := pieces:size:sub(#1).

        newlines:greaterOrEqual(want):ifElse(
            { ; The wanted line begins after the `want`-th newline in here, and
              ; the pieces before it are what stands in front of that byte.
              at := at:add(pieces:copyFrom(#1, want):join("\n"):size):add(#1).
              want := #0 },
            { want := want:sub(newlines).
              at := at:add(chunk:size) }) }).

    at }) }.

; Everything from `at` to the end, written out a chunk at a time.
tail:writeFrom := { path, at | | size, pos, chunk |
    size := system:fileSize(path).
    pos := at.
    { pos:lessOrEqual(size) }:whileTrue({
        chunk := system:readFile(path, pos, chunkSize).
        chunk:size:equals(#0):ifElse(
            { pos := size:add(#1) },
            { system:write(chunk).
              pos := pos:add(chunk:size) }) }) }.

; ---------------------------------------------------------------------------
; Standard input, which cannot be seeked
;
; **A pipe has no size and no positions**, so none of the above applies and the
; only way to know the last ten lines is to have seen them all go past. What is
; kept is bounded rather than the whole input: a ring of `n` lines for `-n`, and
; the last `n` bytes for `-c`.
;
; This is the shape real `tail` has for the same reason, and it is the honest
; answer to *why is a pipe different* — not a gap in this language.

tail:stdinLines := { n | | ring, at, filled, line, out, i |
    n:equals(#0):ifElse({ "" }, {
    ring := array:new.
    [#1, n]:loop({ i | ring:add(nil) }).
    at := #0.
    filled := #0.

    line := system:readLine.
    { line:notNil }:whileTrue({
        at := at:mod(n):add(#1).
        ring:atPut(at, line).
        filled:lessThan(n):ifTrue({ filled := filled:add(#1) }).
        line := system:readLine }).

    out := "".
    [#1, filled]:loop({ i |
        out := out:concat(ring:at(at:sub(filled):add(i):sub(#1):mod(n):add(#1)))
                  :concat("\n") }).
    out }) }.

tail:stdinBytes := { n | | out, line |
    out := "".
    line := system:readLine.
    { line:notNil }:whileTrue({
        out := out:concat(line):concat("\n").
        ; Kept bounded rather than kept whole. The trim is why this is not a
        ; program that holds a pipe.
        out:size:greaterThan(n):ifTrue({
            out := out:copyFrom(out:size:sub(n):add(#1), out:size) }).
        line := system:readLine }).
    out }.

tail:stdinFrom := { n, lines | | count, line, out |
    count := #0.
    out := "".
    line := system:readLine.
    { line:notNil }:whileTrue({
        count := count:add(#1).
        lines:ifElse(
            { count:greaterOrEqual(n):ifTrue({
                  out := out:concat(line):concat("\n") }) },
            { out := out:concat(line):concat("\n") }).
        line := system:readLine }).
    lines:ifElse(
        { out },
        { out:size:lessThan(n):ifElse({ "" },
                                      { out:copyFrom(n, out:size) }) }) }.

; ---------------------------------------------------------------------------
; The command line

options := object:new.
options:count := #10.
options:unit := 'lines.             ; 'lines or 'bytes
options:fromStart := false.         ; the `+N` form
options:quiet := false.
options:verbose := false.
options:files := nil.

options:number := { text | | body |
    body := text.
    body:copyFrom(#1, #1):equals("+"):ifTrue({
        options:fromStart := true.
        body := body:copyFrom(#2, body:size) }).
    { body:asInteger }:onError({ e |
        error:raise("`{}` is not a number":fill([text])) }) }.

options:read := { args | | i, a, j, c, done, value |
    self:files := array:new.
    i := #1.

    { i:lessOrEqual(args:size) }:whileTrue({
        a := args:at(i).

        a:equals("--"):ifElse(
            { i := i:add(#1).
              { i:lessOrEqual(args:size) }:whileTrue({
                  self:files:add(args:at(i)). i := i:add(#1) }) },

            { a:size:greaterThan(#1):and({ a:copyFrom(#1, #1):equals("-") })
                :ifElse(
                { j := #2.
                  done := false.
                  { done:not:and({ j:lessOrEqual(a:size) }) }:whileTrue({
                      c := a:at(j).
                      c:equals("q"):ifTrue({ self:quiet := true. j := j:add(#1) }).
                      c:equals("v"):ifTrue({ self:verbose := true. j := j:add(#1) }).
                      c:equals("n"):or({ c:equals("c") }):ifTrue({
                          j:lessThan(a:size):ifElse(
                              { value := a:copyFrom(j:add(#1), a:size) },
                              { i := i:add(#1).
                                i:greaterThan(args:size):ifTrue({
                                    error:raise("-{} wants a number after it"
                                                    :fill([c])) }).
                                value := args:at(i) }).
                          self:unit := c:equals("n"):ifElse({ 'lines }, { 'bytes }).
                          self:count := self:number(value).
                          done := true }).
                      ["q", "v", "n", "c"]:indexOf(c):isNil:ifTrue({
                          error:raise("unknown option `-{}`":fill([c])) }) }).
                  i := i:add(#1) },

                { self:files:add(a). i := i:add(#1) }) }) }).

    self:count:lessThan(#0):ifTrue({ error:raise("a count cannot be negative") }).
    self:fromStart:and({ self:count:equals(#0) }):ifTrue({ self:count := #1 }).
    self:files:do({ f |
        system:fileExists(f):ifFalse({
            error:raise("cannot read `{}`":fill([f])) }) }).
    self }.

; ---------------------------------------------------------------------------
; Doing it

tail:ofFile := { path |
    options:fromStart:ifElse(
        { options:unit:equals('lines):ifElse(
            { self:writeFrom(path, self:startOfLine(path, options:count)) },
            { self:writeFrom(path, options:count) }) },
        { options:unit:equals('lines):ifElse(
            { system:write(self:lastLines(path, options:count)) },
            { system:write(self:lastBytes(path, options:count)) }) }) }.

tail:ofStdin := {
    options:fromStart:ifElse(
        { system:write(self:stdinFrom(options:count,
                                      options:unit:equals('lines))) },
        { options:unit:equals('lines):ifElse(
            { system:write(self:stdinLines(options:count)) },
            { system:write(self:stdinBytes(options:count)) }) }) }.

; A heading when there is more than one file, which is what every tail does and
; is the only thing here that depends on how many files there are.
tail:run := {
    options:files:size:equals(#0):ifElse(
        { options:verbose:and({ options:quiet:not }):ifTrue({
              "==> standard input <==":display }).
          self:ofStdin },
        { | first |
          first := true.
          options:files:do({ path |
              (options:verbose:or({ options:files:size:greaterThan(#1) })
                  :and({ options:quiet:not })):ifTrue({
                  first:ifFalse({ "":display }).
                  "==> {} <==":fill([path]):display }).
              first := false.
              self:ofFile(path) }) }) }.

; ---------------------------------------------------------------------------
; What it does with no arguments

demonstrate := { | path, size |
    path := "build/tail-demo.txt".
    system:makeDirectory("build").
    system:writeFile(path,
        "alpha\nbravo\ncharlie\ndelta\necho\nfoxtrot\ngolf\nhotel\n").

    "":display.
    "tail -- the end of a file, without reading the rest of it.":display.
    "":display.
    "  {} holds {} bytes:":fill([path, system:fileSize(path)]):display.
    "":display.
    system:write(system:readFile(path)).

    "":display.
    "  $ tail -n 3":display.
    "":display.
    system:write(self:lastLines(path, #3)).

    "":display.
    "  $ tail -n +6":display.
    "":display.
    self:writeFrom(path, self:startOfLine(path, #6)).

    "":display.
    "  $ tail -c 12":display.
    "":display.
    system:write(self:lastBytes(path, #12)).

    "":display.
    "  Not one of those read the file whole. On a 3 GB file the same three":display.
    "  calls answer in milliseconds, and readFile(path) refuses it outright.":display.
    "":display.
    system:remove(path) }.

; ---------------------------------------------------------------------------
; No arguments means two different things, and this is how they are told apart
;
; Every program here runs with no arguments on input it carries. `tail` with no
; arguments is also a **real invocation** -- `... | tail` is how half of its uses
; are typed -- so the house rule and the tool collide over the same empty
; command line, which no other program here has had happen.
;
; **`keyWaiting(0.0)` is what separates them**, and it is the nearest thing this
; language has to asking whether standard input is a terminal. It answers *is
; there a byte to read, right now*, and it is documented as **true at the end of
; input** -- so a pipe answers true whether it is full or finished, and an idle
; terminal answers false. That property is a nuisance everywhere else and is
; exactly what is wanted here.
;
; A person typing at a prompt gets the demonstration rather than a program
; waiting for them to type a file, which is the house rule winning a case it
; should win.

{ system:arguments:size:equals(#0):and({ system:keyWaiting(0.0):not }):ifElse(
    { demonstrate:boundTo(tail):value },
    { options:read(system:arguments).
      tail:run }) }
    :onError({ e |
        system:writeError("tail: ":concat(e:message):concat("\n")).
        system:exit(#1) }).

; ---------------------------------------------------------------------------
; What this program found
;
; Written after the code and after the oracle. Everything below was run.
;
; ---------------------------------------------------------------------------
; The question it was written to answer, and the answer is nothing
;
; This was not written to ask for something. The range was already built, and
; this is the first caller: the question is **is what was built usable**, and
; the honest answer is that it wanted no change of any kind. No extra argument,
; no convenience, no different rule at the edges.
;
; That is the whole finding and it is worth stating plainly rather than dressing
; up, because [ideas.md](../docs/ideas.md) put *it found nothing* on the table as
; an available answer and this is a case where it is the true one.
;
; **What it is measured against**: 29 cases held byte-for-byte against
; `/usr/bin/tail` by [oracle.sh](oracle.sh), each run twice -- input named as a
; file and input on a pipe -- plus seven more by hand for the several-file
; headings the harness cannot express, and the same two commands on a 3 GB file.
; Every one identical.
;
; | file | `tail -n 3` here | `sed -n '$p'`, which reads it whole |
; | --- | --- | --- |
; | 618 KB | 2.1 MB | 5.4 MB |
; | 6.4 MB | 2.1 MB | 32.4 MB |
; | 3 GB | 2.0 MB, in 5 ms | *refused* |
;
; **Flat**, and the last row is the one the range was built for.
;
; ---------------------------------------------------------------------------
; The predicted cost was real, and `split` paid it
;
; [3.22](../docs/COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done) said
; a range's real price is that **a record spanning two chunks becomes the
; caller's problem**, and it does. `lastLines` above is that problem: it walks
; backwards a chunk at a time and a line may be cut in half by a boundary.
;
; **What made it cheap was already in the language.** `split` counts the
; newlines in a chunk, and `join` puts back exactly what `split` removed -- so
; the byte offset of the last few lines *within* a chunk is arithmetic on their
; joined length rather than a second search. What carries across a boundary is
; one integer, `found`, and a line cut in two is simply one whose newline was
; counted in the earlier chunk. Twelve lines, and no state that a reader has to
; hold in their head.
;
; The entry's guess that this shape is *writable in Solum and is the shape
; scan.sol already has* was right about the difficulty and wrong about the
; tool -- `scan.sol` is a cursor over one string and never came into it.
;
; ---------------------------------------------------------------------------
; Clamping was the right call, and two of four call sites need it
;
; `readFile(path, from, count)` answers what was there rather than refusing when
; a range runs past the end. Of the four places this program reads:
;
; - `writeFrom` asks for a whole chunk and takes what comes, every time, and the
;   last chunk of every file is short.
; - `startOfLine` does the same walking forwards.
; - `lastLines` and `lastBytes` compute exact lengths and would not have noticed.
;
; So half of them, and **both of the two that stream**. Had a short range been
; refused, each would have had to ask `fileSize` and take a minimum first --
; the caller re-deriving a number the call already had, at every chunk, with a
; race in the gap. The argument for clamping was a race and the argument holds
; up in use.
;
; **`#0` being refused cost nothing**: no arithmetic here ever produced one, and
; a position that is not a position would have been a defect rather than a
; convenience.
;
; ---------------------------------------------------------------------------
; What it found that is not about files at all
;
; **No arguments means two different things here, and no other program has had
; that.** Every program in this directory runs with no arguments on input it
; carries; `tail` with no arguments is also a real invocation, since `... | tail`
; is how half its uses are typed. The same empty command line, two meanings.
;
; `system:keyWaiting(0.0)` is what separates them and it is **the nearest thing
; this language has to asking whether standard input is a terminal**. It answers
; *is there a byte to read right now*, and it is documented as true at the end of
; input -- so a pipe says true whether it is full or finished, and an idle
; terminal says false. That property is a nuisance in every other program and is
; precisely what was wanted here, which is the second time
; [6.35](../docs/COMPLETED.md#635-a-read-that-gives-up--done) has paid for
; itself in a way its entry did not predict.
;
; **There is no `isatty`**, and this is a program that wanted one and found a
; message that answers the question by accident. Whether that is a gap is a
; question rather than a finding: one caller, and a workaround that is exact
; rather than approximate.
;
; ---------------------------------------------------------------------------
; And a limitation that cost more here than it did last time
;
; [3.2](../docs/ROADMAP.md#32-no-non-local-return), no non-local return.
; [sed.sol](sed.sol) met it and reported that it cost nothing: `d` and `q` are
; early exits and a verdict symbol through a loop is three lines longer than a
; `return`.
;
; **This program met it in a different shape and paid more.** Three of the
; routines here open with a guard -- an empty file, a count of zero, a line
; number of one -- and each is one line in a language with `return`. Here each
; wraps the entire body in an `ifElse` and closes with `}) }` at the far end, so
; the cost is not three lines but three functions indented around a condition
; that has nothing to do with what they compute.
;
; Still small, and still not an argument on its own. It is worth recording
; because it is the third customer for that entry and the first to want the
; *guard* shape rather than the early-exit-from-a-loop shape, and those are
; different things that the entry currently treats as one.
;
; ---------------------------------------------------------------------------
; What is not here, and what it would find
;
; **`-f`.** It is the one part of `tail` with a finding of its own waiting, and
; it is named in [ideas.md](../docs/ideas.md#tail-and-the-file-this-language-cannot-read--scoped-2026-08-31):
; there is no `system:sleep`, and the only thing in this language that waits is
; `keyWaiting`, which waits on standard input and answers true at the end of it
; -- so a follow loop built on it spins at a hundred percent exactly when
; `tail -f` is normally run. The predicted resolution is `shell:run("sleep 1")`,
; a fork per poll, and the finding being the *price* rather than the absence.
;
; It is left out rather than half-built because an oracle cannot check a program
; that does not stop, and a part of this file that nothing checks would be the
; only such part.
