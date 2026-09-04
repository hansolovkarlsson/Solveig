; sort.sol -- lines in order, and a file bigger than the memory to hold it.
;
; Run with:  ./bin/solas programs/sort.sol && ./bin/solvm programs/sort.sob
;
;     solvm sort.sob names.txt              in byte order
;     solvm sort.sob -n scores.txt          by the number each line starts with
;     solvm sort.sob -r -u names.txt        descending, one of each
;     solvm sort.sob -t: -k2,2n /etc/passwd by the second colon field, numerically
;     solvm sort.sob -c names.txt           say whether it is already sorted
;     solvm sort.sob -m a.txt b.txt         merge two files that already are
;     solvm sort.sob -S 4096 huge.txt       hold 4 KB at a time and spill the rest
;     ... | solvm sort.sob                  from a pipe
;
; With no arguments it demonstrates itself on a file it writes, which is the
; house rule for these programs.
;
; **Byte order, always.** `LC_ALL=C` is what the tool on the machine has to be
; run under to agree with this, and that is not a limitation being apologised
; for: a string here is bytes ([2.13](../docs/ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only)),
; `lessThan` compares them, and a collation table is a different program.
;
; ---------------------------------------------------------------------------
; The twenty-first program here, and the first that cannot hold its input
;
; **The prediction was written before the program**, in
; [ideas.md](../docs/ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31),
; and it is kept there rather than rewritten:
;
; > **`sort`.** `array:sorted(block)` at scale, and its stability, which nothing
; > has had to care about. **Its real finding is predicted to be a gap we
; > already know about and nothing has wanted**: an external merge sort writes
; > runs to temporary files and merges them, and there is no positioned write —
; > `writeFile` replaces and `appendFile` appends. That is the mirror of the
; > ranged read built this morning, and `sort` would be its first customer.
;
; **The predicted gap is not there, and the reason is worth more than the
; prediction was.** An external merge sort never writes into the middle of a
; file: it writes each run once, whole, and then reads the runs back. The
; account is at the bottom of this file, with what it found instead -- which
; came from the sweep over real files rather than from anything predicted, and
; with the one claim this program nearly published and had to take back.
;
; ---------------------------------------------------------------------------
; What is here, and what is not
;
;   -r           descending
;   -n           by the number a field begins with
;   -u           one line per distinct key
;   -f           fold case before comparing
;   -b           ignore the blanks a field begins with
;   -s           stable: no last-resort comparison, and ties keep their order
;   -c           check rather than sort; exit 1 and name the first line out of place
;   -t SEP       fields are separated by SEP rather than by blanks
;   -k F[,F][nrbf]  compare by fields, several times over, in the order given
;   -o FILE      write there rather than to standard output, `-o in.txt` included
;   -m           the inputs are sorted already; merge them
;   -S BYTES     hold at most this much in memory and spill the rest to runs
;
; Left out, and each for a reason:
;
;   -k F.C       a character offset inside a field. The field machinery is the
;                interesting half and the offset is arithmetic on top of it; it
;                is refused by name rather than misread, and there is a case in
;                `differ/` saying so.
;   -h -V -R     human sizes, version numbers, a random hash. Three more
;                comparison functions against the same key machinery.
;   -z           NUL-terminated records. `split` would do it in one line and
;                nothing here produces them.
;   collation    see the note above.

@include "text.sol".

; ---------------------------------------------------------------------------
; Options

options := object:new.
options:reverse := false.
options:numeric := false.
options:unique := false.
options:foldCase := false.
options:ignoreBlanks := false.
options:stable := false.
options:checkOnly := false.
options:mergeOnly := false.
options:separator := nil.           ; nil means blanks
options:keys := array:new.          ; key specs; empty means the whole line
options:output := nil.
options:budget := #16777216.        ; -S, in bytes; 16 MB before spilling
options:files := nil.

