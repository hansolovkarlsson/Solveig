; gzip.sol -- inflate: a gzip stream back into the bytes it was made from.
;
; Run with:  ./bin/solas programs/gzip.sol && ./bin/solvm programs/gzip.sob
;
;     solvm gzip.sob -d file.gz          writes `file`, removes `file.gz`
;     solvm gzip.sob -dk file.gz         keeps the input
;     solvm gzip.sob -dc file.gz         writes to standard output instead
;     solvm gzip.sob -t file.gz          checks it and prints nothing
;     solvm gzip.sob -l file.gz          the sizes and the ratio
;     ... | solvm gzip.sob -d            from a pipe, to standard output
;
; **Decompression only.** `gzip` without `-d` compresses, and that is a second
; program and a harder one -- a match finder, a hash chain and the choice of
; how to code each block. This one is `gunzip`, which is what the survey in
; [ideas.md](../docs/ideas.md#gzip--d--the-one-that-answers-the-question-behind-the-neural-net)
; asked for and is the half where the answers are already written down: RFC 1951
; for DEFLATE and RFC 1952 for the container around it.
;
; The oracle is `/usr/bin/gzip`, which is Apple gzip 479 here, on files it made
; itself. That is the strongest form available: every case is a round trip, so
; the oracle does not merely agree with this program, it produced the input.
;
;     sh programs/gzip/sweep.sh          the corpus, and this repository's files

; ---------------------------------------------------------------------------
; The twenty-second program here, and what it was written to measure
;
; Every other program in this directory reads text and reports on its structure,
; or computes over it. This one holds a **32 KB sliding window** and copies
; inside it, which is the array-heavy workload
; [the survey](../docs/ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31)
; named and nothing here had written.
;
; The prediction it was written against, kept in its own words:
;
;     A `SolValue` is a tag and a union, so a 32 KB window is 32,768 tagged
;     values rather than 32,768 bytes, and every access is a send. Predicted
;     finding: the cost of that, in a number, on a problem where the right
;     answer is known to the byte.
;
; **The number is at the bottom of this file**, with the three other things it
; found -- one of which contradicts an open roadmap entry that names this
; program by name.
;
; ---------------------------------------------------------------------------
; Bits arrive in the opposite order from the bytes, and that is the whole trick
;
; DEFLATE packs its bit fields **least significant bit first** within a byte,
; and its Huffman codes **most significant bit first** within the code. Those
; two are not a contradiction, they are two different things being packed, and
; every implementation of this format has one paragraph explaining it because
; every implementer gets it wrong once.
;
; `bits` below takes n bits as an integer, low bit first, which is right for
; every fixed-width field in the format: the block header, the lengths, the
; extra bits, `LEN` and `NLEN`. `decode` takes them one at a time and shifts
; each into the *bottom* of a code it is accumulating, which builds the code
; most significant bit first. One buffer, two readings of it.

inBytes := array:new.       ; the piece in hand, one integer per byte
inPos   := #1.              ; the next byte to take from it, one-based
inMore  := nil.             ; a block answering the next piece, or nil for a
                            ; source that arrives in one
inTotal := #0.              ; how many bytes have come out of the source, which
                            ; is what `-l` prints as the compressed size
inChunk := #4096.           ; and how many are asked for at a time -- the size
                            ; of the window `readUpTo` answers out of, so asking
                            ; for more would not get more
bitBuf  := #0.              ; bits taken from the stream and not yet handed out
bitCnt  := #0.              ; how many of them there are -- never more than 7
                            ; after a call, since `bits` fills only as far as it
                            ; has to and then takes what it asked for

; A string as an array of integers, once, rather than `at(i):asByte` at every
; read.
;
; **This is a measurement and not a preference.** `string:at` answers a
; one-character string and `asByte` its number, so a byte costs two sends and an
; allocation every time it is looked at -- and the bit reader looks at each byte
; once but the *loop condition* around it runs per bit. Converting the stream up
; front is one pass of two sends a byte, after which a byte is one `array:at`.
; Over a 73 KB stream the conversion costs 8 ms and saves rather more than that.
;
; It also bounds the program's appetite in a way worth saying out loud: the
; input is held twice over, as a string and as an array of boxed integers, and
; the array is the expensive one.
bytesOf := { text | | out, i, n |
    out := array:new. i := #1. n := text:size.
    { i:lessOrEqual(n) }:whileTrue({
        out:add(text:at(i):asByte).
        i := i:inc }).
    out }.

; And back again, in chunks. `join` over four hundred thousand one-byte strings
; is one allocation per byte and one enormous array; four thousand at a time is
; the same work with a bounded high-water mark.
textOf := { bytes | | parts, chunk, i, n |
    parts := array:new. chunk := array:new. i := #1. n := bytes:size.
    { i:lessOrEqual(n) }:whileTrue({
        chunk:add(bytes:at(i):asCharacter).
        chunk:size:greaterOrEqual(#4096):ifTrue({
            parts:add(chunk:join("")).
            chunk := array:new }).
        i := i:inc }).
    chunk:size:greaterThan(#0):ifTrue({ parts:add(chunk:join("")) }).
    parts:join("") }.

; ---------------------------------------------------------------------------
; Where the bytes come from
;
; Two sources and one reader. `resetInput` is a stream that arrived whole --
; a named file, and the demonstration below -- and `resetStream` is standard
; input, taken in pieces with
; [`readUpTo`](../docs/REFERENCE.md#up-to-n-bytes-when-neither-a-line-nor-a-byte-will-do).
;
; **The refill replaces the piece rather than appending to it**, which is the
; whole of what this buys. Nothing here ever looks backwards -- `inPos` only
; ever moves forward, the window a back-reference reads from is `out` and not
; the input -- so a piece that has been read is not needed again and is not
; kept. The stream route therefore holds 4,096 input bytes however long the
; stream is, where reading it whole held one string and one integer per byte of
; the entire input.

; Answers whether a byte is there to take, refilling first if the piece in hand
; is spent. **A source that is finished stays finished**: `readUpTo` answers nil
; at the end and goes on answering nil, so asking again is allowed. It is not
; free -- the window is empty, so each call past the end is a `read` that
; answers nothing -- but `readMembers` asks once, to find out whether another
; member follows, and `nextByte` does not ask again after that.
inReady := { | piece |
    inPos:greaterThan(inBytes:size):ifTrue({
        piece := inMore:isNil:ifElse({ nil }, { inMore:value }).
        piece:isNil:ifFalse({
            inBytes := piece.
            inPos := #1.
            inTotal := inTotal:add(piece:size) }) }).
    inPos:lessOrEqual(inBytes:size) }.

resetInput := { bytes |
    inBytes := bytes. inPos := #1. inMore := nil. inTotal := bytes:size.
    bitBuf := #0. bitCnt := #0 }.

resetStream := {
    inBytes := array:new. inPos := #1. inTotal := #0.
    bitBuf := #0. bitCnt := #0.
    inMore := { | text |
        text := system:readUpTo(inChunk).
        text:isNil:ifElse({ nil }, { bytesOf:value(text) }) } }.

; **The guard is written twice on purpose.** `inReady` says the same thing this
; first line says, and calling it unconditionally is one block send per byte of
; input -- 11 instructions a byte, measured, which is 1.8% of the whole program
; and is paid by the named-file route as well, where nothing ever refills. So
; the test that is true almost always stays here, and the call happens only when
; the piece in hand has run out.
nextByte := { | b |
    inPos:greaterThan(inBytes:size):ifTrue({
        inReady:value:ifFalse({
            error:raise("unexpected end of input") }) }).
    b := inBytes:at(inPos).
    inPos := inPos:inc.
    b }.

bits := { n | | v |
    { bitCnt:lessThan(n) }:whileTrue({
        bitBuf := nextByte:value:shiftLeft(bitCnt):bitOr(bitBuf).
        bitCnt := bitCnt:add(#8) }).
    v := bitBuf:bitAnd(#1:shiftLeft(n):sub(#1)).
    bitBuf := bitBuf:shiftRight(n).
    bitCnt := bitCnt:sub(n).
    v }.

; A stored block and everything outside the DEFLATE stream is byte-aligned.
; Discarding is correct rather than approximate: `bits` never leaves more than
; seven, so what is thrown away is always the tail of one byte.
alignToByte := { bitBuf := #0. bitCnt := #0 }.

; ---------------------------------------------------------------------------
; Canonical Huffman, counted rather than tabulated
;
; A DEFLATE table is given as a code **length** per symbol and nothing else; the
; codes themselves follow from the lengths by a rule both ends know. The
; representation here is the one from `puff.c`, which is the reference
; decompressor RFC 1951 ships with, and it is two arrays:
;
;     counts   how many symbols have each code length, 1 to 15
;     symbols  every symbol that has a code, sorted by length and then by symbol
;
; Decoding walks the lengths from the shortest, keeping the first code of each
; length and how many there are, and stops when the code it has accumulated
; falls inside that length's run. **No table is built**, which is why a dynamic
; block costs nothing to set up and something to read -- the opposite trade from
; a lookup table, and the right one when a block may be three symbols long.
;
; A table is `[counts, symbols]` rather than an object with two slots. That is
; the only place in this file where the reason is speed: a slot read is a send
; and `decode` does two of them per symbol, of which there are one per byte of
; output.
huffmanOf := { lengths | | counts, symbols, offs, i, n, len, at |
    counts := array:new.
    #15:repeat({ counts:add(#0) }).
    n := lengths:size.
    i := #1.
    { i:lessOrEqual(n) }:whileTrue({
        len := lengths:at(i).
        len:greaterThan(#0):ifTrue({
            counts:atPut(len, counts:at(len):add(#1)) }).
        i := i:inc }).

    ; Where each length's run begins in `symbols`.
    offs := array:new.
    at := #0.
    [#1, #15]:loop({ l |
        offs:add(at).
        at := at:add(counts:at(l)) }).

    symbols := array:new.
    at:repeat({ symbols:add(#0) }).
    i := #1.
    { i:lessOrEqual(n) }:whileTrue({
        len := lengths:at(i).
        len:greaterThan(#0):ifTrue({
            offs:atPut(len, offs:at(len):add(#1)).
            symbols:atPut(offs:at(len), i:sub(#1)) }).
        i := i:inc }).

    [counts, symbols] }.

; One symbol, a bit at a time.
;
; **The loop is left by a flag** ([3.13](../docs/ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing)),
; and this is the shape that entry is about: the answer is found in the middle
; of the body and there is nothing to do afterwards. `sym` is both the result
; and the condition, which at least means the flag is not a second variable.
decode := { table | | counts, symbols, code, first, index, len, count, sym |
    counts := table:at(#1). symbols := table:at(#2).
    code := #0. first := #0. index := #0. len := #1. sym := nil.
    { sym:isNil }:whileTrue({
        len:greaterThan(#15):ifTrue({
            error:raise("a code in this stream is not in its table") }).
        code := code:bitOr(bits:value(#1)).
        count := counts:at(len).
        code:sub(first):lessThan(count):ifElse(
            { sym := symbols:at(index:add(code):sub(first):add(#1)) },
            { index := index:add(count).
              first := first:add(count):shiftLeft(#1).
              code := code:shiftLeft(#1).
              len := len:inc }) }).
    sym }.

; ---------------------------------------------------------------------------
; The tables the format fixes, and the two the length codes index

lengthBase := [#3, #4, #5, #6, #7, #8, #9, #10, #11, #13, #15, #17, #19, #23,
               #27, #31, #35, #43, #51, #59, #67, #83, #99, #115, #131, #163,
               #195, #227, #258].
lengthExtra := [#0, #0, #0, #0, #0, #0, #0, #0, #1, #1, #1, #1, #2, #2, #2, #2,
                #3, #3, #3, #3, #4, #4, #4, #4, #5, #5, #5, #5, #0].

distanceBase := [#1, #2, #3, #4, #5, #7, #9, #13, #17, #25, #33, #49, #65, #97,
                 #129, #193, #257, #385, #513, #769, #1025, #1537, #2049, #3073,
                 #4097, #6145, #8193, #12289, #16385, #24577].
distanceExtra := [#0, #0, #0, #0, #1, #1, #2, #2, #3, #3, #4, #4, #5, #5, #6,
                  #6, #7, #7, #8, #8, #9, #9, #10, #10, #11, #11, #12, #12,
                  #13, #13].

; The order the code-length code's own lengths arrive in. It is not sorted, and
; the reason is that the codes near the front are the ones a small block is
; likely to use, so a truncated list still says something.
lengthOrder := [#16, #17, #18, #0, #8, #7, #9, #6, #10, #5, #11, #4, #12, #3,
                #13, #2, #14, #1, #15].

fixedLiterals := nil.
fixedDistances := nil.

buildFixed := { | lengths |
    lengths := array:new.
    #144:repeat({ lengths:add(#8) }).
    #112:repeat({ lengths:add(#9) }).
    #24:repeat({ lengths:add(#7) }).
    #8:repeat({ lengths:add(#8) }).
    fixedLiterals := huffmanOf:value(lengths).

    lengths := array:new.
    #30:repeat({ lengths:add(#5) }).
    fixedDistances := huffmanOf:value(lengths) }.

; ---------------------------------------------------------------------------
; The three kinds of block
;
; `out` is the whole output rather than a ring buffer of the last 32 KB, and
; that is a decision worth naming. A ring costs a modulo on every access and
; buys back memory this program then has to spend again to write the file --
; `writeFile` takes a string, so the bytes have to exist all at once anyway.
; **The window is therefore free**, and a back-reference is `out:at` at an
; index that is `out:size` minus the distance.

out := array:new.

storedBlock := { | len, nlen, i |
    alignToByte:value.
    len := nextByte:value:bitOr(nextByte:value:shiftLeft(#8)).
    nlen := nextByte:value:bitOr(nextByte:value:shiftLeft(#8)).
    len:bitXor($FFFF):equals(nlen):ifFalse({
        error:raise("a stored block's length and its complement disagree") }).
    i := #0.
    { i:lessThan(len) }:whileTrue({
        out:add(nextByte:value).
        i := i:inc }) }.

; The compressed body, given the two tables to read it with. This is the loop
; the program's running time is in.
codedBlock := { literals, distances | | sym, len, dist, at, more, size |
    more := true.
    { more }:whileTrue({
        sym := decode:value(literals).
        sym:lessThan(#256):ifElse(
            { out:add(sym) },
            { sym:equals(#256):ifElse(
                { more := false },
                { sym:greaterThan(#285):ifTrue({
                      error:raise("a length code in this stream is not one") }).
                  len := lengthBase:at(sym:sub(#256))
                           :add(bits:value(lengthExtra:at(sym:sub(#256)))).
                  sym := decode:value(distances).
                  sym:greaterThan(#29):ifTrue({
                      error:raise("a distance code in this stream is not one") }).
                  dist := distanceBase:at(sym:inc)
                            :add(bits:value(distanceExtra:at(sym:inc))).
                  size := out:size.
                  dist:greaterThan(size):ifTrue({
                      error:raise("a distance reaches back before the start") }).
                  at := size:sub(dist):add(#1).

                  ; **A copy may overlap its own source**, and that is not a
                  ; defect to be guarded against -- it is how the format spells
                  ; a run. `dist` of 1 and `len` of 100 is a hundred of the same
                  ; byte, and reading one byte at a time through the array as it
                  ; grows produces exactly that. A block copy would not.
                  len:repeat({
                      out:add(out:at(at)).
                      at := at:inc }) }) }) }) }.

dynamicTables := { | hlit, hdist, hclen, lengths, code, i, n, sym, count, prev |
    hlit := bits:value(#5):add(#257).
    hdist := bits:value(#5):add(#1).
    hclen := bits:value(#4):add(#4).

    lengths := array:new.
    #19:repeat({ lengths:add(#0) }).
    i := #1.
    { i:lessOrEqual(hclen) }:whileTrue({
        lengths:atPut(lengthOrder:at(i):inc, bits:value(#3)).
        i := i:inc }).
    code := huffmanOf:value(lengths).

    ; The literal and the distance lengths arrive as **one** run-length coded
    ; list and are split afterwards, which is the format's doing rather than a
    ; convenience here: a repeat may straddle the boundary between them.
    n := hlit:add(hdist).
    lengths := array:new.
    prev := #0.
    { lengths:size:lessThan(n) }:whileTrue({
        sym := decode:value(code).
        sym:lessThan(#16):ifElse(
            { lengths:add(sym). prev := sym },
            { sym:equals(#16):ifTrue({
                  lengths:size:equals(#0):ifTrue({
                      error:raise("a repeat with nothing before it") }).
                  count := bits:value(#2):add(#3).
                  count:repeat({ lengths:add(prev) }) }).
              sym:equals(#17):ifTrue({
                  count := bits:value(#3):add(#3).
                  count:repeat({ lengths:add(#0) }).
                  prev := #0 }).
              sym:equals(#18):ifTrue({
                  count := bits:value(#7):add(#11).
                  count:repeat({ lengths:add(#0) }).
                  prev := #0 }) }) }).

    lengths:size:greaterThan(n):ifTrue({
        error:raise("the code lengths in this stream overrun their own count") }).

    [huffmanOf:value(lengths:copyFrom(#1, hlit)),
     huffmanOf:value(lengths:copyFrom(hlit:inc, n))] }.

inflate := { | last, kind, tables |
    last := false.
    { last:not }:whileTrue({
        last := bits:value(#1):equals(#1).
        kind := bits:value(#2).
        kind:equals(#0):ifTrue({ storedBlock:value }).
        kind:equals(#1):ifTrue({
            codedBlock:value(fixedLiterals, fixedDistances) }).
        kind:equals(#2):ifTrue({
            tables := dynamicTables:value.
            codedBlock:value(tables:at(#1), tables:at(#2)) }).
        kind:equals(#3):ifTrue({
            error:raise("block type 3 is reserved and this stream uses it") }) }) }.

; ---------------------------------------------------------------------------
; CRC-32, the one the trailer carries
;
; The same reflected polynomial `zlib` uses, built into a table of 256 once. The
; arithmetic stays under 2^32 throughout, so nothing here goes near
; [3.12](../docs/ROADMAP.md#312-no-shift-can-produce-a-negative-integer) -- the
; only shifts are to the right.

crcTable := nil.

buildCrc := { | c |
    crcTable := array:new.
    [#0, #255]:loop({ n |
        c := n.
        #8:repeat({
            c := c:bitAnd(#1):equals(#1):ifElse(
                { c:shiftRight(#1):bitXor($EDB88320) },
                { c:shiftRight(#1) }) }).
        crcTable:add(c) }) }.

crcOf := { bytes | | c, i, n |
    c := $FFFFFFFF. i := #1. n := bytes:size.
    { i:lessOrEqual(n) }:whileTrue({
        c := crcTable:at(c:bitXor(bytes:at(i)):bitAnd($FF):inc)
               :bitXor(c:shiftRight(#8)).
        i := i:inc }).
    c:bitXor($FFFFFFFF) }.

; ---------------------------------------------------------------------------
; The container, which is RFC 1952 and is mostly optional fields

le32 := { | a, b, c, d |
    a := nextByte:value. b := nextByte:value.
    c := nextByte:value. d := nextByte:value.
    a:bitOr(b:shiftLeft(#8)):bitOr(c:shiftLeft(#16)):bitOr(d:shiftLeft(#24)) }.

readUntilNul := { | s, b |
    s := "". b := nextByte:value.
    { b:equals(#0):not }:whileTrue({
        s := s:concat(b:asCharacter).
        b := nextByte:value }).
    s }.

; Answers a dictionary describing one member and leaves `inPos` after its
; trailer. `out` holds the bytes it produced.
readMember := { | flags, xlen, name, want, crc, isize, start, mtime |
    nextByte:value:equals(#31):ifFalse({
        error:raise("this is not a gzip file -- the first two bytes are wrong") }).
    nextByte:value:equals(#139):ifFalse({
        error:raise("this is not a gzip file -- the first two bytes are wrong") }).
    nextByte:value:equals(#8):ifFalse({
        error:raise("this stream is compressed with a method that is not deflate") }).
    flags := nextByte:value.
    mtime := le32:value.
    nextByte:value.                     ; XFL, which says how hard it tried
    nextByte:value.                     ; OS
    flags:bitAnd(#4):equals(#4):ifTrue({
        xlen := nextByte:value:bitOr(nextByte:value:shiftLeft(#8)).
        xlen:repeat({ nextByte:value }) }).
    name := flags:bitAnd(#8):equals(#8):ifElse({ readUntilNul:value }, { nil }).
    flags:bitAnd(#16):equals(#16):ifTrue({ readUntilNul:value }).
    flags:bitAnd(#2):equals(#2):ifTrue({ nextByte:value. nextByte:value }).

    start := out:size.
    inflate:value.
    alignToByte:value.

    want := le32:value.
    isize := le32:value.

    crc := crcOf:value(out:copyFrom(start:inc, out:size)).
    crc:equals(want):ifFalse({
        error:raise("the checksum does not match -- this stream is damaged") }).
    out:size:sub(start):bitAnd($FFFFFFFF):equals(isize):ifFalse({
        error:raise("the length does not match -- this stream is damaged") }).

    dictionary:of("name", name, "mtime", mtime, "size", out:size:sub(start)) }.

; Every member in the stream. gzip files concatenate, and `cat a.gz b.gz` is a
; valid one that decompresses to both -- which is the case an implementation
; that reads one member and stops gets wrong while looking right.
readMembers := { | members |
    out := array:new.
    members := array:new.
    members:add(readMember:value).
    { inReady:value }:whileTrue({
        members:add(readMember:value) }).
    members }.

; The two ways in, and the only difference between them is the source.
readAll := { bytes | resetInput:value(bytes). readMembers:value }.
readStream := { resetStream:value. readMembers:value }.

; ---------------------------------------------------------------------------
; The command line

wantStdout := false.
wantKeep := false.
wantTest := false.
wantList := false.
quiet := false.
operands := array:new.
programName := "gzip".

fail := { text |
    system:writeError(programName:concat(": "):concat(text):concat("\n")).
    system:exit(#1) }.

; `-dc` and `-d -c` are the same thing, which means the flags are letters and
; not words. `-d` is accepted and ignored: this program has nothing else to do.
parseArguments := { args | | a, i, j, c, seenDashes |
    seenDashes := false.
    i := #1.
    { i:lessOrEqual(args:size) }:whileTrue({
        a := args:at(i).
        ( seenDashes:not:and({ a:size:greaterThan(#1) })
              :and({ a:copyFrom(#1, #1):equals("-") }) ):ifElse(
            { a:equals("--"):ifElse(
                { seenDashes := true },
                { j := #2.
                  { j:lessOrEqual(a:size) }:whileTrue({
                      c := a:copyFrom(j, j).
                      c:equals("d"):ifTrue({ #0 }).
                      c:equals("c"):ifTrue({ wantStdout := true }).
                      c:equals("k"):ifTrue({ wantKeep := true }).
                      c:equals("t"):ifTrue({ wantTest := true }).
                      c:equals("l"):ifTrue({ wantList := true }).
                      c:equals("q"):ifTrue({ quiet := true }).
                      c:equals("f"):ifTrue({ #0 }).
                      ( "dcktlqf":indexOf(c):isNil ):ifTrue({
                          fail:value("unknown option -- ":concat(c)) }).
                      j := j:inc }) }) },
            { operands:add(a) }).
        i := i:inc }) }.

; `file.gz` becomes `file`, and so do the other suffixes gzip knows. A name it
; does not recognise has no output name, which is an error unless `-c`.
outputNameFor := { name | | endings, answer, e, i |
    endings := [".gz", ".z", "-gz", "-z", "_z", ".tgz", ".taz"].
    answer := nil.
    i := #1.
    { answer:isNil:and({ i:lessOrEqual(endings:size) }) }:whileTrue({
        e := endings:at(i).
        ( name:size:greaterThan(e:size)
              :and({ name:copyFrom(name:size:sub(e:size):inc, name:size)
                         :asLowercase:equals(e) }) ):ifTrue({
            answer := e:equals(".tgz"):or({ e:equals(".taz") }):ifElse(
                { name:copyFrom(#1, name:size:sub(#4)):concat(".tar") },
                { name:copyFrom(#1, name:size:sub(e:size)) }) }).
        i := i:inc }).
    answer }.

; ---------------------------------------------------------------------------
; The ratio `-l` prints, which is not the obvious one
;
; **The obvious formula is wrong on every line, and only the oracle says so.**
; `100 * (uncompressed - compressed) / uncompressed` is what a reader would
; write and what this file had; held against `gzip -l`, `18` bytes in a `27`
; byte file is **-44.5%** and the obvious formula says -50.0%.
;
; What BSD gzip computes is `print_ratio`, and it is doing integer arithmetic
; on purpose: `diff = uncompressed - compressed/2`, a shift loop to keep the
; multiply inside 32 bits, and then `diff * 2000 / uncompressed - 1000` to get
; ten times the percentage. The halving is not an approximation of anything --
; it is where the `- 1000` comes from, and the two together are one expression
; that has been algebraically rearranged to stay in integers.
;
; It also gives the floor: a file that did not shrink at all reports **-99.9%**
; rather than the true figure, because `diff` has gone non-positive and there is
; nothing left to divide. `18` bytes in a `38` byte file is -99.9% and so is a
; megabyte in a gigabyte.
;
; **Nobody would have found this by reading the format.** It is not in RFC 1952;
; it is in the tool, and it is the clearest thing this program found that a
; specification could not have told it.
ratioText := { uncompressed, compressed | | diff, u, p10, whole, tenth |
    u := uncompressed.
    diff := u:sub(compressed:div(#2)).
    p10 := diff:lessOrEqual(#0):ifElse(
        { #-999 },
        { { u:greaterThan($100000) }:whileTrue({
              diff := diff:shiftRight(#1).
              u := u:shiftRight(#1) }).
          u:equals(#0):ifElse({ #0 }, { diff:mul(#2000):div(u):sub(#1000) }) }).
    whole := p10:abs:div(#10).
    tenth := p10:abs:mod(#10).
    p10:lessThan(#0):ifElse({ "-" }, { "" })
        :concat(whole:asString):concat("."):concat(tenth:asString):concat("%") }.

; **The uncompressed size is the last member's**, not the sum of them, which is
; a divergence this program copies rather than corrects: `gzip -l` reads the
; four bytes at the end of the file and asks no further questions, so
; `cat a.gz b.gz` lists as though it held only `b`. Answering the true total
; would be more useful and would disagree with the oracle, and the rule here is
; that a divergence is written down rather than improved on quietly.
listOne := { path, size, members | | uncompressed, name |
    uncompressed := members:at(members:size):at("size").
    name := outputNameFor:value(path).
    name:isNil:ifTrue({ name := path }).
    system:write("{}{} {} {}\n":fill([
        size:asString("12"),
        uncompressed:asString("13"),
        ratioText:value(uncompressed, size):asString(">6"),
        name])) }.

listHeader := {
    system:write("  compressed uncompressed  ratio uncompressed_name\n") }.

; ---------------------------------------------------------------------------
; What it does with no arguments at all
;
; The house rule for these programs is that one run with nothing on the command
; line has to say something. A decompressor has nothing to say without input, so
; it carries some: the array below is a gzip stream, made by the oracle, of a
; sentence that is long enough to need a back-reference.
;
; **It is told apart from `... | gunzip` the way `sha256sum` does it**, by
; asking whether standard input is a terminal. An empty command line with a pipe
; behind it means the opposite thing from an empty command line at a prompt.

demonstration := [#31, #139, #8, #0, #0, #0, #0, #0, #2, #3, #11, #206, #207,
                  #41, #75, #205, #76, #87, #200, #44, #86, #72, #84, #200, #73,
                  #204, #75, #47, #77, #76, #79, #213, #81, #72, #204, #75, #65,
                  #226, #163, #202, #42, #148, #230, #149, #100, #230, #40, #20,
                  #231, #231, #166, #38, #229, #167, #84, #42, #148, #23, #101,
                  #150, #164, #130, #20, #20, #20, #229, #167, #23, #37, #230,
                  #42, #100, #230, #41, #100, #150, #232, #113, #1, #0, #181,
                  #24, #4, #228, #91, #0, #0, #0].

demonstrate := { | members |
    "gzip.sol -- a gzip stream, inflated:":display.
    "":display.
    members := readAll:value(demonstration).
    textOf:value(out):display.
    "":display.
    "{} bytes in, {} out, one member, checksum agreed."
        :fill([demonstration:size, out:size]):display }.

; ---------------------------------------------------------------------------
; One operand

readWhole := { path |
    { system:readFile(path) }:onError({ e |
        fail:value("{}: {}":fill([path, e:message])) }) }.

doOne := { path | | members, target, text |
    members := { path:equals("/dev/stdin"):ifElse(
                     { readStream:value },
                     { readAll:value(bytesOf:value(readWhole:value(path))) })
               }:onError({ e |
        fail:value("{}: {}":fill([path:equals("/dev/stdin"):ifElse(
                                      { "stdin" }, { path }),
                                  e:message])) }).
    wantList:ifTrue({ listOne:value(path, inTotal, members) }).
    wantTest:or({ wantList }):ifFalse({
        text := textOf:value(out).
        target := wantStdout:or({ path:equals("/dev/stdin") }):ifElse(
            { nil },
            { outputNameFor:value(path) }).
        target:isNil:ifElse(
            { system:write(text) },
            { system:writeFile(target, text).
              wantKeep:ifFalse({ system:remove(path) }) }) }) }.

main := { | args |
    buildFixed:value.
    buildCrc:value.
    args := system:arguments.
    parseArguments:value(args).

    operands:size:equals(#0):ifElse(
        { system:isTerminal('input):and({ args:size:equals(#0) }):ifElse(
            { demonstrate:value },
            { wantList:ifTrue({ listHeader:value }).
              doOne:value("/dev/stdin") }) },
        { wantList:ifTrue({ listHeader:value }).
          operands:do({ p |
              p:equals("-"):ifElse(
                  { doOne:value("/dev/stdin") },
                  { doOne:value(p) }) }) }) }.

main:value.

; ---------------------------------------------------------------------------
; What it found
;
; Apple M2 Pro, macOS 25.6.0, `solvm` built `-O2`. The instruction counts are
; exact rather than sampled: `--steps=N` stops a program after N instructions,
; so the smallest N that lets a run finish is that run's count, and a binary
; search finds it. `docs/REFERENCE.md` is the subject throughout -- 65,177 bytes
; of gzip in, 185,364 bytes out.
;
;     40,775,088 instructions          220 per byte of output
;     0.14 s, best of five             1.32 MB/s of output
;                                      291 million instructions a second
;
; ---------------------------------------------------------------------------
; 1. The window was the thing to measure, and it is 5% of the program
;
; **The prediction asked for the cost of a 32 KB window as 32,768 tagged values,
; and the answer is that it is nearly the cheapest part of the program.** Where
; the instructions actually go:
;
;     the Huffman decode, a bit at a time      28.8 M    70.7%
;     CRC-32 over the output                    4.63 M   11.4%    25 a byte
;     the output array back into a string       4.26 M   10.5%    23 a byte
;     **the window**                            1.97 M    4.8%    11 a byte
;     the input string into an array            1.04 M    2.6%    16 a byte
;     the two fixed tables, once                0.06 M    0.1%
;
; And it is not that the window is little used. **172,699 of the 185,364 bytes
; came out of it** -- 93.2% -- against 12,665 written straight from a literal.
; Nearly every byte this program produces is `out:add(out:at(at))`, and that
; pair of sends costs about eleven instructions, which at 3.4 ns an instruction
; is 38 ns a byte. A boxed integer in an array is not free, and it is not the
; problem.
;
; **What costs is reading the bits.** 59,710 Huffman symbols were decoded, at
; about 483 instructions each; 521,162 bits went through `bits`, at about 55
; instructions a bit. A bit is a block call, a `whileTrue` test, a mask, two
; shifts and two subtractions, and then the caller shifts it into a code and
; compares against a count -- twenty-odd sends to move one bit, and there are
; three of them for every byte of output.
;
; This is the same shape the survey predicted for a different reason and the
; same shape [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels)
; keeps producing: **the expensive thing is the one that happens most often, not
; the one that looks heaviest.** A 32 KB array looks like the cost and a bit
; looks like nothing.
;
; ---------------------------------------------------------------------------
; 2. Inlining the one-bit read, measured and not taken
;
; If the decode loop reads its bit itself rather than calling `bits`, the run is
; **37,176,291 instructions, 8.8% fewer** -- about eight instructions a call,
; which is what a frame and a return cost here. It is four lines and it is not
; in this file.
;
; The reason is the ratio rather than the ugliness: `sha256sum` wrote its
; rotates out for **1.48x** and that paid for the loss of the standard's own
; notation. 1.09x does not, and the version in this file can be read against
; RFC 1951 section 3.2.2 a line at a time. The number is here so that the next
; person to want it does not have to measure it again.
;
; ---------------------------------------------------------------------------
; 3. The oracle knew something no specification does
;
; `gzip -l`'s ratio column is **not** `100 * (uncompressed - compressed) /
; uncompressed`, and this program printed that formula until it was held against
; the tool. It is integer arithmetic with a floor at -99.9%, written out above
; `ratioText`. Eighteen bytes in a twenty-seven byte file is -44.5% and the
; obvious formula says -50.0%.
;
; **RFC 1952 does not contain it, because it is not part of the format.** It is
; a property of the program that prints the listing, and the only way to know it
; is to run that program. That is the argument for an oracle in one line: a
; standard cannot be wrong about the thing it does not specify.
;
; ---------------------------------------------------------------------------
; 4. It is a customer for 6.45, and not for the reason the entry gives
;
; [6.45](../docs/COMPLETED.md#645-a-pipe-cannot-be-taken-in-bounded-pieces--done) names
; this program by name as the third customer that would sharpen it, on the
; grounds that its input has no lines at all -- so `readLine` would not be lossy
; here, it would be meaningless, and *that program would have exactly one route
; in*.
;
; **The route is there and it works.** `system:readFile("/dev/stdin")` reads the
; pipe whole since [6.43](../docs/COMPLETED.md#643-a-program-cannot-read-standard-input-whole-and-the-call-that-looks-as-though-it-can-answers---done)
; closed, `... | solvm gzip.sob -d` is what the sweep runs, and nothing about
; this program is blocked. So the half of the prediction that said it would have
; one way in is right, and the half that implied being short of one is not.
;
; **What makes it a customer is memory, which is `sort`'s reason and not a new
; one.** Measured with `--memory=N`, binary-searched the same way as the steps:
;
;     docs/REFERENCE.md   185,364 bytes out    5,563,386 bytes held    30.0x
;     docs/ideas.md       392,567 bytes out   13,116,403 bytes held    33.4x
;
; (Both documents have grown since, so the *before* column in the section below
; is larger than this one for the same two names. It is the same program and the
; same measurement, over more bytes.)
;
; **Thirty bytes held for every byte produced**, where the format asks for a
; 32 KB window and nothing else however large the stream is. Four copies of the
; data are alive at once: the input as a string, the input as boxed integers,
; the output as boxed integers, and the output as a string. A bounded read would
; retire the first two; a ring buffer and an incremental write would retire the
; other two and are this program's own business rather than the language's.
;
; So the entry gains a second customer for the argument it already had, rather
; than a third reason. That is worth less than it hoped for and is still worth
; recording, because *no new reason* is a finding when an entry predicted one.
;
; ### And then it was converted, so here is what the bounded read was worth
;
; `readUpTo` shipped in 0.43.0 and standard input is now taken in 4,096-byte
; pieces, each one replacing the last. The four copies are two. Smallest
; `--memory=N` that lets the run finish, binary-searched the same way:
;
;                        out        before        after
;     docs/REFERENCE.md  187,655   6,615,294   4,528,936    31.5% less
;     docs/ideas.md      397,342  13,121,439   8,942,620    31.8% less
;
;     held per byte of output      35.3x -> 24.1x  and  33.0x -> 22.5x
;
; **That is the input gone rather than a saving on it**, and the way to show it
; is not that difference: it is to hold the *output* still and vary the input.
; The same 187,655 bytes come out of all seven of these -- each is two members,
; the first k bytes stored and the rest deflated, so the stream gets longer
; while what it says stays the same:
;
;     compressed in     before        after
;         65,881      6,615,294     4,528,936
;         85,587      6,618,344     4,586,890
;        104,642      6,618,344     4,586,890
;        124,099      6,618,344     4,553,338
;        143,963      8,713,853     4,538,086
;        163,321      8,713,853     4,586,890
;        187,693      8,710,802     4,580,790
;
; **The before column climbs by 2.1 MB across that range and the after column
; does not move**: 58 KB of scatter over an input that nearly trebles, with no
; trend in it. A gigabyte through the pipe holds the same 4,096 bytes of it that
; a kilobyte does, and this is the measurement that says so rather than an
; argument from the code. What is left is the two copies of the output, which
; are this program's own business and want a ring buffer and an incremental
; write rather than anything from the language.
;
; ### And the before column is why `--memory=N` has to be read as a ceiling
;
; It does not climb, it **steps**: 6.62 MB for the first four rows and 8.71 MB
; for the last three, one jump of 2,095,509 bytes and nothing in between. Five
; compression levels of the same file -- inputs from 65,894 to 78,610 bytes,
; which is 200 KB of boxed integers between them -- give
; **6,615,294 to the byte, all five**.
;
; So the smallest `--memory` a run survives is where the collector's heap
; threshold next lands, not what the program holds, and the step here is about
; a third of the figure. **A difference smaller than a step is invisible**, which
; is worth knowing about every number in this file and in
; [6.45](../docs/COMPLETED.md#645-a-pipe-cannot-be-taken-in-bounded-pieces--done):
; they are ceilings with a coarse grain, and they are honest for the comparison
; they are used for -- both builds measured the same way on the same input --
; and would not be honest quoted to the byte as *what this program holds*.
;
; **It cost 1,206 instructions.** 41,225,173 to 41,226,379 on `REFERENCE.md`
; through the pipe, which is 0.003%. That is not the cost of the reads: the same
; `bytesOf` runs over the same 65,894 bytes either way, and what is new is
; seventeen loop set-ups where there was one, plus the refill test in `inReady`
; seventeen times. The named-file route moved by 54. The first version of
; `nextByte` called `inReady` on *every byte* rather than only at a boundary and
; cost 725,751 instructions instead, 1.8%, on both routes; the comment above it
; says why the guard is now written twice.
;
; ### The sweep was running every case down one route
;
; `sweep.sh` named its files on the command line, all 66 cases of it, and the
; pipe was checked by nothing at all -- so the reader this section is about
; would have shipped untested by the strongest check this program has. It runs
; both ways now, 131 cases, and the pipe cases were **proved to fail rather than
; assumed to**: a `readUpTo` loop that stops at the first short piece -- the
; defect `oracle.sh` records finding in `sha256sum`'s standard-input path -- is
; reported by 64 of them, and by none of the file cases.
;
; **`oracle.sh` has run every case both ways since `sed`**, and `sweep.sh` is a
; different script, written for a program the shared harness does not fit --
; and the two-route rule did not come with it. That is the shape worth naming:
; not a check that was got wrong, a check that was correct in the file it was
; written in and absent from the one written next to it. A program with two ways
; in gets tested down the one that takes a filename, because that is the one a
; case is easy to write for.
;
; ---------------------------------------------------------------------------
; 5. And the language wanted nothing
;
; **No roadmap entry came out of this program.** That is the outcome
; [ideas.md](../docs/ideas.md#programs-that-would-press-on-something) keeps
; available on purpose -- *it found nothing* is a legitimate answer, and it is
; only worth anything because the prediction was written down first.
; Everything this needed was there: `bitAnd`, `shiftLeft` and
; `shiftRight` for the bit reader, an array that grows for the window, a whole
; read for the pipe, `asByte` and `asCharacter` for the ends, and `writeError`
; and a non-zero exit for a stream that does not check out.
;
; The two places it was awkward are both written down above and neither is a
; gap: a byte costs two sends to read out of a string, which `bytesOf` pays once
; instead of many times, and a loop is left by its condition
; ([3.13](../docs/ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing)),
; which `decode` pays for with a `sym` that is both the answer and the flag.
;
; That is a real result rather than a quiet one. The survey wrote this program
; down as the one that would say whether packed numeric arrays are needed, and
; the answer it produced is **no, and here is why**: the boxing is 5% and the
; interpretation is 70%.
