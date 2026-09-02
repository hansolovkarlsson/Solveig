; re.sol -- regular expressions, POSIX BRE and ERE, with groups.
;
;     @include "re.sol".
;     re:on("\\(ab\\)*c"):find("ababc"):print.       ; #1
;     re:ere("a|ab"):find("ab"):print.               ; #1
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; ---------------------------------------------------------------------------
; The bargain, which is the same one shell.sol strikes
;
; **Build a pattern out of things you wrote, not out of things a file or a user
; gave you.** This is a backtracking engine, and a pattern with a starred group
; inside a starred group takes exponential time on input that nearly matches --
; `^\(a\+\)\+b$` against a run of `a` doubles per character. A pattern chosen by
; a stranger is therefore a way to stop a program, in the same way a shell
; command built from a stranger's input is a way to run one.
;
; That was decided rather than discovered: the alternative was POSIX regex from
; libc through an extension, which is flat on those cases and about seventy
; times faster, and it was refused because *the patterns here are ones this
; repository writes*. See
; [the entry](../docs/ideas.md#scoped-on-2026-09-01-and-the-number-nobody-had-taken)
; for the measurements the decision rests on.
;
; **Two things make the risk bounded rather than theoretical.** `--steps` stops
; a runaway match and says so, because every step this takes is an instruction
; the machine counts -- which is exactly what an engine inside a C primitive
; could not offer. And `re:guarded` turns on a visited set that removes the
; exponential outright, at 20-30%, for a caller that does not control its input
; after all.
;
; ---------------------------------------------------------------------------
; What it has
;
;   .           any one character
;   [abc]       one of those; [a-z] a range; [^abc] anything but; [] and [^]
;               take a literal ] first
;   *           zero or more of what came before
;   ^  $        the start and the end of the text
;   \c          c itself, for any of the above
;
; and, spelled `\(...\)` `\+` `\?` `\|` `\{n,m\}` in **BRE** and `(...)` `+`
; `?` `|` `{n,m}` in **ERE**:
;
;   (...)       a group, numbered from 1 by its opening bracket
;   +  ?        one or more, and zero or one
;   {n} {n,} {n,m}   a counted repetition
;   a|b         either
;   \1 .. \9    what group n matched -- **BRE only**, as POSIX has it
;
; **Leftmost-longest**, which is POSIX and is not what a PEG or a Perl-style
; engine gives: `a|ab` against `ab` answers `ab`, not `a`. It costs nothing
; measurable -- the walk is exhausted either way on any pattern that fails.
;
; ---------------------------------------------------------------------------
; How it works, and why not the obvious way
;
; **A pattern compiles to an instruction list and a loop runs it**, with an
; explicit stack for the choice points. Not recursion:
; [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels) bounds
; the call depth at about 254, and a recursive matcher spends a frame per
; repetition, so `lib/pattern.sol` -- which this replaces -- managed 250 stars
; and no more. Here the *matcher's* depth is an array's length and nothing else
; -- a 2,000-character pattern matches at no depth at all.
;
; **The compiler still walks a tree, and that is where the frames go**: groups
; nested 48 deep compile and 49 do not. It was 220 plain characters until
; `parseCat` was made to build a list rather than a spine of pairs -- caught by
; measuring a claim before writing it down, which is the only reason it is not
; a regression against the file this replaces.
;
; That is the same lesson [check_syntax.sol](../programs/check_syntax.sol)
; learned, and its instruction set was the obvious foundation. **It is the wrong
; one**, measured: LPeg's `Choice` is ordered and its `LoopCommit` makes `*`
; possessive, which is right for a grammar and wrong for a regex. `a|ab` would
; answer `a` and `a*ab` would fail on `aaab`. The instructions carry over; the
; compilation of alternation and repetition does not.

@include "scan.sol".

re := object:new.

; ---------------------------------------------------------------------------
; The tree the parser builds
;
; A node rather than a pair of arrays, because the emitter walks it twice for a
; counted repetition -- `a{2,4}` is `aa` then two optional `a`s -- and a tree is
; what can be walked again.