; A key spec is `[fromField, toField, numeric, reverse, blanks, fold]`, with
; `toField` nil for *to the end of the line*. The four flags are the modifiers
; that may follow the fields, each of which turns its global option on for this
; key alone -- never off, which is what the tool does and is the only reading
; that makes `-n -k2,2` and `-k2,2n` agree.
options:key := { text | | body, from, to, at, mods, spec, digits |
    body := text.
    mods := "".
    at := #1.
    ; The point is taken as part of the fields rather than as a modifier, so
    ; that `-k1.2` reaches the refusal below and is told what is wrong with it
    ; rather than being told `.2` is not a modifier. Found by the corpus case
    ; written to pin the refusal, which is the case earning its keep before the
    ; feature it refuses ever existed.
    digits := "0123456789,.".
    { at:lessOrEqual(body:size)
        :and({ digits:indexOf(body:at(at)):notNil }) }:whileTrue({
        at := at:add(#1) }).
    at:lessOrEqual(body:size):ifTrue({
        mods := body:copyFrom(at, body:size).
        body := body:copyFrom(#1, at:sub(#1)) }).

    body:indexOf("."):notNil:ifTrue({
        error:raise("a character offset in `-k` is not supported: {}"
                        :fill([text])) }).

    spec := body:split(",").
    spec:size:greaterThan(#2):ifTrue({
        error:raise("`-k {}` names more than a start and an end":fill([text])) }).
    from := { spec:at(#1):asInteger }:onError({ e |
        error:raise("`-k {}` does not start with a field number":fill([text])) }).
    from:lessThan(#1):ifTrue({
        error:raise("`-k {}` starts at field {}, and fields start at 1"
                        :fill([text, from])) }).
    to := spec:size:equals(#2):ifElse(
        { { spec:at(#2):asInteger }:onError({ e |
              error:raise("`-k {}` does not end with a field number"
                              :fill([text])) }) },
        { nil }).

    ; Every modifier character, rather than the first: `-k2,2nr` is two of them
    ; and `-k2,2x` has to be refused rather than half-read.
    [#1, mods:size]:loop({ m |
        "nrbf":indexOf(mods:at(m)):isNil:ifTrue({
            error:raise("`-k {}` has a modifier that is not one of n, r, b or f"
                            :fill([text])) }) }).

    [from, to,
     mods:indexOf("n"):notNil, mods:indexOf("r"):notNil,
     mods:indexOf("b"):notNil, mods:indexOf("f"):notNil] }.

options:read := { args | | i, a, j, c, done, value |
    self:files := array:new.
    self:keys := array:new.
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
                      c:equals("r"):ifTrue({ self:reverse := true. j := j:add(#1) }).
                      c:equals("n"):ifTrue({ self:numeric := true. j := j:add(#1) }).
                      c:equals("u"):ifTrue({ self:unique := true. j := j:add(#1) }).
                      c:equals("f"):ifTrue({ self:foldCase := true. j := j:add(#1) }).
                      c:equals("b"):ifTrue({ self:ignoreBlanks := true. j := j:add(#1) }).
                      c:equals("s"):ifTrue({ self:stable := true. j := j:add(#1) }).
                      c:equals("c"):ifTrue({ self:checkOnly := true. j := j:add(#1) }).
                      c:equals("m"):ifTrue({ self:mergeOnly := true. j := j:add(#1) }).

                      ; The four that take a value, which may be joined to the
                      ; letter or be the next argument -- `-t:` and `-t :` both.
                      "tkoS":indexOf(c):notNil:ifTrue({
                          j:lessThan(a:size):ifElse(
                              { value := a:copyFrom(j:add(#1), a:size) },
                              { i := i:add(#1).
                                i:greaterThan(args:size):ifTrue({
                                    error:raise("-{} wants a value":fill([c])) }).
                                value := args:at(i) }).
                          c:equals("t"):ifTrue({
                              value:size:equals(#1):ifFalse({
                                  error:raise("-t wants one character, got `{}`"
                                                  :fill([value])) }).
                              self:separator := value }).
                          c:equals("k"):ifTrue({ self:keys:add(self:key(value)) }).
                          c:equals("o"):ifTrue({ self:output := value }).
                          c:equals("S"):ifTrue({
                              self:budget := { value:asInteger }:onError({ e |
                                  error:raise("-S wants a number of bytes, got `{}`"
                                                  :fill([value])) }).
                              self:budget:lessThan(#1):ifTrue({
                                  error:raise("-S cannot hold {} bytes"
                                                  :fill([self:budget])) }) }).
                          done := true }).

                      "rnufbscmtkoS":indexOf(c):isNil:ifTrue({
                          error:raise("unknown option -- {}":fill([c])) }) }).
                  i := i:add(#1) },

                { self:files:add(a). i := i:add(#1) }) }) }).

    self:files:size:equals(#0):ifTrue({ self:files:add("-") }) }.

; ---------------------------------------------------------------------------
; Fields, which is where the fiddliness lives
;
; **A field carries the blanks in front of it**, and that is not a quirk to be
; tidied away: `-k2,2` over `a   z` and `a  y` compares `"   z"` against
; `"  y"`, so the *wider* gap sorts first because a space is less than a letter.
; `-b` is what says to skip them, and the pair of cases in the corpus is the
; only reason this paragraph is right.
;
; With `-t` there are no blanks in it: the line is cut at each separator and the
; separator belongs to neither side, so `a::b` has three fields and the middle
; one is empty.

fieldsOf := { line |
    options:separator:isNil:ifElse(
        { | out, i, size, start |
          ; Each field is the blanks before it and the non-blanks after, which
          ; is one pass with two inner walks rather than a split.
          out := array:new.
          size := line:size.
          i := #1.
          { i:lessOrEqual(size) }:whileTrue({
              start := i.
              { i:lessOrEqual(size)
                  :and({ line:at(i):equals(" "):or({ line:at(i):equals("\t") }) })
                  }:whileTrue({ i := i:add(#1) }).
              { i:lessOrEqual(size)
                  :and({ line:at(i):equals(" "):or({ line:at(i):equals("\t") })
                             :not }) }:whileTrue({ i := i:add(#1) }).
              out:add(line:copyFrom(start, i:sub(#1))) }).
          out },
        { line:split(options:separator) }) }.

; The text a key spec names: field `from` to field `to`, joined back together
; with what separated them -- which for the blank case is nothing, since the
; blanks are already inside the fields.
;
; **A field that is not there is the empty string** rather than an error, which
; is what the tool does with `-k3` on a two-field line and is what makes a key
; usable on ragged input at all.
keyOf := { line, spec | | fields, from, to, out, i |
    fields := fieldsOf:value(line).
    from := spec:at(#1).
    to := spec:at(#2):isNil:ifElse({ fields:size }, { spec:at(#2) }).
    to:greaterThan(fields:size):ifTrue({ to := fields:size }).
    from:greaterThan(fields:size):or({ to:lessThan(from) }):ifElse(
        { "" },
        { out := array:new.
          [from, to]:loop({ i | out:add(fields:at(i)) }).
          out:join(options:separator:isNil:ifElse({ "" },
                                                  { options:separator })) }) }.

; ---------------------------------------------------------------------------
; The number a line begins with
;
; **`asFloat` is strict and this cannot be**, which is the second time a program
; here has wanted a lenient numeric read -- `awk` predicted it first and was not
; written on it. What the tool reads is: blanks, then a sign, then digits, then
; a point and more digits. **No exponent and no hex**: `1e3` is one and `0x10`
; is zero, measured rather than assumed, and anything with no digits at all is
; zero as well.
;
; So the reading is written out here, and it is nine lines. That is the whole
; cost of the gap for this program, and it is worth stating because the entry it
; would open should not be opened on nine lines.
numberOf := { text | | i, size, sign, digits, seenPoint, out |
    size := text:size.
    i := #1.
    { i:lessOrEqual(size)
        :and({ text:at(i):equals(" "):or({ text:at(i):equals("\t") }) })
        }:whileTrue({ i := i:add(#1) }).
    ; **A minus and not a plus.** The tool reads `-1` as minus one and `+5` as
    ; *zero* -- so `+5` sorts with the unreadable lines and the last resort puts
    ; it before `3`, because `+` is less than `3` in bytes. Found by sorting this
    ; repository's own README, where a line begins `+0.2% to +3.4%`; the
    ; generated half of the sweep never produced a leading plus because nobody
    ; thought to put one in the alphabet.
    sign := 1.0.
    i:lessOrEqual(size):and({ text:at(i):equals("-") }):ifTrue({
        sign := -1.0.
        i := i:add(#1) }).
    digits := "".
    seenPoint := false.
    { i:lessOrEqual(size)
        :and({ "0123456789":indexOf(text:at(i)):notNil
                   :or({ text:at(i):equals("."):and({ seenPoint:not }) }) })
        }:whileTrue({
        text:at(i):equals("."):ifTrue({ seenPoint := true }).
        digits := digits:concat(text:at(i)).
        i := i:add(#1) }).
    out := (digits:equals(""):or({ digits:equals(".") })):ifElse(
        { 0.0 },
        { { digits:asFloat }:onError({ e |
              ; A run of digits with a point at one end -- `3.` or `.5` -- which
              ; `asFloat` refuses and every sort reads.
              { digits:concat("0"):asFloat }:onError({ e2 |
                  { "0":concat(digits):asFloat }:onError({ e3 | 0.0 }) }) }) }).
    sign:mul(out) }.

; ---------------------------------------------------------------------------
; Comparing
;
; One key at a time, in the order they were given, and the first that decides
; wins. **The last resort is the whole line, compared byte for byte** -- and it
; is switched off by `-s` and by `-u`, both measured against the tool: `-s`
; wants ties in input order, and `-u` wants keys rather than lines to be what
; is distinct.
;
; It answers `#-1`, `#0` or `#1` rather than a boolean, because a sort needs
; *less than* and a check and a uniqueness test need *equal*, and deriving one
; from two calls to the other costs a second pass over the keys.

compareText := { a, b, useNumeric |
    useNumeric:ifElse(
        { | x, y |
          x := numberOf:value(a). y := numberOf:value(b).
          x:lessThan(y):ifElse({ #-1 },
              { y:lessThan(x):ifElse({ #1 }, { #0 }) }) },
        { a:lessThan(b):ifElse({ #-1 },
              { b:lessThan(a):ifElse({ #1 }, { #0 }) }) }) }.

; `-b` and `-f` change what is compared rather than how, so they are applied to
; the text before it is handed on.
prepare := { text, blanks, fold | | out, i |
    out := text.
    blanks:ifTrue({
        i := #1.
        { i:lessOrEqual(out:size)
            :and({ out:at(i):equals(" "):or({ out:at(i):equals("\t") }) })
            }:whileTrue({ i := i:add(#1) }).
        out := i:greaterThan(out:size):ifElse({ "" },
                                              { out:copyFrom(i, out:size) }) }).
    ; **Upper, not lower**, and the difference is visible only next to
    ; punctuation: folding down puts `[` (91) below `a` (97) and folding up puts
    ; it above `Z` (90). Measured against the tool, which answers `ab Zb [a`.
    ; The generated half of the sweep never showed it because its alphabet is
    ; letters and digits; three of this repository's own README files did.
    fold:ifTrue({ out := out:asUppercase }).
    out }.

compareLines := { a, b | | verdict |
    verdict := #0.
    options:keys:do({ spec | | ka, kb, useNumeric, useBlanks, useFold, r |
        verdict:equals(#0):ifTrue({
            useNumeric := options:numeric:or({ spec:at(#3) }).
            useBlanks := options:ignoreBlanks:or({ spec:at(#5) }).
            useFold := options:foldCase:or({ spec:at(#6) }).
            ka := prepare:value(keyOf:value(a, spec), useBlanks, useFold).
            kb := prepare:value(keyOf:value(b, spec), useBlanks, useFold).
            r := compareText:value(ka, kb, useNumeric).
            (options:reverse:or({ spec:at(#4) })):ifTrue({ r := r:negated }).
            verdict := r }) }).

    ; No `-k` at all: the whole line is the key, and the last resort would be
    ; the same comparison a second time.
    options:keys:size:equals(#0):ifTrue({
        verdict := compareText:value(
            prepare:value(a, options:ignoreBlanks, options:foldCase),
            prepare:value(b, options:ignoreBlanks, options:foldCase),
            options:numeric).
        options:reverse:ifTrue({ verdict := verdict:negated }) }).

    ; The last resort, on the whole line and in byte order, which `-r` reverses
    ; and `-s` and `-u` switch off.
    ;
    ; **It applies with no `-k` too**, which a first draft got wrong on the
    ; reasoning that the key is then the whole line already. It is not: `-f`
    ; folds it and `-b` strips it, so `Apple` and `apple` tie under `-f` and
    ; the byte comparison is what puts the capital first. Two of the fourteen
    ; smoke tests, and both of them options that change the key rather than
    ; the order.
    verdict:equals(#0)
        :and({ options:stable:not })
        :and({ options:unique:not }):ifTrue({
        verdict := compareText:value(a, b, false).
        options:reverse:ifTrue({ verdict := verdict:negated }) }).
    verdict }.

; What `-u` calls the same line: the keys, without the last resort. When there
; are no keys that is the whole line, which is what `sort -u` means on its own.
sameKey := { a, b |
    options:keys:size:equals(#0):ifElse(
        { compareLines:value(a, b):equals(#0) },
        { | verdict |
          verdict := #0.
          options:keys:do({ spec | | ka, kb |
              verdict:equals(#0):ifTrue({
                  ka := prepare:value(keyOf:value(a, spec),
                            options:ignoreBlanks:or({ spec:at(#5) }),
                            options:foldCase:or({ spec:at(#6) })).
                  kb := prepare:value(keyOf:value(b, spec),
                            options:ignoreBlanks:or({ spec:at(#5) }),
                            options:foldCase:or({ spec:at(#6) })).
                  verdict := compareText:value(ka, kb,
                                 options:numeric:or({ spec:at(#3) })) }) }).
          verdict:equals(#0) }) }.

; ---------------------------------------------------------------------------
; Reading lines without holding the file
;
; A reader answers one line at a time and nil at the end. Two sources, and the
; difference between them is the whole of what this program had to find out.
;
; **From a file: a ranged read with a buffer.** `readFile(path, from, count)`
; gives a window without a handle, so a reader is a path and an integer -- and
; several readers over several files need nothing shared, which is what the
; merge below depends on.
;
; **From a pipe: the same shape**, since
; [6.45](../docs/COMPLETED.md#645-a-pipe-cannot-be-taken-in-bounded-pieces--done)
; closed. `readUpTo(#n)` answers up to n bytes exactly as they were sent, so the
; two branches differ by which call fills the buffer and by nothing else. The
; program that raised that entry is this one -- see the bottom of this file for
; what it cost while the middle was missing.
;
; **The count is a ceiling and the window is a lower one.** `readUpTo` answers
; out of the four-kilobyte window every reader here shares, so asking for 65,536
; gets 4,096 and the loop goes round again. That is the documented contract
; rather than a surprise -- *a short answer is normal* -- and it is written down
; because `readChunk` reads like a promise about the size of a read, and for the
; pipe it is not one.

readChunk := #65536.

reader := object:new.

reader:onFile := { path | | r |
    r := object:new.
    r:path := path.
    r:at := #1.                     ; the next unread byte, one-based
    r:buffer := "".
    r:done := false.
    r:kind := 'file.
    r }.

reader:onStdin := { | r |
    r := object:new.
    r:buffer := "".
    r:done := false.
    r:kind := 'stdin.
    r }.

reader:open := { name |
    name:equals("-"):ifElse({ self:onStdin }, { self:onFile(name) }) }.

; Fills until the buffer holds a newline or the source is spent. Answers
; whether anything is left to hand out.
;
; **`seen` is here because the buffer must not be searched twice.** The obvious
; loop asks `r:buffer:indexOf("\n"):isNil` as its condition, which rescans
; everything read so far on every read -- and on a line longer than one read
; that is a scan per piece over a buffer that keeps growing, which is quadratic
; in the length of the line. **A newline can only be in the bytes just read**,
; since the ones before them have already been searched and had none. So the
; buffer is searched once on the way in and each piece once as it arrives.
;
; Measured, one line and nothing else, through a pipe, `-g`:
;
;                  before      after
;     1,000,000    0.48 s      0.01 s
;     2,000,000    1.90 s      0.04 s
;     4,000,000    7.71 s      0.25 s
;     8,000,000       --       1.10 s
;    16,000,000       --       4.48 s
;
; **Thirty times faster at 4 MB and still quadratic**, which is worth saying
; rather than leaving to be found: the scan is gone and `r:buffer:concat(more)`
; is not. Building an L-byte buffer out of L/4,096 pieces copies the whole of it
; on every piece. This fix is the scan; the concatenation is `next`'s to answer,
; below.
reader:fill := { r | | more, seen |
    seen := r:buffer:indexOf("\n"):notNil.
    { r:done:not:and({ seen:not }) }:whileTrue({
        r:kind:equals('file):ifElse(
            { more := system:readFile(r:path, r:at, readChunk).
              r:at := r:at:add(more:size).
              more:size:equals(#0):ifElse(
                  { r:done := true },
                  { seen := more:indexOf("\n"):notNil.
                    r:buffer := r:buffer:concat(more) }) },
            { more := system:readUpTo(readChunk).
              more:isNil:ifElse(
                  { r:done := true },
                  { seen := more:indexOf("\n"):notNil.
                    r:buffer := r:buffer:concat(more) }) }) }).
    r:buffer:size:greaterThan(#0) }.

; **A last line with no newline is a line**, which is what every sort does --
; and the output always ends with one, so the difference never reaches the
; answer. That is the one place this program is allowed not to care about the
; distinction `diff` had to be exact about.
reader:next := { r | | at, line |
    self:fill(r):ifElse(
        { at := r:buffer:indexOf("\n").
          at:isNil:ifElse(
              { line := r:buffer. r:buffer := "" },
              { line := r:buffer:copyFrom(#1, at:sub(#1)).
                r:buffer := r:buffer:copyFrom(at:add(#1), r:buffer:size) }).
          line },
        { nil }) }.

; ---------------------------------------------------------------------------
; Where the runs go
;
; `TMPDIR` when there is one, the way the tool does, and `build/` when there is
; not. The directory is made, filled and taken away again -- a program that
; leaves runs behind after sorting a large file is worse than one that is slow.

temporary := object:new.
temporary:dir := nil.
temporary:count := #0.

temporary:directory := { | base |
    self:dir:isNil:ifTrue({
        base := system:environment("TMPDIR").
        base:isNil:ifTrue({ base := "build/" }).
        base:endsWith("/"):ifFalse({ base := base:concat("/") }).
        self:dir := base:concat("solveig-sort-")
                        :concat(system:clock:mul(1000000.0):truncated:asString).
        system:makeDirectory(self:dir) }).
    self:dir }.

temporary:path := {
    self:count := self:count:add(#1).
    self:directory:concat("/run-"):concat(self:count:asString) }.

temporary:clean := {
    self:dir:isNil:ifFalse({
        system:filesIn(self:dir):do({ name |
            system:remove(self:dir:concat("/"):concat(name)) }).
        system:remove(self:dir).
        self:dir := nil }) }.

; ---------------------------------------------------------------------------
; Sorting
;
; **`array:sorted(block)` is a stable merge sort**, which this program needs and
; which nothing said. See the bottom of the file: the guarantee is in a comment
; in `builtins.c` and was not in the reference until this program went looking
; for it.
;
; The comparison hands `sorted` a boolean and keeps the three-way answer for the
; merge and for `-u`, which both need *equal* rather than *before*.
sortBatch := { lines |
    lines:sorted({ a, b | compareLines:value(a, b):lessThan(#0) }) }.

; ---------------------------------------------------------------------------
; The whole of it, in one pass over the inputs
;
; Read until the budget is spent, sort what is in hand, and either keep it (if
; that was all there was) or write it out as a run and carry on. **One run means
; the file fitted**, and the merge below is then a walk over a single sorted
; array rather than anything to do with files.

runs := array:new.
inMemory := nil.

spill := { batch | | path |
    path := temporary:path.
    system:writeFile(path, sortBatch:value(batch):join("\n"):concat("\n")).
    runs:add(path) }.

readEverything := {
    | batch, bytes, r, line |
    batch := array:new.
    bytes := #0.
    options:files:do({ name |
        r := reader:open(name).
        line := reader:next(r).
        { line:notNil }:whileTrue({
            batch:add(line).
            bytes := bytes:add(line:size):add(#1).
            bytes:greaterOrEqual(options:budget):ifTrue({
                spill:value(batch).
                batch := array:new.
                bytes := #0 }).
            line := reader:next(r) }) }).

    ; What is left over is a run like any other -- except when it is the only
    ; one, where writing it to a file and reading it back would be work done to
    ; make the code shorter rather than to make it right.
    runs:size:equals(#0):ifElse(
        { inMemory := sortBatch:value(batch) },
        { batch:size:greaterThan(#0):ifTrue({ spill:value(batch) }) }) }.

; ---------------------------------------------------------------------------
; Merging
;
; **The k-way merge is where a positioned write was predicted and where the
; ranged read turned out to be the whole answer.** Every run has a reader, each
; reader is a path and an integer, and the smallest head wins. Nothing is
; opened, nothing is closed, and nothing has to be seeked to a place it was
; already at.
;
; **The winner comes off a heap, and the first draft used a linear scan.** That
; draft carried a comment saying a heap *would matter at a few hundred runs* and
; that the scan was the trade this repository keeps making until something
; measures otherwise. Something measured otherwise within the day, and the
; comment had named its own falsifying condition well enough to recognise it:
;
; | 400 lines, 23 KB | scan | heap |
; | --- | --- | --- |
; | `-S 100000` -- one run, no merge | 0.01 s | 0.01 s |
; | `-S 1024` -- 23 runs | 0.02 s | 0.02 s |
; | `-S 64` -- 366 runs | **0.24 s** | 0.09 s |
;
; Twenty-four times on four hundred lines, and the shape is `lines x runs`.
; `sweep.sh` runs `-S 16` over this repository's own files, where
; `docs/CHANGELOG.md` is **14,707 lines in 788,815 bytes** -- some forty-nine
; thousand runs, and a comparison per run per line.
;
; **It did not fail. It ran for two hours and fourteen minutes without
; finishing the generated half**, which is how this was found: a check too slow
; to finish is a defect report that nobody reads as one. The same file, same
; budget, on the heap:
;
; ```text
; sort -S 16 docs/CHANGELOG.md      3.88 s, and agrees with the tool
; ```
;
; And the sweep that would not finish now takes 5 minutes 28 seconds for all
; 1,610 comparisons.
;
; **What the handle-free reader bought is worth naming here.** A merge over
; 43,750 runs is not unusual for an external sort at a small budget, and a
; program holding a file handle per run would have run out of descriptors long
; before it ran out of patience. A reader here is a path and an integer, so the
; only cost of a large `k` was the scan -- which is an algorithm to choose
; rather than a wall to hit.
;
; Ties go to the **earlier run**, which the scan got for free by taking the
; first strictly-smaller head and the heap has to be told: two runs holding
; equal lines must come out in the order they were written, or `-s` stops being
; stable the moment the input spills.

emit := object:new.
emit:parts := array:new.
emit:held := #0.
emit:path := nil.
emit:started := false.

emit:line := { line |
    self:parts:add(line).
    self:held := self:held:add(line:size):add(#1).
    self:held:greaterThan(#1048576):ifTrue({ self:flush }) }.

emit:flush := { | text |
    self:parts:size:greaterThan(#0):ifTrue({
        text := self:parts:join("\n"):concat("\n").
        self:parts := array:new.
        self:held := #0.
        self:path:isNil:ifElse(
            { system:write(text) },
            { self:started:ifElse(
                { system:appendFile(self:path, text) },
                { system:writeFile(self:path, text). self:started := true }) }) }) }.

emit:finish := {
    self:flush.
    ; A file that was written to must exist even when nothing was written to
    ; it: `sort -o out.txt` over an empty input leaves an empty file, not the
    ; file that was there before.
    self:path:isNil:or({ self:started }):ifFalse({
        system:writeFile(self:path, "") }) }.

; A binary heap of run numbers, ordered by the line each run is holding. The
; array is one-based, so a node at `i` has its parent at `i/2` and its children
; at `2i` and `2i+1` with no offset anywhere -- which is the one place this
; language's indexing is simpler than C's rather than noisier.
heads := array:new.

; Equal lines go to the earlier run, so that a spilled sort is as stable as one
; that fitted.
heapBefore := { a, b | | r |
    r := compareLines:value(heads:at(a), heads:at(b)).
    r:equals(#0):ifElse({ a:lessThan(b) }, { r:lessThan(#0) }) }.

siftUp := { heap, at | | i, parent, t |
    i := at.
    { i:greaterThan(#1)
        :and({ heapBefore:value(heap:at(i), heap:at(i:div(#2))) }) }:whileTrue({
        parent := i:div(#2).
        t := heap:at(i). heap:atPut(i, heap:at(parent)). heap:atPut(parent, t).
        i := parent }) }.

siftDown := { heap, size | | i, small, left, right, t, going |
    i := #1.
    going := true.
    { going }:whileTrue({
        small := i.
        left := i:mul(#2).
        right := left:add(#1).
        left:lessOrEqual(size)
            :and({ heapBefore:value(heap:at(left), heap:at(small)) }):ifTrue({
            small := left }).
        right:lessOrEqual(size)
            :and({ heapBefore:value(heap:at(right), heap:at(small)) }):ifTrue({
            small := right }).
        small:equals(i):ifElse(
            { going := false },
            { t := heap:at(i). heap:atPut(i, heap:at(small)).
              heap:atPut(small, t).
              i := small }) }) }.

mergeReaders := { readers | | heap, size, best, last, haveLast |
    heads := readers:collect({ r | reader:next(r) }).
    heap := array:new.
    size := #0.
    [#1, heads:size]:loop({ n |
        heads:at(n):notNil:ifTrue({
            heap:add(n).
            size := size:add(#1).
            siftUp:value(heap, size) }) }).

    last := nil.
    haveLast := false.

    { size:greaterThan(#0) }:whileTrue({ | line |
        best := heap:at(#1).
        line := heads:at(best).

        ; `-u` drops a line whose key matches the one before it, which is the
        ; only place the merge looks backwards.
        options:unique:and({ haveLast })
            :and({ sameKey:value(last, line) }):ifFalse({
            emit:line(line) }).
        last := line.
        haveLast := true.

        heads:atPut(best, reader:next(readers:at(best))).
        heads:at(best):isNil:ifElse(
            { heap:atPut(#1, heap:at(size)).
              heap:removeLast.
              size := size:sub(#1) },
            { }).
        size:greaterThan(#0):ifTrue({ siftDown:value(heap, size) }) }) }.

; ---------------------------------------------------------------------------
; Checking rather than sorting
;
; `-c` says nothing when the file is in order and names the first line that is
; not: `sort: <name>:<line>: disorder: <text>`, exit 1. The name of a pipe is
; `-`, which is what the tool prints and is why the corpus marks these cases
; `pipenames:` rather than waving the two routes through.

check := { | r, name, previous, n, bad |
    name := options:files:at(#1).
    r := reader:open(name).
    previous := reader:next(r).
    n := #1.
    bad := nil.
    { bad:isNil:and({ previous:notNil }) }:whileTrue({ | line |
        line := reader:next(r).
        line:isNil:ifElse(
            { previous := nil },
            { n := n:add(#1).
              ; `-c` with `-u` refuses an *equal* pair too, which is the one
              ; place the two options meet.
              (compareLines:value(line, previous):lessThan(#0)
                  :or({ options:unique:and({ sameKey:value(line, previous) }) }))
                  :ifElse(
                  { bad := [n, line] },
                  { previous := line }) }) }).
    bad:isNil:ifElse(
        { #0 },
        { system:writeError("sort: {}:{}: disorder: {}\n"
                                :fill([name, bad:at(#1), bad:at(#2)])).
          #1 }) }.

; ---------------------------------------------------------------------------
; Running it

sort := object:new.

; **Every run starts from nothing**, which the demonstration is what found:
; it sorts the same file three ways, and the second run merged the first run's
; spill files because `runs` and the emitter were still holding them. A program
; invoked once from a command line would never have shown it.
sort:run := { | readers |
    runs := array:new.
    inMemory := nil.
    emit:parts := array:new.
    emit:held := #0.
    emit:started := false.
    emit:path := options:output.

    options:checkOnly:ifElse(
        { check:value },
        { options:mergeOnly:ifElse(
            { ; The inputs are sorted already, so there is nothing to sort:
              ; the merge is the whole program, and this is the path a run of
              ; `sort` over already-sorted parts takes.
              readers := options:files:collect({ name | reader:open(name) }).
              mergeReaders:value(readers).
              emit:finish.
              #0 },
            { readEverything:value.
              inMemory:isNil:ifElse(
                  { readers := runs:collect({ path | reader:onFile(path) }).
                    mergeReaders:value(readers) },
                  { | last, haveLast |
                    last := nil. haveLast := false.
                    inMemory:do({ line |
                        options:unique:and({ haveLast })
                            :and({ sameKey:value(last, line) }):ifFalse({
                            emit:line(line) }).
                        last := line. haveLast := true }) }).
              emit:finish.
              temporary:clean.
              #0 }) }) }.

; ---------------------------------------------------------------------------
; What it does with no arguments

demonstrate := { | dir, path |
    dir := "build".
    system:makeDirectory(dir).
    path := "build/sort-demo.txt".
    system:writeFile(path,
        "pear:3\napple:10\nfig:1\nbanana:2\napple:7\n").

    "-- in byte order":display.
    options:files := [path].
    sort:run.

    "":display.
    "-- by the number after the colon, numerically":display.
    options:keys := [options:key("2,2n")].
    options:separator := ":".
    sort:run.

    "":display.
    "-- one line per fruit, four bytes at a time so it spills to runs":display.
    options:keys := [options:key("1,1")].
    options:unique := true.
    options:budget := #4.
    sort:run }.

; **No arguments means two different things here**, which is the second time a
; program in this directory has had that -- `tail` was the first, and the note
; in its file is where this one was copied from rather than rediscovered.
; Every program here runs with no arguments on input it carries; `... | sort` is
; also a real invocation, and it is how half of sort's uses are typed. The same
; empty command line, two meanings, and `system:isTerminal` is what tells them
; apart.
;
; It was found by the corpus rather than by thinking: the pipe route of every
; case with no options ran the demonstration and reported it as the answer.
{ system:arguments:size:equals(#0):and({ system:isTerminal('input) }):ifElse(
    { demonstrate:value },
    { options:read(system:arguments).
      system:exit(sort:run) }) }:onError({ e |
    temporary:clean.
    system:writeError("sort: {}\n":fill([e:message])).
    system:exit(#2) }).

; ---------------------------------------------------------------------------
; The prediction was wrong about the gap, and the reason is the finding
;
; **Kept beside the prediction rather than in place of it.**
; [ideas.md](../docs/ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31)
; said `sort`'s real finding would be a missing **positioned write**, on the
; reasoning that an external merge sort writes runs to temporary files and
; `writeFile` replaces where `appendFile` appends.
;
; ### There is nothing to write into the middle of
;
; **An external merge sort never seeks in a file it is writing.** A run is
; produced whole -- read a budget's worth of lines, sort them, write them once
; -- and then it is only ever *read*. The output is produced in order, so it
; appends. `writeFile` and `appendFile` are exactly the two writes this needs
; and there is no third.
;
; The entry called this *the mirror of the ranged read*, and a mirror is the
; wrong figure: the ranged read exists because a program wants to look at part
; of a file it did not write. Nothing wants to write part of a file it is
; producing, because a producer knows what comes next. **A write is not the
; reverse of a read**, and the entry reasoned from the symmetry of the names.
;
; ### What the merge wanted was the ranged read, and it was already there
;
; The k-way merge needs `k` independent positions in `k` files at once, which is
; the thing a language with file *handles* has to think about -- how many are
; open, what closes them, what happens when one is used after closing.
; `readFile(path, from, count)` has none of that: **a reader here is a path and
; an integer.** So the half of the program the entry was worried about is the
; half that needed nothing.
;
; ### The claim this program nearly published, and had to take back
;
; The entry's first sentence was *`array:sorted(block)` at scale, and its
; stability, which nothing has had to care about.* `sort -s` has to care, and so
; does `-k`, so this was going to be the headline: **`sorted` is a stable merge
; sort, deliberately, and nothing says so** -- an implementation detail and a
; promise being the same line of code, which is the shape
; [6.42](../docs/COMPLETED.md#642-a-second-producer-of-sob-has-no-contract-to-build-against--done)
; closed for the bytecode format five days earlier.
;
; **It is not true.** [REFERENCE.md](../docs/REFERENCE.md#array) has said it all
; along, in prose under the sorting examples rather than in the message table:
;
; > The sort is **stable** -- equal elements keep the order they were in --
; > which is what makes sorting twice a way to order by two keys.
;
; The paragraph was written and nearly shipped because a `grep` for `sorted`
; found the table row and the `filesIn` note and stopped there. **An absence was
; asserted from a search that did not cover the document**, which is the
; argument from absence
; [design.md](../docs/design.md#what-the-language-is-for) rules out for
; features and 2026-09-01 found nothing had ruled out for checks. It is kept
; here rather than deleted because the *good* version of this finding and the
; wrong one look identical until somebody reads the page.
;
; What is true is the smaller thing: **this program depends on that guarantee**,
; and it is the first here that does. `-s` is exactly *no last resort, and let
; the sort keep the order*, and the merge relies on the same promise across
; runs. Until now the sentence in the reference had no customer.
;
; ### `-n` is the second customer for a lenient numeric read
;
; `asFloat` is strict on purpose and the reference says so. Every sort reads a
; *prefix*: blanks, a sign, digits, a point. `1e3` is **one** and `0x10` is
; **zero**, measured against the tool rather than assumed.
;
; [awk](awk.sol) predicted this gap first and was written after `lib/re.sol`
; rather than on it, so the gap was named and never had a second customer. It
; has one now -- and the honest report is that it cost **nine lines**, which is
; why this is a paragraph rather than a roadmap entry. A message that saves nine
; lines in two programs is not one this language is short of.
;
; ### The second customer for 6.43, which is why 6.45 has a number
;
; [6.43](../docs/COMPLETED.md#643-a-program-cannot-read-standard-input-whole-and-the-call-that-looks-as-though-it-can-answers---done)
; said a program cannot read standard input whole, and `diff` raised it because
; `readLine` cannot see the newline at the end. That closed on 2026-09-03 and
; this half did not, so it is
; [6.45](../docs/COMPLETED.md#645-a-pipe-cannot-be-taken-in-bounded-pieces--done) now.
;
; **`sort` does not care about the newline** -- the output always ends with one,
; so the distinction never reaches the answer -- and it was the second customer
; anyway, for the other half:
; `readLine` folds `\r\n` into one terminator, so a file written on another
; system sorts as *different lines* through a pipe than through a name.
;
; **And it adds a reason the entry does not have.** `diff` wants a pipe read
; *whole*. A sort that spills to runs wants the opposite: a pipe read in bounded
; pieces, so that memory stays inside `-S` no matter how large the input is.
; `readKey` does that and costs 238 nanoseconds a byte; `readLine` does it at a
; twentieth of the price and changes the answer. **The entry is about the
; absence of a middle**, and the second customer is what shows that the middle
; is what is missing rather than the whole-file read.
;
; ### And the middle arrived, so this is what it was worth
;
; `readUpTo` shipped in 0.43.0 and the byte-at-a-time loop above is now four
; lines that read like the file branch beside them. Same machine, same input --
; `docs/REFERENCE.md` and `docs/ideas.md` concatenated, 584,997 bytes in 11,350
; lines -- and the counts are exact rather than sampled, by the `--steps=N`
; binary search `gzip.sol` describes. **An instruction count does not depend on
; how the machine was built**, and these were reproduced under both `-g` and
; `-O2` to the instruction; the seconds below are `-O2`, best of five, because
; `make` builds `-g` and those would be a different number:
;
;     through a pipe, byte at a time      28,846,431 instructions
;     through a pipe, `readUpTo`          15,402,663      1.87x fewer
;     the same file named on the command line 15,398,455
;
; **The pipe now costs what the name costs**, to within 4,208 instructions on
; thirteen and a half million saved -- 0.03%, and the file route did not change.
; That is the result worth having and it is not the speed: a program with two
; ways in had two performance stories, and the entry's whole argument was that
; one of them was missing a call. 4.7 MB through a pipe went from 1.50 s to
; 0.81 s.
;
; **What was spent was 23 instructions a byte**, which is what `readKey` costs
; in the loop that has to ask whether it answered nil. Nothing about the answer
; moved -- `oracle.sh` runs all thirty cases down both routes and reports the
; same two divergences it always has.
;
; ### What the conversion turned up, and it is about `readChunk`
;
; `next` drains the buffer with `copyFrom(at + 1, size)`, so **every line copies
; whatever is behind it**, and a larger read is therefore not a cheaper one.
; Measured on the file route, 4.7 MB, otherwise identical:
;
;     readChunk  4,096      0.88 s
;                8,192      0.86 s
;               16,384      0.87 s
;               65,536      1.03 s     <- what this program uses
;
; (`-O2`, best of five, on the 4,679,976-byte file above. A `-g` build loses
; every one of these and the shape is what matters, not the digits.)
;
; Both effects are visible in that table: the drain punishes the large end and
; the per-call cost punishes the small one. It is left at 65,536 because
; changing it is a different piece of work from this one and wants its own
; check -- but it is written down with numbers rather than as a suspicion, and
; it is why the pipe route above beats the named file by 20% in wall clock
; while costing the same instructions. The pipe's reads are 4,096 bytes whatever
; is asked for.
