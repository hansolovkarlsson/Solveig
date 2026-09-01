; sha256sum.sol -- the SHA-256 of a file, and the check of one.
;
; Run with:  ./bin/solas programs/sha256sum.sol && ./bin/solvm programs/sha256sum.sob
;
;     solvm sha256sum.sob file...        one line per file: the digest, two
;                                        spaces, the name
;     solvm sha256sum.sob -b file        a `*` before the name instead
;     solvm sha256sum.sob -z file        NUL instead of the newline
;     solvm sha256sum.sob -c sums.txt    check a list, `name: OK` per line
;     solvm sha256sum.sob -c -w sums.txt and complain about lines that are not
;     ... | solvm sha256sum.sob          from a pipe, which is named `-`
;
; `-t` is the default and is accepted so that `-bt` and `-tb` mean what they do
; elsewhere. **That is the whole of `sha256sum [-bctwz]`, which is the whole of
; the usage line of the tool on this machine -- and not the whole of the tool.**
; `/sbin/sha256sum` also answers to ten long options its own usage line does not
; mention: `--binary`, `--text`, `--check`, `--warn` and `--zero` alongside the
; short forms, and `--tag`, `--quiet`, `--status`, `--help` and `--version`
; which have no short form at all. None of those is written here, and the three
; cases in `sha256sum/differ/` are what stop that being a sentence nobody
; rechecks.
;
; With no arguments and nothing on standard input it demonstrates itself, which
; is the house rule for these programs -- see the note at the bottom about how
; that is told apart from `... | sha256sum`, which is the same empty command
; line meaning the opposite thing.
;
; ---------------------------------------------------------------------------
; The eighteenth program here, and the first with no I/O in its inner loop
;
; Every program in this directory so far is a parser or a filter over text, and
; spends its time in `split`, `indexOf` or a syscall.
; [ideas.md](../docs/ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31)
; surveyed what to write next and put this first for one reason: **sixty-four
; rounds of shifts, masks and additions per sixty-four bytes, and nothing else.**
; It is the cheapest available answer to the question standing behind every
; numeric ambition on that page -- *what does this interpreter cost per
; arithmetic operation when there is nothing else going on* -- and it is a
; measurement no amount of reading the dispatch loop produces.
;
; **And the answer is at the bottom of this file**, with the two other things it
; found, one of which is a language gap that now has a roadmap number.
;
; The oracle is `/sbin/sha256sum`, which is on this machine and was written by
; somebody who had never heard of this language. The published FIPS 180-4
; vectors are a second and independent check, which is the thing `sed` and
; `tail` did not have: an oracle can be wrong in the same direction as a copy of
; itself, and a number printed in a standard cannot.
;
;     sh programs/sha256sum/vectors.sh     the published vectors
;     sh programs/oracle.sh sha256sum      the corpus, both ways in
;     sh programs/sha256sum/check.sh       -c, which wants a directory of files