re:node := object:new.
re:node:kind := 'char.      ; char any set bol eol cat alt star plus opt group ref
re:node:text := "".
re:node:left := nil.
re:node:right := nil.
re:node:negated := false.
re:node:items := nil.       ; for 'cat: the sequence, as a list
re:node:group := #0.        ; which group, for 'group and 'ref
re:node:least := #0.        ; for a counted repetition
re:node:most := nil.        ; nil is "no upper bound"

re:newNode := { kind | | n | n := self:node:new. n:kind := kind. n }.

; ---------------------------------------------------------------------------
; Reading a pattern
;
; **One parser, two dialects, and the difference is only which spellings are
; special.** In BRE a bare `(` is a literal and `\(` opens a group; in ERE it is
; the other way round. `special` answers what the character in hand means, so
; nothing below has to ask which dialect it is in.

re:source := "".
re:extended := false.       ; ERE rather than BRE
re:pos := #1.
re:groups := #0.

re:atEnd := { self:pos:greaterThan(self:source:size) }.
re:peek := { self:atEnd:ifElse({ "" }, { self:source:at(self:pos) }) }.
re:take := { | c | c := self:peek. self:pos := self:pos:inc. c }.

; Is the next thing this operator? In ERE it is the bare character; in BRE it is
; a backslash and then the character. Answers true having consumed it.
re:eat := { op | | n |
    self:extended:ifElse(
        { self:peek:equals(op):ifElse({ self:take. true }, { false }) },
        { (self:peek:equals("\\"):and({
              n := self:pos:inc.
              n:lessOrEqual(self:source:size)
                  :and({ self:source:at(n):equals(op) }) })):ifElse(
              { self:take. self:take. true },
              { false }) }) }.

; The same question without consuming, for the loops that have to look first.
re:sees := { op | | at |
    at := self:pos.
    self:extended:ifElse(
        { self:peek:equals(op) },
        { self:peek:equals("\\"):and({
              at:inc:lessOrEqual(self:source:size)
                  :and({ self:source:at(at:inc):equals(op) }) }) }) }.

