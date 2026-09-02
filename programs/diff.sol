; diff.sol -- two files, and the shortest way to turn one into the other.
;
; Run with:  ./bin/solas programs/diff.sol && ./bin/solvm programs/diff.sob
;
;     solvm diff.sob old.txt new.txt          the normal format: 2c2, 3a4, 1d0
;     solvm diff.sob -u old.txt new.txt       unified, with three lines of context
;     solvm diff.sob -U 5 old.txt new.txt     unified, with five
;     solvm diff.sob -q old.txt new.txt       whether they differ, and nothing else
;     solvm diff.sob -s old.txt new.txt       and say so when they are identical
;     solvm diff.sob -i old.txt new.txt       ignoring case
;     ... | solvm diff.sob old.txt -          the second one from standard input
;
; With no arguments it demonstrates itself on two files it writes, which is the
; house rule for these programs.
;
; Exit status is the tool's: `#0` when they are the same, `#1` when they differ,
; `#2` when something went wrong.
;
; ---------------------------------------------------------------------------
; The twentieth program here, and the first that computes rather than recognises
;
; **The prediction was written before the program**, in
; [ideas.md](../docs/ideas.md#diff--the-first-program-here-that-computes-rather-than-recognises),
; and it is kept there rather than rewritten:
;
; > Everything written so far reads one input and reports on its structure.
; > `diff` holds two and computes a relationship between them.
; >
; > **Predicted findings**, in the order they are expected to bite:
; > [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels), because
; > the divide-and-conquer form of Myers recurses on the halves of the edit graph
; > and a large file has many; a two-dimensional array, which nothing here has
; > needed and which is an array of arrays with a send per index; and memory at
; > scale, where the classic table is quadratic and the linear-space refinement
; > is the interesting half of the algorithm rather than an optimisation.
; >
; > **It is also the first tool whose *output format* is hard.**
;
; **Three of those four were wrong, and the fourth was right twice over.** The
; account is at the bottom of this file, after the code, along with the two
; things that were found instead and that nothing on that page anticipated:
; standard input cannot be read byte-for-byte except one byte at a time, and
; `readFile` on a pipe answers `""` rather than either the contents or an error.
;
; ---------------------------------------------------------------------------
; What is here, and what is not
;
;   -u, -U N     unified, with three lines of context or with N
;   -q           report only whether the files differ
;   -s           say so when they are identical, which is otherwise silent
;   -i           compare without regard to case
;   -            standard input, as either operand
;
; Left out, and each for a reason rather than by running out of patience:
;
;   -r           directories. It is a walk over `filesIn` around this program
;                rather than anything about diffing, and `mirror.sol` already
;                walks a tree here.
;   -c, -e, -n   the older output formats. `-u` and the normal format between
;                them carry every hard part -- hunks, context, coalescing -- and
;                a third spelling of the same edit script teaches nothing.
;   -b, -w       whitespace folding. One line of key-building, and it would make
;                the corpus about `split` rather than about the algorithm.
;   -L           a label for the header, which exists to paper over exactly the
;                timestamp problem this program has to solve properly instead.

; ---------------------------------------------------------------------------
; Options

options := object:new.
options:format := 'normal.          ; 'normal, 'unified or 'brief
options:context := #3.
options:ignoreCase := false.
options:reportIdentical := false.
options:files := nil.

options:number := { text |
    { text:asInteger }:onError({ e |
        error:raise("`{}` is not a number":fill([text])) }) }.

options:read := { args | | i, a, j, c, done, value |
    self:files := array:new.
    i := #1.

    { i:lessOrEqual(args:size) }:whileTrue({
        a := args:at(i).

        ; `--` ends the options, and a bare `-` is standard input rather than
        ; an option with no letters after it. Both are the tool's rules and
        ; both are one line here.
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
                      c:equals("u"):ifTrue({
                          self:format := 'unified. j := j:add(#1) }).
                      c:equals("q"):ifTrue({
                          self:format := 'brief. j := j:add(#1) }).
                      c:equals("s"):ifTrue({
                          self:reportIdentical := true. j := j:add(#1) }).
                      c:equals("i"):ifTrue({
                          self:ignoreCase := true. j := j:add(#1) }).
                      c:equals("U"):ifTrue({
                          ; `-U5` and `-U 5` both, the way every option here
                          ; that takes a number is written.
                          j:lessThan(a:size):ifElse(
                              { value := a:copyFrom(j:add(#1), a:size) },
                              { i := i:add(#1).
                                i:greaterThan(args:size):ifTrue({
                                    error:raise("-U wants a number of lines") }).
                                value := args:at(i) }).
                          self:context := self:number(value).
                          self:context:lessThan(#0):ifTrue({
                              error:raise("-U cannot show a negative number of lines") }).
                          self:format := 'unified.
                          done := true }).

                      ; Anything else is not ours, and saying which is worth
                      ; more than a usage screen.
                      "uqsiU":indexOf(c):isNil:ifTrue({
                          error:raise("unknown option -- {}":fill([c])) }) }).
                  i := i:add(#1) },

                { self:files:add(a). i := i:add(#1) }) }) }).

    self:files:size:equals(#2):not:ifTrue({
        error:raise("two files are wanted, got {}":fill([self:files:size])) }) }.

; ---------------------------------------------------------------------------
; Reading a side
;
; A side is its lines, whether the last of them ended with a newline, and the
; name to print for it. The lines never carry their terminator: a line is what
; is between the newlines, which is what both output formats print and what the
; comparison is about.
;
; **The last line is the whole difficulty.** A file ending `...c` and a file
; ending `...c\n` have the same last line and are not the same file, and every
; diff says so -- `\ No newline at end of file`. So *incomplete* is carried
; beside the lines and folded into the comparison, below.

side := object:new.

; `split` puts an empty string after a trailing separator, which is the piece
; that is not a line. An empty file has no lines at all, where `split` answers
; one empty one -- so that case is taken first rather than trimmed afterwards.
side:linesOf := { text | | parts |
    text:size:equals(#0):ifElse(
        { [array:new, true] },
        { parts := text:split("\n").
          parts:last(#1):at(#1):equals(""):ifElse(
              { [parts:copyFrom(#1, parts:size:sub(#1)), true] },
              { [parts, false] }) }) }.

side:ofFile := { path | | text, split, s |
    text := { system:readFile(path) }:onError({ e |
        error:raise("{}: No such file or directory":fill([path])) }).
    split := self:linesOf(text).
    s := object:new.
    s:lines := split:at(#1).
    s:complete := split:at(#2).
    s:name := path.
    s:stamp := system:modifiedAt(path).
    s }.

; **Standard input is read one byte at a time, and that is not an oversight.**
; `readLine` answers a line *without its terminator* and treats `\r\n` as one --
; so it cannot say whether the last line ended with a newline, and it silently
; rewrites a file written on another system. Both matter to a program whose
; whole job is to report what two files hold, byte for byte.
;
; `readFile("/dev/stdin")` is the shortcut it looks like and is not: on a pipe
; it answers `""`, silently. The account is at the bottom.
;
; The price is measured and is 20x: 4.2 MB a second against 84, or 238
; nanoseconds a byte. That is the cost of being exact about the one byte at the
; end of the input, and it is paid.
side:ofStdin := { | parts, c, split, s |
    parts := array:new.
    c := system:readKey.
    { c:notNil }:whileTrue({ parts:add(c). c := system:readKey }).
    split := self:linesOf(parts:join("")).
    s := object:new.
    s:lines := split:at(#1).
    s:complete := split:at(#2).
    s:name := "-".
    ; Standard input has no modification time, so both diffs stamp it with the
    ; moment they ran. This is why a `-u` case reading a pipe cannot be held
    ; against its own file route in the corpus.
    s:stamp := system:time.
    s }.

side:read := { name |
    name:equals("-"):ifElse({ self:ofStdin }, { self:ofFile(name) }) }.

; ---------------------------------------------------------------------------
; The comparison key, and the trick that makes the last line ordinary
;
; A key is what the algorithm compares, and it is the line's text -- lowercased
; under `-i`, which is the whole of what that option is.
;
; **An incomplete last line gets a newline appended to its key.** No line can
; contain one, since a newline is what the lines were split on, so the marker
; cannot collide with anything: two incomplete last lines with the same text
; agree, an incomplete one and a complete one do not, and every other line is
; untouched. The alternative was a second condition inside the innermost loop
; of the algorithm, run once per character comparison, to ask a question whose
; answer is fixed before the loop starts.

keysOf := { s | | keys, n |
    keys := s:lines:collect({ line |
        options:ignoreCase:ifElse({ line:asLowercase }, { line }) }).
    n := keys:size.
    n:greaterThan(#0):and({ s:complete:not }):ifTrue({
        keys:atPut(n, keys:at(n):concat("\n")) }).
    keys }.

; ---------------------------------------------------------------------------
; Myers, and why this shape rather than the one that was predicted
;
; **An Algorithm for Differential File Comparison** (Myers, 1986) walks an edit
; graph diagonally: for each edit distance `d` in turn, it records how far along
; each diagonal `k` a path of exactly `d` edits can reach. The first `d` that
; reaches the far corner is the number of edits, and the answer is minimal
; because `d` was counted upwards.
;
; The greedy forward pass is here rather than the linear-space divide and
; conquer, and the reason is worth stating because
; [ideas.md](../docs/ideas.md) predicted the other one:
;
; - **It is the shape a diff actually has.** The recursion buys memory, which
;   is not what was scarce, and costs the trace -- which is what the output is
;   reconstructed from.
; - **It is iterative**, so [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels)
;   never comes near it. That is the first of the three predicted findings not
;   to fire, and the entry's own reasoning is what rules it out: the recursion
;   was a property of the variant, not of the problem.
;
; `v` holds one integer per diagonal, `k` running from `-max` to `max`. Solum
; arrays are one-based and diagonals are not, so `k` is stored at
; `k + max + 1` throughout -- written out at each use rather than hidden behind
; a method, since a send in this loop is the loop.

myers := object:new.

; The state of `v` on entry to each step, which is what the path is read back
; out of. Only the band `-d..d` can have been written by step `d`, so that is
; what is kept -- the rest of `v` is the previous step's and would be copied for
; nothing. The trace is therefore `d` entries of `2d+1`, which is quadratic in
; the number of *edits* rather than in the size of the files.
myers:script := { aKeys, bKeys | | n, m, max, off, v, trace, d, k, x, y, done,
                                   band, ops, prevK, prevX, prevY, i |
    n := aKeys:size.
    m := bKeys:size.
    max := n:add(m).

    ; `v` carries one diagonal more than the algorithm can reach at each end,
    ; for the same reason the bands below do: the snapshot reads the two
    ; neighbours of the band's edge, and at the last step -- `d` equal to
    ; `max`, which is what two files with nothing in common cost -- the lower
    ; of those is one before the first diagonal. Found by the corpus on its
    ; first run, by the three cases where the edit distance is the whole of
    ; both files.
    off := max:add(#2).

    v := array:new.
    max:add(#1):mul(#2):add(#1):repeat({ v:add(#0) }).
    trace := array:new.

    d := #0.
    done := false.
    { done:not:and({ d:lessOrEqual(max) }) }:whileTrue({
        ; One diagonal wider than the step can reach, at each end. The
        ; neighbour a path arrives from is `k+1` or `k-1`, and at the edge of
        ; the band one of those is outside it -- so the band carries the two
        ; that were never written, holding what `v` holds, which is what a
        ; full-width copy would have handed back anyway. Found by the first
        ; run: at `d` of zero the band was one entry and the lookup asked for
        ; the second.
        band := array:new.
        [d:negated:sub(#1), d:add(#1)]:loop({ kk |
            band:add(v:at(kk:add(off))) }).
        trace:add(band).

        k := d:negated.
        { done:not:and({ k:lessOrEqual(d) }) }:whileTrue({
            ; Which of the two neighbours the path arrives from: down when the
            ; diagonal below reaches further, right otherwise. The two edge
            ; cases are the ends of the band, where only one neighbour exists.
            (k:equals(d:negated):or({ k:notEquals(d):and({
                v:at(k:sub(#1):add(off)):lessThan(v:at(k:add(#1):add(off))) }) }))
                :ifElse(
                { x := v:at(k:add(#1):add(off)) },
                { x := v:at(k:sub(#1):add(off)):add(#1) }).
            y := x:sub(k).

            ; The snake: every line the two sides agree on from here costs
            ; nothing, so it is taken before the next edit is considered.
            { x:lessThan(n):and({ y:lessThan(m) })
                :and({ aKeys:at(x:add(#1)):equals(bKeys:at(y:add(#1))) }) }
                :whileTrue({ x := x:add(#1). y := y:add(#1) }).

            v:atPut(k:add(off), x).
            x:greaterOrEqual(n):and({ y:greaterOrEqual(m) }):ifTrue({
                done := true }).
            k := k:add(#2) }).
        done:not:ifTrue({ d := d:add(#1) }) }).

    ; ---------------------------------------------------------------------
    ; Reading the path back out
    ;
    ; From the far corner, one step of `d` at a time. At each step the same
    ; question decides where the path came from, asked of the `v` that was
    ; current then; the snake between is unchanged lines, and the one edit is a
    ; deletion when the diagonal moved right and an insertion when it moved
    ; down.
    ;
    ; The operations come out backwards and are reversed once at the end, which
    ; is cheaper than inserting at the front of an array `n` times and is the
    ; only place this program keeps a list it has to turn around.
    ops := array:new.
    x := n.
    y := m.
    { d:greaterOrEqual(#0) }:whileTrue({
        band := trace:at(d:add(#1)).
        k := x:sub(y).
        (k:equals(d:negated):or({ k:notEquals(d):and({
            band:at(k:add(d):add(#1)):lessThan(
                band:at(k:add(d):add(#3))) }) }))
            :ifElse(
            { prevK := k:add(#1) },
            { prevK := k:sub(#1) }).
        prevX := band:at(prevK:add(d):add(#2)).
        prevY := prevX:sub(prevK).

        { x:greaterThan(prevX):and({ y:greaterThan(prevY) }) }:whileTrue({
            ops:add('same). x := x:sub(#1). y := y:sub(#1) }).

        d:greaterThan(#0):ifTrue({
            x:equals(prevX):ifElse(
                { ops:add('insert) },
                { ops:add('delete) }) }).
        x := prevX.
        y := prevY.
        d := d:sub(#1) }).

    ; Reversed in place, which is one pass and no second array.
    i := #1.
    { i:lessThan(ops:size:sub(i):add(#2)) }:whileTrue({ | j, t |
        j := ops:size:sub(i):add(#1).
        t := ops:at(i). ops:atPut(i, ops:at(j)). ops:atPut(j, t).
        i := i:add(#1) }).
    ops }.

; ---------------------------------------------------------------------------
; From operations to changes
;
; A change is `[fromA, toA, fromB, toB]`, one-based and inclusive, and an empty
; range is written with its end one before its start -- so a pure insertion has
; `toA` one less than `fromA` and needs no separate representation. That is what
; makes the three normal-format spellings below one condition each rather than
; three shapes.
;
; A change is a maximal run of operations with no agreement in it. The `d`, `a`
; and `c` of the normal format are which of the two ranges turned out empty.

changesOf := { ops | | changes, i, x, y, fromA, fromB |
    changes := array:new.
    i := #1.
    x := #0.
    y := #0.
    { i:lessOrEqual(ops:size) }:whileTrue({
        ops:at(i):equals('same):ifElse(
            { x := x:add(#1). y := y:add(#1). i := i:add(#1) },
            { fromA := x:add(#1).
              fromB := y:add(#1).
              { i:lessOrEqual(ops:size)
                  :and({ ops:at(i):notEquals('same) }) }:whileTrue({
                  ops:at(i):equals('delete):ifElse(
                      { x := x:add(#1) },
                      { y := y:add(#1) }).
                  i := i:add(#1) }).
              changes:add([fromA, x, fromB, y]) }) }).
    changes }.

; ---------------------------------------------------------------------------
; Printing

report := object:new.

report:range := { from, to |
    from:equals(to):ifElse(
        { from:asString },
        { "{},{}":fill([from, to]) }) }.

; The marker goes after a line that is the last of a file which does not end
; with a newline. It is a statement about the *file*, printed under whichever
; line happens to be its last, which is why both formats ask the same question
; in the same words.
report:incomplete := { s, i |
    s:complete:not:and({ i:equals(s:lines:size) }):ifTrue({
        "\\ No newline at end of file":display }) }.

report:normal := { a, b, changes |
    changes:do({ c | | fromA, toA, fromB, toB |
        fromA := c:at(#1). toA := c:at(#2).
        fromB := c:at(#3). toB := c:at(#4).

        toA:lessThan(fromA):ifTrue({
            "{}a{}":fill([fromA:sub(#1), self:range(fromB, toB)]):display }).
        toB:lessThan(fromB):ifTrue({
            "{}d{}":fill([self:range(fromA, toA), fromB:sub(#1)]):display }).
        toA:greaterOrEqual(fromA):and({ toB:greaterOrEqual(fromB) }):ifTrue({
            "{}c{}":fill([self:range(fromA, toA),
                          self:range(fromB, toB)]):display }).

        toA:greaterOrEqual(fromA):ifTrue({
            [fromA, toA]:loop({ i |
                "< ":concat(a:lines:at(i)):display.
                self:incomplete(a, i) }) }).
        toA:greaterOrEqual(fromA):and({ toB:greaterOrEqual(fromB) }):ifTrue({
            "---":display }).
        toB:greaterOrEqual(fromB):ifTrue({
            [fromB, toB]:loop({ i |
                "> ":concat(b:lines:at(i)):display.
                self:incomplete(b, i) }) }) }) }.

; ---------------------------------------------------------------------------
; The unified format, which is where the prediction was right
;
; **Two changes belong to the same hunk when the unchanged run between them is
; at most twice the context**, because at any more the two context blocks would
; not touch and the hunk would be printing lines it had no reason to. Measured
; against the tool rather than reasoned about: a gap of six merges and a gap of
; seven does not, with three lines of context.
;
; The header's counts are the lines *printed*, not the lines changed, and a
; count of one is written without its comma. An empty side is written as the
; position it would go after, with a count of zero -- `@@ -0,0 +1 @@` for a line
; added to an empty file, which is the one place a line number here is allowed
; to be zero.

report:header := { from, count, lines | | at |
    count:equals(#0):ifElse(
        { ; An empty range is written at the line it follows -- **except at the
          ; start of a file that has lines, where it is written at line 1
          ; rather than at line 0.** That is not arithmetic and was not
          ; guessed: a random sweep against the tool disagreed on it 44 times
          ; in 1050 runs, and the seven probes that followed are the only
          ; reason this line reads the way it does. `0` is reserved for a file
          ; with nothing in it.
          at := from:sub(#1).
          at:lessThan(#1):and({ lines:greaterThan(#0) }):ifTrue({ at := #1 }).
          "{},0":fill([at]) },
        { count:equals(#1):ifElse(
            { from:asString },
            { "{},{}":fill([from, count]) }) }) }.

; The stamp a header carries is the file's modification time in **local** time,
; which is what every diff prints and what this language cannot produce: an
; instant formats in UTC and there is no message for the offset. So the offset
; is asked of the machine once, and added.
;
; **Once, rather than per file**, and that is a real limitation rather than a
; shortcut: the offset is the one in force *now*, so a file stamped on the other
; side of a daylight-saving change is printed an hour out. Asking `date` per
; file would fix it and would be two forks instead of one to work around a gap
; that should not be worked around at all. The account is at the bottom.
report:offset := nil.

report:localOffset := { | z, sign, minutes |
    self:offset:isNil:ifTrue({
        z := { system:capture(["date", "+%z"]):at("output"):trim }
                 :onError({ e | "+0000" }).
        self:offset := { sign := z:copyFrom(#1, #1):equals("-")
                                     :ifElse({ #-1 }, { #1 }).
                         minutes := z:copyFrom(#2, #3):asInteger:mul(#60)
                                        :add(z:copyFrom(#4, #5):asInteger).
                         sign:mul(minutes):mul(#60) }
                       :onError({ e | #0 }) }).
    self:offset }.

report:stamp := { s |
    s:stamp:plusSeconds(self:localOffset:asFloat)
        :asString("%Y-%m-%d %H:%M:%S") }.

report:unified := { a, b, changes | | context, hunks, current, last |
    context := options:context.

    ; Grouping first, so that the printing below never has to look ahead.
    hunks := array:new.
    current := nil.
    changes:do({ c |
        current:isNil:ifTrue({ current := array:new }).
        current:size:greaterThan(#0):ifTrue({
            last := current:last(#1):at(#1).
            ; The gap is the unchanged lines between the end of one change and
            ; the start of the next, counted in the first file -- which is the
            ; same number in the second, since unchanged lines are shared.
            c:at(#1):sub(last:at(#2)):sub(#1)
                :greaterThan(context:mul(#2)):ifTrue({
                hunks:add(current).
                current := array:new }) }).
        current:add(c) }).
    current:isNil:not:and({ current:size:greaterThan(#0) }):ifTrue({
        hunks:add(current) }).

    "--- {}\t{}":fill([a:name, self:stamp(a)]):display.
    "+++ {}\t{}":fill([b:name, self:stamp(b)]):display.

    hunks:do({ hunk | | first, final, fromA, toA, fromB, toB, ax, bx |
        first := hunk:at(#1).
        final := hunk:last(#1):at(#1).

        fromA := first:at(#1):sub(context).
        fromA:lessThan(#1):ifTrue({ fromA := #1 }).
        toA := final:at(#2):add(context).
        toA:greaterThan(a:lines:size):ifTrue({ toA := a:lines:size }).

        fromB := first:at(#3):sub(context).
        fromB:lessThan(#1):ifTrue({ fromB := #1 }).
        toB := final:at(#4):add(context).
        toB:greaterThan(b:lines:size):ifTrue({ toB := b:lines:size }).

        "@@ -{} +{} @@":fill([
            self:header(fromA, toA:sub(fromA):add(#1), a:lines:size),
            self:header(fromB, toB:sub(fromB):add(#1), b:lines:size)]):display.

        ax := fromA.
        bx := fromB.
        hunk:do({ c |
            { ax:lessThan(c:at(#1)) }:whileTrue({
                " ":concat(a:lines:at(ax)):display.
                ; A shared last line is the last line of both, so the marker is
                ; asked of each and printed at most once -- the second ask is
                ; false whenever the first was true.
                self:incomplete(a, ax).
                a:complete:ifTrue({ self:incomplete(b, bx) }).
                ax := ax:add(#1). bx := bx:add(#1) }).
            [c:at(#1), c:at(#2)]:loop({ i |
                "-":concat(a:lines:at(i)):display.
                self:incomplete(a, i) }).
            ax := c:at(#2):add(#1).
            [c:at(#3), c:at(#4)]:loop({ i |
                "+":concat(b:lines:at(i)):display.
                self:incomplete(b, i) }).
            bx := c:at(#4):add(#1) }).

        { ax:lessOrEqual(toA) }:whileTrue({
            " ":concat(a:lines:at(ax)):display.
            self:incomplete(a, ax).
            a:complete:ifTrue({ self:incomplete(b, bx) }).
            ax := ax:add(#1). bx := bx:add(#1) }) }) }.

; ---------------------------------------------------------------------------
; Running it

diff := object:new.

diff:run := { | a, b, changes |
    a := side:read(options:files:at(#1)).
    b := side:read(options:files:at(#2)).

    changes := changesOf:value(myers:script(keysOf:value(a), keysOf:value(b))).

    changes:size:equals(#0):ifElse(
        { options:reportIdentical:ifTrue({
              "Files {} and {} are identical":fill([a:name, b:name]):display }).
          #0 },
        { options:format:equals('brief):ifTrue({
              "Files {} and {} differ":fill([a:name, b:name]):display }).
          options:format:equals('normal):ifTrue({
              report:normal(a, b, changes) }).
          options:format:equals('unified):ifTrue({
              report:unified(a, b, changes) }).
          #1 }) }.

; ---------------------------------------------------------------------------
; What it does with no arguments
;
; Two files it writes itself, shown both ways, because the two formats are the
; two halves of what this program is: an edit script, and an edit script with
; enough of its surroundings to be applied somewhere else.

demonstrate := { | dir, one, two |
    dir := "build".
    system:makeDirectory(dir).
    one := "build/diff-demo-old.txt".
    two := "build/diff-demo-new.txt".
    system:writeFile(one,
        "the quick brown fox\njumps over\nthe lazy dog\nand keeps going\nto the end\n").
    system:writeFile(two,
        "the quick brown fox\nvaults over\nthe lazy dog\nand keeps going\nto the very end\n").

    "-- the normal format":display.
    options:files := [one, two].
    options:format := 'normal.
    diff:run.

    "":display.
    "-- unified, with one line of context":display.
    options:format := 'unified.
    options:context := #1.
    diff:run.

    "":display.
    "-- and against itself":display.
    options:files := [one, one].
    options:reportIdentical := true.
    diff:run }.

; A failure here is the tool's exit 2, and its message goes to standard error
; where a diagnostic belongs -- the output of a diff is an edit script, and a
; program reading one should not have to tell a complaint from a change.
{ system:arguments:size:equals(#0):ifElse(
    { demonstrate:value },
    { options:read(system:arguments).
      system:exit(diff:run) }) }:onError({ e |
    system:writeError("diff: {}\n":fill([e:message])).
    system:exit(#2) }).

; ---------------------------------------------------------------------------
; What the prediction got right, and the three quarters of it that were wrong
;
; **Kept beside the prediction rather than in place of it.**
; [ideas.md](../docs/ideas.md#diff--the-first-program-here-that-computes-rather-than-recognises)
; named four things. One held, three did not, and the two findings that matter
; are on neither list.
;
; ### 3.5 never came near it, and the entry said why without noticing
;
; **Predicted first and did not fire at all.** The recursion is a property of
; the *linear-space variant*, which the entry named -- "the divide-and-conquer
; form of Myers recurses on the halves of the edit graph" -- and the variant
; buys memory at the cost of the trace the output is read back out of. The
; greedy forward pass is a `whileTrue` over `d` and another over `k`, and the
; deepest this program nests is a block inside a block.
;
; That is the third time an entry here has predicted
; [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels) for a
; program and been wrong, and the shape is the same each time:
; [basic.sol](basic.sol) argued a line-numbered language never nests,
; [check_syntax.sol](check_syntax.sol) replaced its tree walker with an
; instruction set, and [pascal.sol](pascal.sol) compiles rather than walks.
; **A prediction of 3.5 is really a prediction about which implementation gets
; written**, and the one that gets written here is the iterative one, because
; the limitation is known before the choice is made.
;
; ### The two-dimensional array was not needed either
;
; **Predicted second, and the algorithm that wants one is the algorithm nobody
; writes.** The quadratic table is the textbook LCS and no diff uses it. Myers
; keeps *one* array of diagonals, `v`, and a trace of the bands it passed
; through -- which is an array of arrays, but a ragged one, and a ragged array
; of increasing lengths is not the two-dimensional array the entry meant.
;
; The one place it bites is the one the entry did not name: **`k` runs from
; `-max` to `max` and Solum arrays are one-based**, so every access is written
; `v:at(k:add(off))`. Three sends where C writes `v[k + off]`, in the innermost
; loop of the program. It is not awkward, it is loud -- the offset is visible at
; every use, which is the same trade the language makes everywhere else.
;
; ### Memory at scale is real and is not where the entry put it
;
; **Predicted third, and half right.** The classic table is quadratic in the
; *files*; the trace here is quadratic in the *edits*, `d` bands of `2d+1`. Two
; files of ten thousand lines differing in one line cost one band of one. Two
; files with nothing in common cost the whole triangle, and that is the real
; wall: `d` is bounded by `n + m`, so a complete rewrite of a ten-thousand-line
; file is a hundred million integers and does not run here.
;
; **That is the same bound every diff has** and is why real ones give up early
; on a large `d` rather than answer minimally. Not implemented, and the reason
; is that it would be a heuristic held against a tool with a *different*
; heuristic, which is a corpus of divergences rather than of agreements.
;
; ### The output format was the hard part, exactly as predicted
;
; **The one that held, and it was the whole of it.** The algorithm was right on
; its first run against the corpus. The *format* was wrong four times:
;
; - a count of one is written `@@ -1 +1 @@` and not `@@ -1,1 +1,1 @@`;
; - two changes merge into one hunk at a gap of exactly twice the context, and
;   split at one more -- six and seven, measured against the tool;
; - `\ No newline at end of file` follows a *context* line too, once, when the
;   shared last line is the last line of both;
; - and an empty range is written at the line it follows, **except at the start
;   of a file that has lines**, where it is written at line 1 rather than at
;   line 0. `0` is kept for a file with nothing in it.
;
; Not one of those is discoverable by reading the algorithm.
;
; **Three of the four were found by the corpus and the fourth was not**, which
; is the part worth carrying. The empty-range rule was wrong in a way sixteen
; hand-written cases all agreed with, because every one of them put its empty
; range where the simple rule and the real one give the same answer. A random
; sweep against the tool -- pairs of files built from nine possible lines, run
; under seven option forms -- disagreed **44 times in 1,050 runs**, and seven
; probes afterwards were what turned the disagreement into a rule. Nothing an
; author writes on purpose lands on the exception; the exception is what a
; generator finds by not knowing there is one.
;
; **After the fix: 2,400 runs, six option forms, files up to forty lines, zero
; disagreements.** That is a stronger statement than the corpus can make and a
; weaker one than it looks: it says nothing about inputs this generator cannot
; produce, and `-i` is excluded from it, for the reason below.
;
; ### And the sentence above was written an hour before the first real file
;
; **The first pair of real files disagreed** -- this repository's own
; `docs/method.md` at two revisions -- and the sweep had said nothing, twice
; over.
;
; Where a line inside an inserted block equals the line at the seam, the
; insertion can be placed as one run or split around that line, and **both are
; the same number of edits.** The tool splits and this program does not.
; [programs/diff/apply.sh](diff/apply.sh) puts a number on it: over sixty pairs
; of real files at two revisions, **48 are byte-identical to the tool and 12 are
; not, and in every one of the 12 the two answers have the same edit count.**
;
; **The generator could not have found it and neither could the corpus.** The
; sweep mutates one line at a time, and the shape needed is a *block* inserted
; whole where a line inside it matches the seam -- which is what editing prose
; does every time and what nobody constructs on purpose. And it does not reduce:
; no window of thirty lines either side reproduces it, because the tool's
; algorithm makes a global choice. **So it cannot be a corpus case**, which is
; why `apply.sh` exists.
;
; This is [an enumeration that looks complete is not a
; proof](../docs/method.md#an-enumeration-that-looks-complete-is-not-a-proof)
; happening to the sweep that was written *because* the corpus had the same
; problem. Two authors, both blind in the same direction, and the thing that
; saw past them was a file somebody had actually edited.
;
; ### So the check that matters is not byte equality
;
; **`patch(1)` is a third judge and it does not care which minimal script it is
; handed.** [apply.sh](diff/apply.sh) writes our unified diff, applies it, and
; compares the result with the second file: **60 of 60 real pairs reproduced it
; exactly.** That is the property -- *is this the diff from A to B* -- where the
; oracle answers *is this the tool's diff*, and the second question stopped
; being the interesting one the moment two right answers turned up.
;
; ### And the tool disagrees with itself under `-i`
;
; **Held as a divergence rather than chased**, in
; `programs/diff/differ/ignore-case-ties.case`. One line `h` against three lines
; `c h h` has two minimal answers, both two insertions:
;
; ```text
; 0a1,2   > c   > h            both inserted before the shared line
; 0a1     > c   1a3   > h      one before it and one after
; ```
;
; The tool prints the first under `-i` and the second without it, **on input
; holding no uppercase at all**, where case folding cannot change a single
; comparison. This program prints the second either way, which is what `-i`
; means: fold the comparison and change nothing else.
;
; It is 41 runs in 400 of the sweep under `-i` and none without it, and matching
; it would mean reproducing a tie-break the oracle does not apply consistently
; to itself. **An oracle can be wrong, and this is the first time one here has
; been caught being two things at once.**
;
; It is also **not** the only divergence, which a first draft of this file said
; it was -- see above. The `-i` one is the only one a *generator* found.
;
; ---------------------------------------------------------------------------
; And two things nothing predicted, both about standard input
;
; ### Reading a pipe byte-for-byte costs 20x, and there is no other way
;
; `readLine` is the obvious way to read standard input and this program cannot
; use it, for two reasons that are the same reason: **it answers a line without
; its terminator, and treats `\r\n` as one terminator.** So it cannot say
; whether the last line ended with a newline -- which is the one thing `\ No
; newline at end of file` exists to report -- and it silently rewrites a file
; written on another system into one that was not.
;
; `readKey` is exact and is a byte at a time. Measured over 628,890 bytes:
;
; | reading standard input | takes | is |
; | --- | --- | --- |
; | `readLine`, a line at a time | 0.0075 s | 84 MB/s |
; | `readKey`, a byte at a time | 0.1498 s | 4.2 MB/s, 238 ns a byte |
;
; **20x, and it is paid**, because a diff that cannot tell those two files
; apart is wrong rather than slow. What is missing is not a way to read a pipe
; -- there are two -- but a way to read one *whole*, the way `readFile` reads a
; file: the fast route normalises and the exact route is a send per byte.
;
; ### `readFile` on a pipe answers `""`, and says nothing
;
; The obvious workaround for the above is `readFile("/dev/stdin")`, and it
; works -- from a redirect. From a pipe it answers the empty string:
;
; ```text
; solvm prog.sob < big.txt           #628890
; cat big.txt | solvm prog.sob       #0
; ```
;
; **Neither the contents nor an error.** `prim_system_read_file` sizes the file
; with `fseeko(SEEK_END)` and `ftello`, and on a pipe the seek fails, leaving
; `size` at its initial `0` -- which is then indistinguishable from an empty
; file, and takes the `want == 0` path that answers `""` before any read is
; attempted. The function already refuses a directory and already checks for a
; negative size; a *failed seek* is the case between them that nothing looks at.
;
; This is the same shape as
; [a path with a NUL in it](../docs/ideas.md#a-path-with-a-nul-in-it-is-silently-a-different-path),
; found on 2026-08-31: not a missing feature but a **silent wrong answer**, and
; found the same way, by a program with a reason to try the thing nobody had
; tried. It is the one finding here that is a defect rather than a limitation.