; ---------------------------------------------------------------------------
; Thirty-two bits, in a language that has one integer type
;
; SHA-256 is defined on arithmetic modulo 2^32 and this language has a single
; signed 64-bit integer that **traps rather than wrapping**
; ([strictness.sol](../examples/strictness.sol)). The
; [At a glance](../docs/ideas.md#at-a-glance) table says **No** to byte, word and
; long for that reason, so this is the first program here to want them.
;
; It does not need them. A 64-bit integer holds the sum of eight 32-bit values
; without going near the trap, so `add` is exact and `mask` puts the answer back
; in range afterwards. The cost is one `bitAnd` per arithmetic step, and whether
; that reads as arithmetic or as bookkeeping is the ergonomic half of what this
; program was written to report.
;
; **What it must not do is shift into bit 63**
; ([3.12](../docs/ROADMAP.md#312-no-shift-can-produce-a-negative-integer)): a
; `shiftLeft` that overflows an i64 is an error whatever the bit pattern meant.
; The largest shift below is 30 places of a value under 2^32, which lands under
; 2^62, so nothing here comes within a factor of two of it. That is luck rather
; than design -- SHA-512 rotates a 64-bit word and could not be written this way
; at all.

mask := $FFFFFFFF.

; The first thirty-two bits of the fractional parts of the cube roots of the
; first sixty-four primes -- FIPS 180-4 section 4.2.2, copied rather than
; computed, which is what the standard prints them for.
k := [
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5,
    $3956C25B, $59F111F1, $923F82A4, $AB1C5ED5,
    $D807AA98, $12835B01, $243185BE, $550C7DC3,
    $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174,
    $E49B69C1, $EFBE4786, $0FC19DC6, $240CA1CC,
    $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7,
    $C6E00BF3, $D5A79147, $06CA6351, $14292967,
    $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13,
    $650A7354, $766A0ABB, $81C2C92E, $92722C85,
    $A2BFE8A1, $A81A664B, $C24B8B70, $C76C51A3,
    $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5,
    $391C0CB3, $4ED8AA4A, $5B9CCA4F, $682E6FF3,
    $748F82EE, $78A5636F, $84C87814, $8CC70208,
    $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2].

; The same, of the square roots of the first eight -- section 5.3.3.
initial := [$6A09E667, $BB67AE85, $3C6EF372, $A54FF53A,
            $510E527F, $9B05688C, $1F83D9AB, $5BE0CD19].

; ---------------------------------------------------------------------------
; The hash, which is fed rather than handed a file
;
; **A digest is computed a block at a time, so nothing here ever holds a file.**
; That was not the plan -- the plan was to read the file and hash the string --
; and it fell out of the pipe: standard input arrives a byte at a time, so the
; state had to survive between bytes, and once it does a named file may as well
; be read in pieces too.
;
; So this is the second caller of
; [`readFile(path, from, count)`](../docs/COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done),
; and it wants the call for the opposite reason `tail` did. `tail` seeks
; backwards to a place it computed; this walks forwards and never looks back. A
; ranged read serves both, which is a thing worth knowing about the shape that
; was chosen: **the entry argued for a range over a handle and the second caller
; did not have to argue again.**

sha256 := object:new.

sha256:h := nil.            ; the eight words of state
sha256:pending := "".       ; fewer than 64 bytes, waiting for the rest of one
sha256:length := #0.        ; how many bytes have gone in, for the padding

sha256:start := { | s |
    s := self:new.
    s:h := initial:copyFrom(#1, #8).
    s:pending := "".
    s:length := #0.
    s }.

; ---------------------------------------------------------------------------
; One block of sixty-four bytes, from `text` beginning at the one-based `base`
;
; This is the whole program's running time. Everything else in this file is
; arrangements.
;
; **The rotates are written out rather than called**, and that is a measurement
; and not a preference. `rotr(x, n)` is `x >> n | x << (32 - n)`, masked, and as
; a method on this object it reads the way the standard writes it:
;
;     s1 := self:rotr(e, #6):bitXor(self:rotr(e, #11)):bitXor(self:rotr(e, #25)).
;
; Six of those per round, sixty-four rounds, and four more per step of the
; message schedule. Hashing a megabyte at `-O2`, all three answering the same
; digest:
;
;     rotr as a method everywhere                 1.36 s   0.74 MB/s
;     written out in the sixty-four rounds        1.10 s   0.91 MB/s   1.24x
;     written out in the message schedule too     0.92 s   1.09 MB/s   1.48x
;
; **A third of this program was the call, not the rotate.** The arithmetic is
; the same either way; what the method cost was a frame and a return, ten times
; per round, and it is 32% of the running time of the readable version.
;
; **The `bitOr` is an exclusive one**, which is what lets the chain below stay
; flat. `x >> n` occupies bits 0 to 31-n and `x << (32-n)` occupies 32-n
; upwards, so within a rotate the two halves never share a bit and `bitOr` and
; `bitXor` are the same operation on them. The whole of `s0` and `s1` is
; therefore one left-to-right xor chain, and the single `bitAnd(mask)` at the
; end throws away everything the left shifts put above bit 31.
sha256:block := { h, text, base | | w, a, b, c, d, e, f, g, hh, s0, s1, ch, maj, t1, t2, at, x, y |
    w := array:new.

    ; Sixteen big-endian words, four bytes each. `string:at` answers a
    ; one-character string and `asByte` its number; there is no way to ask a
    ; string for a byte in one send, and this loop is where that shows.
    [#0, #15]:loop({ i |
        at := base:add(i:mul(#4)).
        w:add(text:at(at):asByte:shiftLeft(#24)
               :bitOr(text:at(at:add(#1)):asByte:shiftLeft(#16))
               :bitOr(text:at(at:add(#2)):asByte:shiftLeft(#8))
               :bitOr(text:at(at:add(#3)):asByte)) }).

    ; Forty-eight more, each from four already there. One-based, so `w:at(i)` is
    ; the standard's W[i-1] and the offsets below are its 2, 7, 15 and 16.
    [#17, #64]:loop({ i |
        x := w:at(i:sub(#15)).
        s0 := x:shiftRight(#7):bitOr(x:shiftLeft(#25))
                :bitXor(x:shiftRight(#18)):bitXor(x:shiftLeft(#14))
                :bitXor(x:shiftRight(#3)):bitAnd(mask).
        y := w:at(i:sub(#2)).
        s1 := y:shiftRight(#17):bitOr(y:shiftLeft(#15))
                :bitXor(y:shiftRight(#19)):bitXor(y:shiftLeft(#13))
                :bitXor(y:shiftRight(#10)):bitAnd(mask).
        w:add(w:at(i:sub(#16)):add(s0):add(w:at(i:sub(#7))):add(s1)
                :bitAnd(mask)) }).

    ; The eight working variables are locals rather than slots on purpose: a
    ; slot is a send and there are five hundred and twelve reads of these.
    a := h:at(#1). b := h:at(#2). c := h:at(#3). d := h:at(#4).
    e := h:at(#5). f := h:at(#6). g := h:at(#7). hh := h:at(#8).

    [#1, #64]:loop({ i |
        s1 := e:shiftRight(#6):bitOr(e:shiftLeft(#26))
                :bitXor(e:shiftRight(#11)):bitXor(e:shiftLeft(#21))
                :bitXor(e:shiftRight(#25)):bitXor(e:shiftLeft(#7)):bitAnd(mask).
        ; `bitNot` answers a negative here -- the language has no unsigned
        ; integer -- and that is harmless, because `bitAnd(g)` immediately
        ; throws away every bit above 31, sign bits included.
        ch := e:bitAnd(f):bitXor(e:bitNot:bitAnd(g)):bitAnd(mask).
        t1 := hh:add(s1):add(ch):add(k:at(i)):add(w:at(i)):bitAnd(mask).
        s0 := a:shiftRight(#2):bitOr(a:shiftLeft(#30))
                :bitXor(a:shiftRight(#13)):bitXor(a:shiftLeft(#19))
                :bitXor(a:shiftRight(#22)):bitXor(a:shiftLeft(#10)):bitAnd(mask).
        maj := a:bitAnd(b):bitXor(a:bitAnd(c)):bitXor(b:bitAnd(c)).
        t2 := s0:add(maj):bitAnd(mask).
        hh := g. g := f. f := e.
        e := d:add(t1):bitAnd(mask).
        d := c. c := b. b := a.
        a := t1:add(t2):bitAnd(mask) }).

    h:atPut(#1, h:at(#1):add(a):bitAnd(mask)).
    h:atPut(#2, h:at(#2):add(b):bitAnd(mask)).
    h:atPut(#3, h:at(#3):add(c):bitAnd(mask)).
    h:atPut(#4, h:at(#4):add(d):bitAnd(mask)).
    h:atPut(#5, h:at(#5):add(e):bitAnd(mask)).
    h:atPut(#6, h:at(#6):add(f):bitAnd(mask)).
    h:atPut(#7, h:at(#7):add(g):bitAnd(mask)).
    h:atPut(#8, h:at(#8):add(hh):bitAnd(mask)).
    h }.

; Take in some more of the message. Whole blocks are hashed out of the caller's
; string without copying it; the remainder waits here for the next call.
sha256:update := { text | | buf, full |
    text:size:greaterThan(#0):ifTrue({
        self:length := self:length:add(text:size).

        ; The concat is skipped when there is nothing pending, which is every
        ; call for a named file: the chunks read below are multiples of 64, so
        ; nothing is ever left over until the last one.
        buf := self:pending:size:equals(#0):ifElse(
            { text },
            { self:pending:concat(text) }).

        full := buf:size:div(#64).
        [#0, full:sub(#1)]:loop({ i |
            self:block(self:h, buf, i:mul(#64):add(#1)) }).
        self:pending := buf:copyFrom(full:mul(#64):add(#1), buf:size) }).
    self }.

; Pad and finish. The padding is a `1` bit, then zeros, then the length in bits
; as eight big-endian bytes, arranged so the whole message is a multiple of 64.
; It happens in one small string of at most 128 bytes, whatever the file's size.
sha256:digest := { | tail, bits, want |
    bits := self:length:mul(#8).
    tail := self:pending:concat(#128:asCharacter).
    want := tail:size:greaterThan(#56):ifElse({ #120 }, { #56 }).
    { tail:size:lessThan(want) }:whileTrue({ tail := tail:concat(#0:asCharacter) }).
    [#7, #0, #-1]:loop({ i |
        tail := tail:concat(bits:shiftRight(i:mul(#8)):bitAnd(#255):asCharacter) }).
    [#0, tail:size:div(#64):sub(#1)]:loop({ i |
        self:block(self:h, tail, i:mul(#64):add(#1)) }).
    self:h:collect({ n | self:hex(n) }):join("") }.

; Eight hex digits, lower case. `asBase(#16)` drops leading zeros, which is
; right for a number and wrong for a field, so they go back on.
sha256:hex := { n | | s |
    s := n:asBase(#16).
    { s:size:lessThan(#8) }:whileTrue({ s := "0":concat(s) }).
    s }.

; ---------------------------------------------------------------------------
; Where the bytes come from
;
; **65536 is a multiple of 64**, which keeps `pending` empty for every call but
; the last so that no chunk is ever copied. That is the property the *code*
; needs. The size is a separate question and it is **not** free, which a first
; draft of this comment asserted without measuring.
;
; **A ranged read costs about 30 microseconds whatever it reads.** One byte,
; sixty-four, four kilobytes, sixty-four kilobytes -- all the same, because the
; cost is the `fopen` and not the bytes. Beside it, `fileSize`, `fileExists` and
; `modifiedAt` cost **0.65 us**: they `stat` and never open. Forty-five times.
;
; So the chunk is what amortises an open, and a megabyte hashed at `-O2` says
; so:
;
;     chunk       1 MB
;     64          1.49 s    62% slower -- 16,384 opens
;     256         1.19 s
;     4096        0.96 s
;     65536       0.93 s
;     1 MB        0.92 s
;
; Flat from about four kilobytes, which is where 30 us stops being visible next
; to the arithmetic. **This is a property of the machine rather than of the
; primitive**: plain C doing `fopen`, `fread` of 64 bytes and `fclose` on the
; same file measures 28 us here, so `readFile` adds one or two.

chunk := #65536.

sha256:ofFile := { path | | s, at, part |
    s := self:start.
    at := #1.
    part := system:readFile(path, at, chunk).
    { part:size:greaterThan(#0) }:whileTrue({
        s:update(part).
        at := at:add(part:size).
        part := system:readFile(path, at, chunk) }).
    s:digest }.

; **Standard input is read one byte at a time, and that is exact rather than
; approximate.** `readLine` cannot say whether the last line ended in a newline
; -- `sed` found that and so did `tail` -- and for a checksum that is not a
; formatting detail, it is a different answer. `readKey` answers one byte, NUL
; included, and nil at the end, which is the whole truth about the stream.
;
; It costs almost nothing. A megabyte through a pipe takes 1.02 s against 0.92 s
; for the same megabyte named as a file, so reading a byte at a time and
; assembling it is **a tenth** of a program doing this much arithmetic --
; and `readKey` on its own runs at about 18 MB/s (17.2 to 19.6 over five runs),
; seventeen times faster than the hash it is feeding. The byte-at-a-time reader that would be a disaster in a
; text filter is invisible behind arithmetic this expensive. The one-byte
; strings go into an array and are joined rather than concatenated in turn, so
; that building a chunk stays linear.
sha256:ofStdin := { | s, parts, b, n |
    s := self:start.
    parts := array:new.
    n := #0.
    b := system:readKey.
    { b:notNil }:whileTrue({
        parts:add(b).
        n := n:add(#1).
        n:equals(chunk):ifTrue({
            s:update(parts:join("")).
            parts := array:new.
            n := #0 }).
        b := system:readKey }).
    n:greaterThan(#0):ifTrue({ s:update(parts:join("")) }).
    s:digest }.

; ---------------------------------------------------------------------------
; The options

options := object:new.
options:binary := false.            ; -b, a `*` before the name
options:check := false.             ; -c
options:warn := false.              ; -w
options:zero := false.              ; -z, NUL instead of the newline
options:files := nil.

options:read := { args | | i, a, j, c |
    self:files := array:new.
    i := #1.
    { i:lessOrEqual(args:size) }:whileTrue({
        a := args:at(i).
        a:equals("--"):ifElse(
            { i := i:add(#1).
              { i:lessOrEqual(args:size) }:whileTrue({
                  self:files:add(args:at(i)). i := i:add(#1) }) },
            ; `-` on its own is standard input and not an option, which is the
            ; one place the leading dash does not mean what it usually does.
            { a:size:greaterThan(#1):and({ a:copyFrom(#1, #1):equals("-") })
                :ifElse(
                { ; A long option is refused by name rather than a character at
                  ; a time, which would otherwise report the second `-` as the
                  ; unknown one. The tool on this machine takes ten of these
                  ; and its usage line mentions none -- see the note below the
                  ; option table.
                  a:copyFrom(#1, #2):equals("--"):ifTrue({
                      error:raise("unknown option `{}`":fill([a])) }).
                  j := #2.
                  { j:lessOrEqual(a:size) }:whileTrue({
                      c := a:at(j).
                      c:equals("b"):ifTrue({ self:binary := true }).
                      c:equals("t"):ifTrue({ self:binary := false }).
                      c:equals("c"):ifTrue({ self:check := true }).
                      c:equals("w"):ifTrue({ self:warn := true }).
                      c:equals("z"):ifTrue({ self:zero := true }).
                      ["b", "t", "c", "w", "z"]:indexOf(c):isNil:ifTrue({
                          error:raise("unknown option `-{}`":fill([c])) }).
                      j := j:add(#1) }).
                  i := i:add(#1) },
                { self:files:add(a). i := i:add(#1) }) }) }).
    self }.

; ---------------------------------------------------------------------------
; Writing a line
;
; Two spaces before a name, or a space and a `*` in binary mode. The `*` says
; nothing about how the file was read here -- there is no text mode to differ
; from, since a string is bytes and nothing translates a line ending -- and it
; is written because a checksum file carrying it has to be readable by the tool
; that wrote it and by this one.

report := object:new.
report:failed := false.

report:line := { text |
    system:write(text:concat(options:zero:ifElse({ #0:asCharacter }, { "\n" }))) }.

report:sum := { digest, name |
    self:line(digest:concat(options:binary:ifElse({ " *" }, { "  " }))
                    :concat(name)) }.

report:error := { name, why |
    system:writeError("sha256sum: {}: {}\n":fill([name, why])).
    self:failed := true }.

; ---------------------------------------------------------------------------
; What is wrong with a name, in one place
;
; Two things can be, and the order matters: `fileExists` deliberately answers
; **false** for a directory -- it answers what `readFile` would say about one --
; so `isDirectory` has to be asked first or a directory is reported as missing.
;
; **This is one message because the two callers had already drifted apart.**
; Hashing a named directory said *Is a directory* and a directory named inside a
; `-c` list said *No such file or directory*, which is the oracle's answer in
; the first case and not in the second. Two copies of a three-line decision, one
; of them corrected and the other not: [5.5](../docs/COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done)
; in miniature, inside a single file.

path := object:new.

; nil when the name is usable, and what to say about it when it is not.
path:complaint := { name |
    name:equals("-"):ifElse(
        { nil },
        { system:isDirectory(name):ifElse(
            { "Is a directory" },
            { system:fileExists(name):ifElse(
                { nil },
                { "No such file or directory" }) }) }) }.

; ---------------------------------------------------------------------------
; Hashing what was named
;
; A file that cannot be read is reported and the rest are still done, which is
; what the tool does and is the opposite of how every other program here treats
; an error. `sha256sum a b c` is three questions rather than one, and answering
; two of them is better than answering none.

run := object:new.

run:one := { name | | why |
    why := path:complaint(name).
    why:notNil:ifElse(
        { report:error(name, why) },
        { name:equals("-"):ifElse(
            { report:sum(sha256:ofStdin, "-") },
            { { report:sum(sha256:ofFile(name), name) }:onError({ e |
                  report:error(name, e:message) }) }) }) }.

run:sums := {
    options:files:size:equals(#0):ifElse(
        { report:sum(sha256:ofStdin, "-") },
        { options:files:do({ name | self:one(name) }) }) }.

; ---------------------------------------------------------------------------
; Checking a list
;
; A line is sixty-four hex digits, a space, a space or a `*`, and a name. The
; name runs to the end of the line, spaces and all, which is why it is taken by
; position rather than by splitting.
;
; **A name stops at the first NUL**, and that is not a convenience. A Solum
; string is length-counted and may hold a NUL anywhere; a Unix filename may not
; hold one at all, so a name read out of a list and carried past a NUL is not a
; name. Cutting it there is what makes a `-z` list readable -- one entry ends in
; a NUL rather than a newline -- and it is also what stops the program being
; *silently* wrong about a list of several `-z` entries, where everything after
; the first name is another entry rather than part of this one.
;
; The first draft did not cut, and the answer it gave is worth recording because
; nothing looked broken: it printed
; `h.txt<NUL>e258...  w.txt: OK`. **The digest was right.** Every filesystem
; message in this language hands the path to C, which stops at the NUL, so
; `fileExists` and `readFile` both quietly saw `h.txt` and agreed with each
; other about a file the program had not asked for. See
; [ideas.md](../docs/ideas.md#a-path-with-a-nul-in-it-is-silently-a-different-path).

check := object:new.
check:bad := #0.                    ; lines that were not checksum lines
check:wrong := #0.                  ; files whose digest did not match

check:isHex := { s |
    s:size:equals(#64):and({ | ok |
        ok := true.
        [#1, #64]:loop({ i | | c |
            c := s:at(i).
            c:greaterOrEqual("0"):and({ c:lessOrEqual("9") })
                :or({ c:greaterOrEqual("a"):and({ c:lessOrEqual("f") }) })
                :ifFalse({ ok := false }) }).
        ok }) }.

check:line := { text, source, number | | want, mark, name, ok, why |
    ; [3.2](../docs/ROADMAP.md#32-no-non-local-return) is why this is a flag
    ; being carried rather than five guards each leaving the block. Four
    ; conditions have to hold before the line is a checksum line, they are
    ; cheapest to test in order, and none of them can end the method.
    ok := text:size:greaterOrEqual(#67).
    ok:ifTrue({
        want := text:copyFrom(#1, #64):asLowercase.
        ok := self:isHex(want) }).
    ok:ifTrue({ ok := text:at(#65):equals(" ") }).
    ok:ifTrue({
        mark := text:at(#66).
        ok := mark:equals(" "):or({ mark:equals("*") }) }).

    ok:ifElse(
        { name := text:copyFrom(#67, text:size).
          why := path:complaint(name).
          ; The tool on this machine writes a second space in front of the name
          ; here, having kept the separator that stood before it in the list.
          ; This does not, and check.sh says so among the differences it
          ; expects.
          why:notNil:ifElse(
              { report:error(name, why) },
              { self:verify(name, want) }) },
        { self:malformed(source, number) }) }.

check:verify := { name, want |
    { | got |
      got := name:equals("-"):ifElse({ sha256:ofStdin }, { sha256:ofFile(name) }).
      got:equals(want):ifElse(
          { report:line("{}: OK":fill([name])) },
          { self:wrong := self:wrong:add(#1).
            report:line("{}: FAILED":fill([name])) }) }
        :onError({ e | report:error(name, e:message) }) }.

check:malformed := { source, number |
    self:bad := self:bad:add(#1).
    options:warn:ifTrue({
        system:writeError("sha256sum: {}: {}: improperly formatted SHA256 checksum line\n"
                              :fill([source, number:asString])) }) }.

check:run := { | text, lines, number |
    options:files:size:equals(#0):ifTrue({
        error:raise("-c wants a file of checksums") }).
    options:files:do({ source |
        system:fileExists(source):ifElse(
            { text := system:readFile(source).
              lines := text:split("\n").

              ; **A blank line is a malformed line**, and the last piece of the
              ; split is not a line at all -- it is what a final newline leaves
              ; behind. Dropping every empty piece was the first draft and it
              ; was wrong: `-c -w` on a list with a blank line in the middle
              ; numbers it and counts it, and the oracle is what said so. The
              ; comment this replaced claimed a blank line was fine "in either
              ; tool", which had not been tried.
              lines:size:greaterThan(#0)
                  :and({ lines:at(lines:size):size:equals(#0) })
                  :ifTrue({ lines := lines:copyFrom(#1, lines:size:sub(#1)) }).

              number := #0.
              lines:do({ line | | cut, at |
                  number := number:add(#1).
                  ; Cut at the first NUL rather than trimming the last, for
                  ; the reason in the paragraph above this object.
                  at := line:indexOf(#0:asCharacter).
                  cut := at:isNil:ifElse(
                      { line },
                      { line:copyFrom(#1, at:sub(#1)) }).
                  self:line(cut, source, number) }) },
            { report:error(source, "No such file or directory") }) }).

    ; Singular and plural, because the tool writes them and a comparison that
    ; runs one file at a time would never notice which.
    self:wrong:greaterThan(#0):ifTrue({
        system:writeError("sha256sum: WARNING: {} computed checksum{} did NOT match\n"
            :fill([self:wrong:asString,
                   self:wrong:equals(#1):ifElse({ "" }, { "s" })])).
        report:failed := true }).
    self:bad:greaterThan(#0):ifTrue({
        system:writeError("sha256sum: WARNING: {} line{} {} improperly formatted\n"
            :fill([self:bad:asString,
                   self:bad:equals(#1):ifElse({ "" }, { "s" }),
                   self:bad:equals(#1):ifElse({ "is" }, { "are" })])) }) }.

; ---------------------------------------------------------------------------
; The demonstration

demonstrate := { | path, sums, text |
    "sha256sum -- the SHA-256 of a file, and the check of one.":display.
    "":display.

    "The three vectors FIPS 180-4 prints, which are the ones every":display.
    "implementation is held against before it is held against anything else:":display.
    "":display.
    [["", "the empty message"],
     ["abc", "\"abc\""],
     ["abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      "the 56-byte one, which is two blocks because the padding needs nine"]]
        :do({ pair | | s |
            s := sha256:start.
            s:update(pair:at(#1)).
            "  {}  {}":fill([s:digest, pair:at(#2)]):display }).
    "":display.

    system:makeDirectory("build").
    path := "build/sha256sum-demo.txt".
    sums := "build/sha256sum-demo.sums".
    text := "Every byte of this file was written by the program now hashing it,
which is how a program here demonstrates itself without being
handed anything first.
".
    system:writeFile(path, text).

    "And a file of {} bytes, written, then read back in 64 KB pieces:"
        :fill([text:size]):display.
    "":display.
    "  $ sha256sum {}":fill([path]):display.
    options:files := [path].
    run:sums.
    "":display.

    "The same digest written to a list, and the list checked:":display.
    "":display.
    system:writeFile(sums, "{}  {}\n":fill([sha256:ofFile(path), path])).
    "  $ sha256sum -c {}":fill([sums]):display.
    options:files := [sums].
    check:run.
    "":display.

    "And the same list against a file that has changed underneath it:":display.
    "":display.
    system:appendFile(path, "one more line, and a different answer\n").
    "  $ sha256sum -c {}":fill([sums]):display.
    check:wrong := #0.
    check:run.
    "":display.

    "  /sbin/sha256sum answers the same bytes to all of that.":display.
    system:remove(path).
    system:remove(sums) }.

; ---------------------------------------------------------------------------
; No arguments means two different things, and this is the second program to
; have that
;
; `tail` was the first, and it wrote the reasoning down: the house rule says a
; program here runs on input it carries, and `... | sha256sum` says read standard
; input, and both are typed as an empty command line.
;
; **`system:isTerminal('input)` separates them**, and it exists because this
; program was the second to ask.
;
; **It used to be `keyWaiting(0.0):not` here too, and that was wrong** in a way
; neither program noticed: a pipe that is open, empty and not yet finished
; answers false just as an idle terminal does, so
; `{ sleep 1; printf x; } | solvm sha256sum.sob` printed the demonstration and
; hashed nothing. Building the message is what found it, which is not what the
; entry expected to buy.
; [6.40](../docs/COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done)
; has the account.

{ system:arguments:size:equals(#0):and({ system:isTerminal('input) }):ifElse(
    { demonstrate:value },
    { options:read(system:arguments).
      options:check:ifElse({ check:run }, { run:sums }).
      report:failed:ifTrue({ system:exit(#1) }) }) }
    :onError({ e |
        system:writeError("sha256sum: ":concat(e:message):concat("\n")).
        system:exit(#1) }).

; ---------------------------------------------------------------------------
; What this program found
;
; It was written to produce one number, and it produced it. The rest of what is
; below was not predicted by the entry that asked for it.
;
; ---------------------------------------------------------------------------
; The number, which is what it was for
;
; **208 bytecode instructions per byte hashed, at 4.3 nanoseconds each.**
;
; Measured rather than counted. `solvm --steps=N` stops a program after N
; instructions and exits 124, so the smallest N that lets a run finish is the
; exact instruction count of that run, and a binary search finds it. Hashing
; files of 0, 64, 640 and 6400 bytes:
;
;     bytes    instructions     blocks    per block
;     0              14,671          1
;     64             28,049          2       13,378
;     640           147,767         11       13,302
;     6400        1,344,947        101       13,302
;
; **13,302 instructions per 64-byte block**, flat from ten blocks to a hundred,
; which is 207.8 per byte of message. The same search on a megabyte answers
; **217,955,855**, against 217,954,715 from the four rows above -- the fit
; confirmed to five figures, the difference being the sixteen chunk reads a
; megabyte needs and the small files do not.
;
; Ten megabytes take **9.30 s** in an `-O2` build on an M2 Pro, which is
; 2.179 billion instructions, so the interpreter is running **234 million
; instructions a second and each one costs 4.3 ns**. That is the answer to the
; question the survey said this program existed to ask, and no amount of reading
; the dispatch loop would have produced it.
;
; **In megabytes: 1.08 a second.** Beside it, the two hashes on this machine,
; each on the same 200 MB:
;
;     /sbin/sha256sum          ~1800 MB/s     C, and the M2's SHA instructions
;     shasum -a 256             ~320 MB/s     Perl, calling a C library
;     this program                1.08 MB/s
;
; The first of those is not a fair comparison and is worth printing anyway: the
; distance between an interpreter and a CPU instruction that does a whole round
; is three orders of magnitude, and it is the honest scale of what a hosted
; hash costs. Perl's is the interesting one -- it is about three hundred times
; faster while being an interpreter too, because it is not interpreting the
; hash.
;
; **And the default build costs more here than anywhere measured.** `make`
; builds `-g` with no optimiser ([performance.md](../docs/performance.md)),
; where the same ten megabytes take 46.0 s rather than 9.30 -- **0.22 MB/s, and
; 4.9x**. The nine benchmarks put that flag at 1.9x to 4.1x, so this is outside
; the range they cover, which is what a program that is nothing but arithmetic
; inside the dispatch loop should be expected to do.
;
; ---------------------------------------------------------------------------
; The mask, which is the ergonomic half of the question
;
; The survey asked for "an ergonomic report on whether a mask after every add
; reads as arithmetic or as bookkeeping". **It reads as bookkeeping**, and the
; reason is that it is not in the standard. FIPS 180-4 writes
;
;     T1 = h + S1 + ch + K[t] + W[t]
;
; and this file writes that with `:bitAnd(mask)` on the end, so every line the
; reader wants to check against the standard has a term in it the standard does
; not have. There are twenty-three of them in `sha256:block`.
;
; **And not one of them is a workaround.** A 64-bit signed integer holds the sum
; of five 32-bit values with fifty-nine bits to spare, so the arithmetic is
; exact at every step and the mask is a *narrowing* rather than a correction --
; which is the argument the [At a glance](../docs/ideas.md#at-a-glance) table
; makes for refusing byte, word and long, and this program is the first thing
; here to test it. It passes. `byte`, `word` and `long` would have removed
; twenty-three sends and added a coercion rule to every arithmetic operation in
; the language, and this program is not evidence for that trade.
;
; **What it is evidence for is smaller and was not on any list**: there is no
; infix notation for bit operations. `@expr` covers `+ - * / ^`, the six
; comparisons and `~ & |` -- where `&` and `|` are *logical* and short-circuit
; -- so a file that is nothing but shifts, xors and masks is the one file here
; that cannot use the notation at all. That is not an argument for adding them:
; `a & b` already means something, `<<` and `>>` next to `<` and `>` in a
; language with no reserved words is a lexing question rather than a grammar
; one, and one program is one program. It is written down because a notation
; introduced for "a formula you are transcribing" met a formula it could not
; transcribe.
;
; ---------------------------------------------------------------------------
; A third of the program was a method call
;
; `rotr(x, n)` is the one operation SHA-256 does that this language has no
; message for, and writing it as a method is the obvious thing:
;
;     sha256:rotr := { x, n |
;         x:shiftRight(n):bitOr(x:shiftLeft(#32:sub(n))):bitAnd(mask) }.
;
; Ten calls per round and four per step of the message schedule. Written out
; instead, on a megabyte, and all three answer the same digest:
;
;     rotr as a method everywhere                 1.36 s   0.74 MB/s
;     written out in the sixty-four rounds        1.10 s   0.91 MB/s   1.24x
;     written out in the message schedule too     0.92 s   1.09 MB/s   1.48x
;
; **The arithmetic is identical in all three.** What the method cost was a frame
; and a return, and it was **a third** of the whole program -- 32% of the
; readable version's running time, of which the message schedule is 13 points
; and the rounds the other 19. That is a number to
; hold against
; [the inline cache entry](../docs/ideas.md#an-inline-cache-at-the-send-site),
; which found dispatch to be 9.7% of the benchmark that asked for it: this is
; not lookup, it is the call itself, and it is the largest single thing measured
; in this program.
;
; It also says something about where a helper belongs. A method named for what
; it does is right almost everywhere and wrong in the one loop that runs
; thirteen thousand instructions per sixty-four bytes.
;
; ---------------------------------------------------------------------------
; [3.2](../docs/ROADMAP.md#32-no-non-local-return) arrived where it was not
; expected
;
; `tail`'s entry predicted that 3.1 and 3.2 would not appear, and for `tail`
; they did not. They appear here, in the half of the program that has nothing to
; do with hashing: `check:line` decides whether a line of a checksum list is a
; checksum line, four conditions have to hold, each is cheapest to test in
; order, and none of them can end the method. It is written as a flag carried
; through four `ifTrue`s.
;
; **It is not the idiom
; [ideas.md](../docs/ideas.md#an-early-exit-from-a-loop) is about**, and the
; difference is worth keeping straight because a first draft of this paragraph
; called it the seventh instance of one. That entry is about
; [3.13](../docs/ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing):
; a *loop* that must stop from inside, carrying a boolean whose only job is to
; stop it. There is no loop here. This is a straight-line guard chain that wants
; a *return*, which is 3.2, and the same spelling arrives at it from a different
; limitation. The entry also says it has stopped counting files, having had that
; number go stale twice -- so adding one to it would have been the wrong thing
; twice over.
;
; **The hashing wanted nothing.** Every loop in `sha256:block` runs a fixed
; number of times and none of them wants out early, which is what a specified
; algorithm looks like. The gap is in the *parsing*, which is the same place it
; has always been.
;
; ---------------------------------------------------------------------------
; The second program to want an `isatty`, which is the trigger firing -- and
; then the workaround turning out to be wrong
;
; `tail` found that `keyWaiting(0.0)` answers *is standard input a terminal* by
; accident, and its entry said: one caller, and a workaround that is exact
; rather than approximate. This program is the second caller, for the same
; reason -- an empty command line means *demonstrate yourself* to the house rule
; and *read standard input* to the tool -- and
; [ideas.md](../docs/ideas.md#two-absences-noticed-on-2026-08-31-that-nothing-has-asked-for)
; had named a second program as the trigger. It fired, and
; `system:isTerminal('input)` was built.
;
; **Building it found the workaround was not exact.** The case for the entry was
; only that the answer arrived through the wrong message; there was no defect to
; fix, or so both programs said. There was: `keyWaiting(0.0)` answers false for
; an idle terminal *and* for a pipe that is open, empty and not yet finished, so
; `{ sleep 1; printf x; } | solvm sha256sum.sob` printed the demonstration and
; hashed nothing.
;
; **Nothing was going to catch it.** A pipeline typed at a prompt or written in
; a test has its first byte ready before the program starts, so the case is
; invisible everywhere it would normally be looked for; it needs a slow writer,
; which is not a thing anybody constructs on purpose. It was found by asking
; what the old spelling had actually been answering -- the question you only ask
; when you are replacing something.
; [6.40](../docs/COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done)
; has the account.
;
; ---------------------------------------------------------------------------
; The second caller of the ranged read, going the other way
;
; [3.22](../docs/COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done)
; chose a range over a handle and `tail` was written to find out whether that
; shape survived contact. It seeks *backwards* to a place it has computed. This
; walks forwards from byte one and never looks back, which is the other half of
; what a file handle is usually for, and it wanted nothing the call does not
; have. **A shape that serves both a seek and a scan with no state between calls
; is the entry's argument holding up under a use it did not have in mind.**
;
; **And the second caller found the price the first could not.** A range with no
; handle means no open is held, so every call opens the file again -- and an
; open costs about 30 microseconds on this machine against 0.65 for the `stat`
; behind `fileSize`, forty-five times. `tail` does one or two reads per
; invocation and cannot see that. A program that streams does it 16,384 times a
; megabyte, so the chunk size stops being an arbitrary constant and becomes the
; thing that amortises the open: 64 bytes costs 62% more than 65536, and the
; curve is flat from about four kilobytes.
;
; **That is a price and not a defect**, and it does not argue for a handle. The
; open is `fopen`'s -- C measures 28 us for the same open, read and close -- so
; a handle would move the cost rather than remove it, and it would buy back
; exactly the lifetime the entry refused. What it argues for is a sentence in
; the reference, since a caller choosing a chunk size is choosing how often to
; pay 30 microseconds and nothing said so.
;
; ---------------------------------------------------------------------------
; And the oracle earned itself twice in ten minutes
;
; **Once against this program.** `check:run` dropped every empty piece of the
; split, and carried a comment saying "a blank line is not a malformed line in
; either tool" -- which had not been tried. It is: `/sbin/sha256sum -c -w` on a
; list with a blank line in the middle numbers that line and counts it. The
; comment was written by somebody who was thinking about the trailing newline
; and generalised from it, which is precisely the shape
; [method.md](../docs/method.md#a-sentence-that-was-true-when-written-is-not-checked-by-anything)
; describes. `programs/sha256sum/check.sh` carries the case that found it.
;
; **Once against itself.** In `-c` mode the oracle reports a file that is not
; there as `sha256sum:  nosuch.txt: No such file or directory` -- two spaces,
; because it kept the separator that stood in front of the name in the list.
; This writes one, and check.sh lists it as a divergence rather than copying it,
; on the grounds that matching an oracle byte for byte is a means and not the
; point.
;
; ---------------------------------------------------------------------------
; And two things the review pass found, which the writing had not
;
; **The same decision, written twice, and the two copies disagreed.** Hashing a
; named directory answered *Is a directory*; a directory named inside a `-c`
; list answered *No such file or directory*. Both lines were three lines long,
; one had been corrected during the writing and the other had not, and nothing
; connected them. It is
; [5.5](../docs/COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done)
; -- the same object written five times, where a fix to one is a fix nobody
; makes to the other four -- **at a scale small enough to happen inside a single
; file in a single afternoon**, which is not the scale that entry was written
; about. `path:complaint` is the one place now.
;
; **And the usage line is a true sentence about a smaller thing than the tool.**
; This file's header said the subset here is the whole of `sha256sum [-bctwz]`,
; "which is the whole of the usage line of the tool on this machine". Both
; halves are true and together they read as *this is the whole tool*, which it
; is not: `/sbin/sha256sum` also answers to `--binary`, `--text`, `--check`,
; `--warn`, `--zero`, `--tag`, `--quiet`, `--status`, `--help` and `--version`,
; and its usage line mentions none of the ten. Found by typing them, not by
; reading. Three of them are now in `sha256sum/differ/`, so the subset is a
; corpus that fails rather than a sentence nobody rechecks.
;
; ---------------------------------------------------------------------------
; A difference that is not one
;
; There is a third difference which is not one, and it is worth knowing about
; before writing another of these: captured with `2>&1` the two tools order the
; `WARNING` line and the per-file lines differently, because the oracle's
; standard output is block-buffered when it is a file and its warning is not.
; Both streams are byte-identical when they are kept apart. `programs/oracle.sh`
; merges them, so a `-c` corpus could not have lived there even if it could have
; carried the files.