; A character class: `[abc]`, `[^abc]`, `[a-z]`, `-` first or last being itself,
; and `]` first being itself. The members are expanded into a string, because
; `indexOf` is then the whole of the membership test and a range in a pattern is
; never large -- the same choice lib/pattern.sol made and the same reason.
re:parseSet := { | n, members, prev, c, closed, first |
    n := self:newNode('set).
    members := "". prev := nil. closed := false. first := true.
    self:peek:equals("^"):ifTrue({ n:negated := true. self:take }).
    { closed:not }:whileTrue({
        self:atEnd:ifTrue({ error:raise("a pattern has an unclosed '['") }).
        c := self:take.
        (c:equals("]"):and({ first:not })):ifElse(
            { closed := true },
            { (c:equals("-"):and({ prev:notNil }):and({
                  self:peek:notEquals("]") }):and({ self:atEnd:not })):ifElse(
                { | lo, hi, i |
                  lo := prev:asByte. hi := self:take:asByte.
                  hi:lessThan(lo):ifTrue({
                      error:raise("a range in [] runs backwards") }).
                  i := lo:inc.
                  { i:lessOrEqual(hi) }:whileTrue({
                      members := members:concat(i:asCharacter). i := i:inc }).
                  prev := nil },
                { members := members:concat(c). prev := c }) }).
        first := false }).
    n:text := members.
    n }.

; A counted repetition, `{n}` `{n,}` `{n,m}`, with the braces already eaten.
re:parseCount := { node | | n, digits, c |
    n := self:newNode('star).      ; kind is fixed up by the caller's emitter
    n:kind := 'count. n:left := node. n:most := nil.
    digits := "".
    { self:peek:notEquals(",") :and({ self:sees("}"):not })
        :and({ self:atEnd:not }) }:whileTrue({ digits := digits:concat(self:take) }).
    digits:equals(""):ifTrue({ error:raise("a repetition count is missing") }).
    n:least := digits:asInteger.
    n:most := n:least.
    self:peek:equals(","):ifTrue({
        self:take.
        digits := "".
        { self:sees("}"):not:and({ self:atEnd:not }) }:whileTrue({
            digits := digits:concat(self:take) }).
        n:most := digits:equals(""):ifElse({ nil }, { digits:asInteger }) }).
    self:eat("}"):ifFalse({ error:raise("a repetition has no closing brace") }).
    n }.

; An atom: a group, a class, `.`, an anchor, a back-reference, or a character.
;
; **`^` and `$` are anchors only where they can be**, which is POSIX's rule for
; BRE and the reason `a$b` matches a dollar sign: `$` is an anchor at the end of
; the pattern and a literal anywhere else. ERE makes them always special, and
; both dialects are followed rather than merged.
re:parseAtom := { | c, n, done |
    n := nil. done := false.

    self:eat("("):ifTrue({ | inner, which |
        which := self:groups:inc. self:groups := which.
        inner := self:parseAlt.
        self:eat(")"):ifFalse({ error:raise("a group has no closing bracket") }).
        n := self:newNode('group). n:left := inner. n:group := which.
        done := true }).

    done:ifFalse({
        c := self:take.

        c:equals("["):ifTrue({ n := self:parseSet. done := true }).
        c:equals("."):ifTrue({ n := self:newNode('any). done := true }).

        (done:not:and({ c:equals("^") })
            :and({ self:extended:or({ self:pos:equals(#2) }) })):ifTrue({
            n := self:newNode('bol). done := true }).

        (done:not:and({ c:equals("$") })
            :and({ self:extended:or({ self:atEnd }) })):ifTrue({
            n := self:newNode('eol). done := true }).

        (done:not:and({ c:equals("\\") })):ifTrue({
            self:atEnd:ifTrue({
                error:raise("a pattern cannot end with a backslash") }).
            c := self:take.
            ; A back-reference is BRE's, and POSIX ERE has none -- which is the
            ; construct that decides an implementation's whole strategy, so it
            ; is not quietly allowed in both.
            "123456789":indexOf(c):notNil:ifTrue({
                self:extended:ifTrue({
                    error:raise(
                        "a back-reference is not in an extended pattern") }).
                n := self:newNode('ref). n:group := c:asInteger.
                done := true }) }).

        done:ifFalse({ n := self:newNode('char). n:text := c }) }).
    n }.

; Repetition binds tighter than concatenation, and stacks: `a**` is `a*`.
re:parseRepeat := { | n, r, more |
    n := self:parseAtom.
    more := true.
    { more }:whileTrue({
        self:peek:equals("*"):ifElse(
            { self:take. r := self:newNode('star). r:left := n. n := r },
            { self:eat("+"):ifElse(
                { r := self:newNode('plus). r:left := n. n := r },
                { self:eat("?"):ifElse(
                    { r := self:newNode('opt). r:left := n. n := r },
                    { self:eat("{"):ifElse(
                        { n := self:parseCount(n) },
                        { more := false }) }) }) }) }).
    n }.

; **A sequence is a list, not a spine of pairs**, and that is not tidiness. The
; emitter walks the tree by recursion, so `abc...` built as `cat(cat(a,b),c)` is
; as deep as the pattern is long -- which cost about 220 characters before it
; ran out of frames ([3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels)).
; lib/pattern.sol compiled a two-thousand-character pattern without trouble
; because it built a flat array, and losing that in the rewrite would have been
; a regression nobody asked for. A list restores it: only real nesting --
; groups inside groups -- costs depth now, and nothing writes thirty of those.
re:parseCat := { | n |
    n := self:newNode('cat).
    n:items := array:new.
    { self:atEnd:not:and({ self:sees("|"):not }):and({
        self:sees(")"):not }) }:whileTrue({
        n:items:add(self:parseRepeat) }).
    n }.

re:parseAlt := { | n, r, a |
    n := self:parseCat.
    { self:eat("|") }:whileTrue({
        r := self:parseCat.
        a := self:newNode('alt). a:left := n. a:right := r. n := a }).
    n }.

; ---------------------------------------------------------------------------
; The instructions
;
;   char c      the next character must be c
;   any         any character, and there must be one
;   set m       one of m, or one not in m when negated
;   bol eol     the start and the end of the text
;   split x y   try x, and keep y to come back to -- greedy prefers x
;   jmp x       go there
;   save k      record the position in slot k
;   ref n       what group n matched, again
;   match       the walk arrived

re:ins := object:new.
re:ins:op := 'match.
re:ins:text := "".
re:ins:x := #0.
re:ins:y := #0.
re:ins:negated := false.

re:code := nil.

re:emit := { op | | i | i := self:ins:new. i:op := op. self:code:add(i).
    self:code:size }.

; **A counted repetition is spelled out** rather than given an instruction of
; its own, which is what every engine does and is the reason `a{1,1000}` is a
; thousand instructions. Nothing here writes one of those.
re:emitNode := { n | | k |
    k := n:kind.
    k:equals('char):ifTrue({ self:code:at(self:emit('char)):text := n:text }).
    k:equals('any):ifTrue({ self:emit('any) }).
    k:equals('bol):ifTrue({ self:emit('bol) }).
    k:equals('eol):ifTrue({ self:emit('eol) }).
    k:equals('set):ifTrue({ | at |
        at := self:emit('set).
        self:code:at(at):text := n:text.
        self:code:at(at):negated := n:negated }).
    k:equals('ref):ifTrue({ self:code:at(self:emit('ref)):x := n:group }).
    k:equals('cat):ifTrue({
        n:items:notNil:ifTrue({ n:items:do({ each | self:emitNode(each) }) }) }).
    k:equals('group):ifTrue({
        self:code:at(self:emit('save)):x := n:group:mul(#2).
        self:emitNode(n:left).
        self:code:at(self:emit('save)):x := n:group:mul(#2):inc }).
    k:equals('alt):ifTrue({ | p, j |
        p := self:emit('split).
        self:code:at(p):x := p:inc.
        self:emitNode(n:left).
        j := self:emit('jmp).
        self:code:at(p):y := j:inc.
        self:emitNode(n:right).
        self:code:at(j):x := self:code:size:inc }).
    k:equals('star):ifTrue({ | p |
        p := self:emit('split).
        self:code:at(p):x := p:inc.
        self:emitNode(n:left).
        self:code:at(self:emit('jmp)):x := p.
        self:code:at(p):y := self:code:size:inc }).
    k:equals('plus):ifTrue({ | s, p |
        s := self:code:size:inc.
        self:emitNode(n:left).
        p := self:emit('split).
        self:code:at(p):x := s.
        self:code:at(p):y := self:code:size:inc }).
    k:equals('opt):ifTrue({ | p |
        p := self:emit('split).
        self:code:at(p):x := p:inc.
        self:emitNode(n:left).
        self:code:at(p):y := self:code:size:inc }).
    k:equals('count):ifTrue({ | i, tail |
        i := #1.
        { i:lessOrEqual(n:least) }:whileTrue({
            self:emitNode(n:left). i := i:inc }).
        n:most:isNil:ifElse(
            { n:least:equals(#0):ifTrue({ | p |
                  ; {0,} is a star
                  p := self:emit('split).
                  self:code:at(p):x := p:inc.
                  self:emitNode(n:left).
                  self:code:at(self:emit('jmp)):x := p.
                  self:code:at(p):y := self:code:size:inc }).
              n:least:greaterThan(#0):ifTrue({ | p, s |
                  ; {n,} is n copies and then a star on the last
                  p := self:emit('split).
                  self:code:at(p):x := p:inc.
                  self:emitNode(n:left).
                  self:code:at(self:emit('jmp)):x := p.
                  self:code:at(p):y := self:code:size:inc }) },
            { | opens |
              opens := array:new.
              i := n:least:inc.
              { i:lessOrEqual(n:most) }:whileTrue({ | p |
                  p := self:emit('split).
                  self:code:at(p):x := p:inc.
                  opens:add(p).
                  self:emitNode(n:left).
                  i := i:inc }).
              opens:do({ p | self:code:at(p):y := self:code:size:inc }) }) }).
    nil }.

; ---------------------------------------------------------------------------
; Compiling
;
; **The leader is carried over from lib/pattern.sol and is worth more than
; anything else here.** If every match must begin with one known character, the
; search skips to where that byte is instead of trying every position: a
; whole-buffer search of a 4,269-line file goes from seconds to 0.008 s. It is
; the difference between an editor's `/` being instant and being noticed.

; The compiled pattern is a `re:new`, the way lib/pattern.sol's is a
; `pattern:new` -- the prototype carries the methods and an instance carries one
; pattern's code. That is not only tidiness: an export boundary belongs to the
; object that draws it, so a compiled pattern has to be *of* the object whose
; methods build it, or `on` could not fill in its own slots from outside.
re:leader := nil.       ; the character every match must start with
re:anchored := false.
re:guarded := false.    ; prune a (pc, position) already tried

; The first instruction that must consume something, if there is one and it is a
; plain character. `save` and `bol` do not consume, so they are stepped over.
re:leaderOf := { code | | i, at, answer, looking |
    at := #1. answer := nil. looking := true.
    { looking:and({ at:lessOrEqual(code:size) }) }:whileTrue({
        i := code:at(at).
        i:op:equals('save):ifElse(
            { at := at:inc },
            { i:op:equals('char):ifTrue({ answer := i:text }).
              looking := false }) }).
    answer }.

re:compile := { source, extended | | p |
    self:source := source. self:extended := extended.
    self:pos := #1. self:groups := #0.
    self:code := array:new.
    self:emitNode(self:parseAlt).
    self:atEnd:ifFalse({
        error:raise("a pattern has an unmatched ')'") }).
    self:emit('match).

    p := self:new.
    p:source := source.
    p:code := self:code.
    p:groups := self:groups.
    p:anchored := self:code:at(#1):op:equals('bol).
    p:leader := self:leaderOf(self:code).
    p }.

; `on` is BRE, which is what sed and vi mean by a regular expression and what
; every caller here wanted first. `ere` is the other dialect, one message rather
; than a flag, so a reader of the call site can see which language the string is
; written in.
re:on := { source | self:compile(source, false) }.
re:ere := { source | self:compile(source, true) }.

; ---------------------------------------------------------------------------
; The machine
;
; **Leftmost-longest is taken by exhaustion.** The walk does not stop at the
; first `match` it reaches; it records how far that one got and carries on
; through the choice points, keeping the furthest. That is what makes `a|ab`
; answer `ab`, and it is free: any pattern that fails is exhausted anyway.
;
; **Groups are undone rather than copied.** A choice point records how deep the
; undo log was, and coming back to it puts the slots it passed over back as they
; were. Copying the slots into every choice point would be an array per
; repetition, which is the difference between this being usable and not.

re:matchAt := { text, start | | stack, undo, saves, best, bestSaves,
                        pc, sp, i, running, n, seen, depth, slots |
    n := text:size.
    slots := self:groups:inc:mul(#2).
    saves := array:new.
    [#1, slots]:loop({ k | saves:add(nil) }).
    undo := array:new.
    stack := array:new.
    seen := self:guarded:ifElse({ dictionary:new }, { nil }).
    best := nil. bestSaves := nil.

    stack:add(#1). stack:add(start). stack:add(#0).

    { stack:size:greaterThan(#0) }:whileTrue({
        depth := stack:removeLast.
        sp := stack:removeLast.
        pc := stack:removeLast.

        { undo:size:greaterThan(depth) }:whileTrue({ | old, slot |
            old := undo:removeLast. slot := undo:removeLast.
            saves:atPut(slot, old) }).

        running := true.
        { running }:whileTrue({
            self:guarded:ifTrue({ | key |
                key := pc:mul(n:add(#2)):add(sp).
                seen:includes(key):ifElse(
                    { running := false }, { seen:atPut(key, true) }) }).

            running:ifTrue({
                i := self:code:at(pc).

                i:op:equals('match):ifTrue({
                    (best:isNil:or({ sp:greaterThan(best) })):ifTrue({
                        best := sp. bestSaves := array:new.
                        saves:do({ v | bestSaves:add(v) }) }).
                    running := false }).

                i:op:equals('char):ifTrue({
                    (sp:lessOrEqual(n):and({
                        text:at(sp):equals(i:text) })):ifElse(
                        { pc := pc:inc. sp := sp:inc },
                        { running := false }) }).

                i:op:equals('any):ifTrue({
                    sp:lessOrEqual(n):ifElse(
                        { pc := pc:inc. sp := sp:inc },
                        { running := false }) }).

                i:op:equals('set):ifTrue({ | inside |
                    sp:greaterThan(n):ifElse(
                        { running := false },
                        { inside := i:text:size:greaterThan(#0)
                              :and({ i:text:indexOf(text:at(sp)):notNil }).
                          i:negated:ifTrue({ inside := inside:not }).
                          inside:ifElse(
                              { pc := pc:inc. sp := sp:inc },
                              { running := false }) }) }).

                i:op:equals('bol):ifTrue({
                    sp:equals(#1):ifElse({ pc := pc:inc },
                                         { running := false }) }).

                i:op:equals('eol):ifTrue({
                    sp:equals(n:inc):ifElse({ pc := pc:inc },
                                            { running := false }) }).

                i:op:equals('save):ifTrue({
                    undo:add(i:x:inc). undo:add(saves:at(i:x:inc)).
                    saves:atPut(i:x:inc, sp).
                    pc := pc:inc }).

                i:op:equals('ref):ifTrue({ | from, to, len, ok, k |
                    from := saves:at(i:x:mul(#2):inc).
                    to := saves:at(i:x:mul(#2):add(#2)).
                    (from:isNil:or({ to:isNil })):ifElse(
                        { running := false },
                        { len := to:sub(from).
                          ok := sp:add(len):lessOrEqual(n:inc).
                          k := #0.
                          { ok:and({ k:lessThan(len) }) }:whileTrue({
                              text:at(sp:add(k)):equals(text:at(from:add(k)))
                                  :ifFalse({ ok := false }).
                              k := k:inc }).
                          ok:ifElse({ pc := pc:inc. sp := sp:add(len) },
                                    { running := false }) }) }).

                i:op:equals('split):ifTrue({
                    stack:add(i:y). stack:add(sp). stack:add(undo:size).
                    pc := i:x }).

                i:op:equals('jmp):ifTrue({ pc := i:x }) }) }) }).

    best:isNil:ifElse({ nil }, { [best, bestSaves] }) }.

; ---------------------------------------------------------------------------
; The surface, which is lib/pattern.sol's so that the callers only change a name
;
; `find` answers where a match begins and `endOfMatchAt` where one ending. The
; pair is what a substitution needs and what an editor's `n` needs, and keeping
; both is why neither has to answer a range nobody asked for.

re:lastEnd := nil.      ; where the last successful find ended
re:lastSaves := nil.    ; and what its groups took

re:findFrom := { text, at | | from, hit, limit |
    from := at. hit := nil. limit := text:size:inc.
    self:lastEnd := nil. self:lastSaves := nil.
    { hit:isNil:and({ from:lessOrEqual(limit) }) }:whileTrue({ | got |
        ; The leader: skip to somewhere a match could begin at all.
        self:leader:notNil:ifTrue({ | where |
            where := text:indexOf(self:leader, from).
            where:isNil:ifElse({ from := limit:inc }, { from := where }) }).
        from:lessOrEqual(limit):ifTrue({
            got := self:matchAt(text, from).
            got:isNil:ifElse(
                { from := from:inc.
                  self:anchored:ifTrue({ from := limit:inc }) },
                { hit := from.
                  self:lastEnd := got:at(#1).
                  self:lastSaves := got:at(#2) }) }) }).
    hit }.

re:find := { text | self:findFrom(text, #1) }.
re:matches := { text | self:find(text):notNil }.

re:findLast := { text, at | | from, found, hit |
    found := nil. from := #1.
    { from := self:findFrom(text, from). from:notNil:and({
        from:lessThan(at) }) }:whileTrue({ found := from. from := from:inc }).
    found }.

; **One past the last character matched**, which is what lib/pattern.sol answers
; and what `copyFrom(start, stop:sub(#1))` in every caller expects. A zero-width
; match answers where it began.
re:endOfMatchAt := { text, at | | got |
    got := self:matchAt(text, at).
    got:isNil:ifElse({ nil }, {
        self:lastSaves := got:at(#2).
        got:at(#1) }) }.

; What group n took in the last successful match, or nil. Numbered from 1; group
; 0 is not offered, because `&` in a replacement already says the whole match
; and two spellings of one thing is how a surface grows.
re:group := { n | | from, to |
    self:lastSaves:isNil:ifElse({ nil }, {
        from := self:lastSaves:at(n:mul(#2):inc).
        to := self:lastSaves:at(n:mul(#2):add(#2)).
        (from:isNil:or({ to:isNil })):ifElse({ nil }, { [from, to:sub(#1)] }) }) }.

; **A replacement takes `&` for the whole match and `\1`..`\9` for a group**,
; which is sed's spelling and vi's. `\&` is an ampersand and `\\` a backslash.
; A group that did not take part answers the empty string rather than raising:
; `\(a\)\|\(b\)` leaves one of the two unset by construction, and a substitution
; that refused it could not be written at all.
re:replacementFor := { replacement, text, start, stop | | out, s, c |
    out := "".
    s := scan:on(replacement).
    { s:atEnd:not }:whileTrue({
        c := s:next.
        c:equals("\\"):ifElse(
            { s:atEnd:ifTrue({
                  error:raise("a replacement cannot end with a backslash") }).
              c := s:next.
              "123456789":indexOf(c):notNil:ifElse(
                  { | g |
                    g := self:group(c:asInteger).
                    g:notNil:ifTrue({
                        out := out:concat(
                            text:copyFrom(g:at(#1), g:at(#2))) }) },
                  { out := out:concat(c) }) },
            { c:equals("&"):ifElse(
                { out := out:concat(text:copyFrom(start, stop:sub(#1))) },
                { out := out:concat(c) }) }) }).
    out }.

; Answers the text and how many times it changed, in a dictionary, the way
; `capture` answers `"output"` and `"status"` -- one walk rather than two, for
; the caller that reports *17 substitutions on 9 lines*.
;
; **The empty-match rule is the one that has to be got exactly right**, and it
; is lib/pattern.sol's, unchanged: a zero-width match where the last one ended
; is not a match, or `s/x*/-/g` would loop for ever on the same position.
re:substitutionIn := { text, replacement, all | | out, at, start, stop,
                               done, count, ended |
    out := "". at := #1. done := false. count := #0. ended := #0.
    { done:not }:whileTrue({
        start := self:findFrom(text, at).
        start:isNil:ifElse(
            { done := true },
            { stop := self:lastEnd.
              (stop:equals(start):and({ start:equals(ended) })):ifElse(
                  { start:lessOrEqual(text:size):ifElse(
                        { out := out:concat(text:at(start)) },
                        { done := true }).
                    at := start:add(#1) },
                  { count := count:add(#1).
                    out := out:concat(text:copyFrom(at, start:sub(#1)))
                              :concat(self:replacementFor(
                                  replacement, text, start, stop)).
                    ended := stop.
                    stop:equals(start):ifTrue({
                        start:lessOrEqual(text:size):ifTrue({
                            out := out:concat(text:at(start)) }).
                        stop := start:add(#1) }).
                    at := stop.
                    all:ifFalse({ done := true }) }) }) }).

    out := out:concat(at:greaterThan(text:size):ifElse(
        { "" }, { text:copyFrom(at, text:size) })).

    dictionary:of("text", out, "count", count) }.

re:replaceIn := { text, replacement |
    self:substitutionIn(text, replacement, false):at("text") }.

re:replaceAllIn := { text, replacement |
    self:substitutionIn(text, replacement, true):at("text") }.

re:countIn := { text | | n, at, start, stop, done, ended |
    n := #0. at := #1. done := false. ended := #0.
    { done:not }:whileTrue({
        start := self:findFrom(text, at).
        start:isNil:ifElse(
            { done := true },
            { stop := self:lastEnd.
              (stop:equals(start):and({ start:equals(ended) })):ifElse(
                  { at := start:add(#1) },
                  { n := n:add(#1).
                    ended := stop.
                    at := stop:equals(start):ifElse({ start:add(#1) },
                                                    { stop }) }) }) }).
    n }.

; ---------------------------------------------------------------------------
; The export boundary
;
; The twelve messages the reference documents, and nothing else. What is left
; out is one matcher taken apart -- `code`, `leader`, `anchored`, `matchAt`,
; `lastEnd` and the rest are the pieces a match is made of. Inherited, so a
; compiled pattern is these messages and no more.
re:exports(['on, 'ere, 'find, 'findFrom, 'findLast, 'matches, 'endOfMatchAt,
            'replaceIn, 'replaceAllIn, 'countIn, 'substitutionIn,
            'group, 'guarded, 'source]).
