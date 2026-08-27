; check_syntax.sol -- read a grammar, then read a file and say where it stops
; agreeing with it.
;
; Run with:  ./bin/solas programs/check_syntax.sol && ./bin/solvm programs/check_syntax.sob
; On a file:  ./bin/solvm programs/check_syntax.sob grammar.bnf source.pas
; The token stream instead:  ./bin/solvm programs/check_syntax.sob grammar.bnf source.pas tokens
; The grammar alone:  ./bin/solvm programs/check_syntax.sob grammar.bnf
;
; The fourteenth program here, and the second whose input is a *language* rather
; than a document -- but where [sola.sol](sola.sol) knows SolaBasic because its
; author wrote SolaBasic into it, this one knows nothing until it is told. Hand
; it Wirth's Pascal and it checks Pascal. Hand it something else and it checks
; that. **The grammar is the program**; this file is only the machine that runs
; one.
;
;     ./bin/solvm programs/check_syntax.sob programs/check_syntax/pascal.bnf myprog.pas
;
; ---------------------------------------------------------------------------
; What it reads, and why it reads two dialects rather than one
;
; The notation is Wirth's -- the one the Pascal report is written in, and the
; one he proposed in *What can we do about the unnecessary diversity of notation
; for syntactic definitions* (1977):
;
;     production = identifier "=" expression "." .
;     expression = term { "|" term } .
;     term       = factor { factor } .
;     factor     = identifier | literal | "(" expression ")"
;                | "[" expression "]" | "{" expression "}" .
;
; That grammar is above in its own notation, which is the property that makes it
; worth using: it describes itself, so there is nothing to learn twice.
;
; **It also accepts the older shape**, because "a file written in BNF" means
; that one at least as often:
;
;     <expression> ::= <term> | <expression> "+" <term>
;
; Angle brackets around a name, `::=` for the definition, no terminator, one
; production per line. Both dialects are read by the same reader: `<name>` is a
; name, `=` and `:=` and `::=` are all the definition symbol, and the `.` at the
; end of a production is **optional** -- a term ends when the next two tokens
; are a name and a definition symbol, which is what "one production per line"
; means when you stop assuming lines matter.
;
; Accepting both was not generosity. It is what makes the left-recursion check
; below earn its place: nobody writes left recursion in Wirth's notation, since
; `{ }` is right there, and everybody writes it in the older one.
;
; ---------------------------------------------------------------------------
; The two halves of a grammar, and why the file has to say where the line is
;
; A grammar for Pascal is written over **tokens** -- `identifier`, `";"`,
; `"begin"` -- and says nothing about how the characters of a file become those
; tokens. Wirth's report gives the lexical rules too, in the same notation, and
; that is the arrangement here: one file, one notation, two halves, with a
; directive naming the seam.
;
;     letter     = "a" .. "z" .            (* lexical: matched over characters *)
;     identifier = letter { letter | digit } .
;
;     %syntax                              (* everything after this is over tokens *)
;
;     program    = "program" identifier ";" block "." .
;
; The seam has to be declared rather than guessed. A rule is not lexical because
; of anything about its shape -- `identifier` and `expression` look alike -- and
; a checker that guesses wrong reports a file as broken when the file is fine,
; which is the worst thing this program could do. So there is a directive, and
; a grammar without one is refused with a message saying so.
;
; The directives, all of them:
;
;     %tokens             what follows is lexical -- the default, so it is optional
;     %syntax             what follows is matched over tokens
;     %fragment name ...  these lexical rules are helpers and are never a token
;     %skip name ...      these token kinds are produced and then thrown away
;     %start name         the goal rule; the first syntactic rule if unsaid
;     %ignorecase         letters compare without regard to case
;
; **`%fragment` is the one of those that had to be learned.** `letter` and
; `digit` are lexical rules, and they are not tokens -- they are what the token
; rules are written out of. Nothing about their shape says so, and the first
; Pascal file this program ever read came back as a stream of `letter` and
; `digit`, because longest match ties are broken by declaration order and
; `letter` is declared before `identifier`. Both match `T`, and `letter` was
; first. There is a warning for it now, below, and a directive to say what was
; meant.
;
; ---------------------------------------------------------------------------
; Three extensions to the notation, and the case for each
;
; Wirth's notation cannot describe a lexer. It has no way to write a range, no
; way to write "any character but this one", and no way to write a tab. Every
; one of those is needed before a single Pascal file can be read, so there are
; three additions and no others:
;
;   `"a" .. "z"`  a range of one character. The alternative is writing
;                 twenty-six alternatives, which the Pascal report does and
;                 which nobody would type twice.
;
;   `! factor`    one character, provided this does not match here. Pascal's
;                 comment is `"{" { ! "}" } "}"` and there is no way to say that
;                 otherwise. It is PEG's negative lookahead with a character
;                 consumed after it, which is the only form anybody uses.
;
;   `"\n" "\t"`   the escapes Solum's own strings take, inside a literal, so
;                 that whitespace can be written down at all.
;
; All three are **lexical only** and refused in a syntactic rule, where they
; would be asking a question about characters in a place that has only tokens.
; That refusal is a grammar error with a line number, not a silent failure.
;
; ---------------------------------------------------------------------------
; What the matcher is, said plainly, because it is the thing that can be wrong
;
; **Ordered choice with local backtracking** -- a PEG, not a general BNF parser.
; `a | b` tries `a`, and tries `b` only if `a` failed. If `a` succeeds and the
; rule containing the choice fails later on, the choice is *not* revisited.
;
; That is a real restriction and it is stated here rather than buried, because
; the failure it produces is a syntax error on a file that is correct. It costs
; nothing on an LL(1) grammar, which is what Wirth's Pascal is and what almost
; every published grammar is. It costs something on a grammar with an
; alternative that is a proper prefix of a later one -- `"<" | "<="` is the
; classic -- and for that the checker below reports the ordering as a grammar
; warning rather than letting it mis-parse quietly.
;
; The lexical half does **not** work that way, and does not need to: it takes
; the longest match over all token rules, which is what every lexer does and
; what makes `"<" | "<="` a non-question there.
;
; The rest of what it found is at the bottom, under "what it cost in frames"
; and "what the grammar had to say about itself".

@include "scan.sol".
@include "control.sol".

; ---------------------------------------------------------------------------
; Characters
;
; ASCII only, deliberately: a grammar that wants a byte outside it writes the
; byte, and `letter` is the grammar's business rather than this program's. The
; one place this file decides what a letter is, is in the names of rules.

isDigit := { c | c:greaterOrEqual("0"):and({ c:lessOrEqual("9") }) }.

; `asUppercase` leaves everything that is not a letter alone, so this is one
; comparison rather than two -- and `_`, `[` and `^` all sit above `Z`, which is
; the part that has to be true for it to work.
isLetter := { c | | u | u := c:asUppercase.
    u:greaterOrEqual("A"):and({ u:lessOrEqual("Z") }) }.

isSpace := { c | c:equals(" "):or({ c:equals("\t") })
    :or({ c:equals("\n") }):or({ c:equals("\r") }) }.

isNameStart := { c | isLetter:value(c):or({ c:equals("_") }) }.
isNameChar := { c | isNameStart:value(c):or({ isDigit:value(c) })
    :or({ c:equals("-") }) }.

; Whether a literal in a syntactic rule is shaped like a word -- which is how
; the reserved words are found, below, without anybody declaring them.
isWordShaped := { text | | ok, i |
    ok := text:size:greaterThan(#0).
    ok:ifTrue({ ok := isNameStart:value(text:at(#1)) }).
    i := #2.
    { ok:and({ i:lessOrEqual(text:size) }) }:whileTrue({
        isNameChar:value(text:at(i)):ifFalse({ ok := false }).
        i := i:add(#1) }).
    ok }.

; ---------------------------------------------------------------------------
; Where a position is
;
; Everything below carries a byte offset and nothing carries a line, because
; the offset is what the scanning already has and the line is wanted perhaps
; four times in a run -- once per message. Counting newlines when asked is
; O(n) each time and free at that rate; carrying a line through every token and
; every node is O(1) each time and a field on everything.

lineColumnIn := { src, pos | | line, start, i, limit |
    line := #1. start := #1. i := #1.
    limit := pos:greaterThan(src:size):ifElse({ src:size }, { pos:sub(#1) }).
    { i:lessOrEqual(limit) }:whileTrue({
        src:at(i):equals("\n"):ifTrue({ line := line:add(#1). start := i:add(#1) }).
        i := i:add(#1) }).
    [line, pos:sub(start):add(#1)] }.

; The text of the line a position falls on, for the caret under an error.
lineTextIn := { src, pos | | start, stop |
    start := pos:greaterThan(src:size):ifElse({ src:size }, { pos }).
    start:lessThan(#1):ifTrue({ start := #1 }).
    { start:greaterThan(#1):and({ src:at(start:sub(#1)):equals("\n"):not }) }
        :whileTrue({ start := start:sub(#1) }).
    stop := start.
    { stop:lessOrEqual(src:size):and({ src:at(stop):equals("\n"):not }) }
        :whileTrue({ stop := stop:add(#1) }).
    stop:greaterThan(start):ifElse({ src:copyFrom(start, stop:sub(#1)) }, { "" }) }.

; ---------------------------------------------------------------------------
; The tree a grammar becomes
;
; One object with a kind, which is the shape the matcher wants: **one method
; per node costs one frame, and a staircase of `ifElse` inside it costs none.**
; That is not a style preference, it is the whole depth budget -- see
; [control.sol](../lib/control.sol), which measures `ifElseIf` at three frames a
; level and says in as many words not to put it inside a recursion. It is used
; once in this file, in the grammar's own lexer, where the frames are transient
; and the legibility is free.
;
;   'lit    text            a terminal: characters, or a token's spelling
;   'range  text upTo       one character between two, lexical only
;   'not    kids:at(#1)     one character, if that does not match, lexical only
;   'ref    text            another rule, by name
;   'seq    kids            all of them, in order; none of them is empty
;   'alt    kids            the first that matches
;   'opt    kids:at(#1)     that, or nothing
;   'rep    kids:at(#1)     that, as many times as it will go

node := object:new.
node:kind := 'lit.
node:text := "".
node:upTo := "".
node:kids := nil.
node:pos := #0.

makeNode := { kind, pos | | n |
    n := node:new. n:kind := kind. n:pos := pos. n:kids := array:new. n }.

; ---------------------------------------------------------------------------
; A rule, and a grammar
;
; `lexical` is decided by which side of `%syntax` the rule was written on and is
; never inferred from the rule itself -- the reason is in the header.

rule := object:new.
rule:name := "".
rule:body := nil.
rule:lexical := false.
rule:pos := #0.
rule:nullable := false.
rule:used := false.
rule:fragment := false.

gRules := dictionary:new.        ; name -> rule
gOrder := array:new.             ; every name, in the order the file gives them
gTokenOrder := array:new.        ; the lexical ones, which is the order they are tried in
gSkip := array:new.
gFragment := array:new.
gStart := nil.
gIgnoreCase := false.
gSection := 'lexical.
gPath := "".
gText := "".
gErrors := array:new.            ; grammar errors, as text
gWarnings := array:new.

; Every comparison of two pieces of text in this program goes through here, so
; that `%ignorecase` is one decision made once rather than a flag consulted in
; nine places, one of which would be missed.
sameText := { a, b |
    gIgnoreCase:ifElse({ a:asLowercase:equals(b:asLowercase) }, { a:equals(b) }) }.

grammarError := { pos, text | | lc |
    lc := lineColumnIn:value(gText, pos).
    gErrors:add("{}:{}: grammar error: {}":fill([gPath, lc:at(#1), text])) }.

grammarWarning := { pos, text | | lc |
    lc := lineColumnIn:value(gText, pos).
    gWarnings:add("{}:{}: grammar warning: {}":fill([gPath, lc:at(#1), text])) }.

; ---------------------------------------------------------------------------
; Reading the grammar file: characters to meta-tokens
;
; This is the flat, cool, many-armed dispatch `ifElseIf` was built for -- run
; once per token of a file that is a few kilobytes, with nothing recursive about
; it. The matcher below is the other case and uses the staircase.

mtok := object:new. mtok:kind := 'name. mtok:text := "". mtok:pos := #0.
makeMtok := { kind, text, pos | | t |
    t := mtok:new. t:kind := kind. t:text := text. t:pos := pos. t }.

escapeFor := { c |
    c:isNil:ifElse({ "" }, {
    c:equals("n"):ifElse({ "\n" }, {
    c:equals("t"):ifElse({ "\t" }, {
    c:equals("r"):ifElse({ "\r" }, {
    c:equals("0"):ifElse({ "" }, { c }) }) }) }) }) }.

; A quoted terminal. Both quotes work and neither is special inside the other,
; which is what lets a grammar write `"'"` and `'"'` without an escape.
readLiteral := { s | | q, out, c, done |
    q := s:next.
    out := "". done := false.
    { done:not }:whileTrue({
        s:atEnd:ifElse({
            error:raise("a literal is not closed before the end of the file") }, {
            c := s:next.
            c:equals(q):ifElse({ done := true }, {
                c:equals("\\"):ifElse(
                    { out := out:concat(escapeFor:value(s:next)) },
                    { out := out:concat(c) }) }) }) }).
    out }.

; `<name>` for the older dialect. The brackets are not part of the name, so
; `<expression>` and `expression` are the same rule and a file may mix them.
readAngleName := { s | | out, c, done |
    s:step.
    out := "". done := false.
    { done:not }:whileTrue({
        s:atEnd:ifElse({ error:raise("a <name> is not closed") }, {
            c := s:next.
            c:equals(">"):ifElse({ done := true }, { out := out:concat(c) }) }) }).
    out:trim }.

metaLex := { src | | s, out, c, start |
    s := scan:on(src).
    out := array:new.
    { s:atEnd:not }:whileTrue({
        c := s:peek.
        start := s:pos.
        [
            { isSpace:value(c) },
                { s:step },
            { s:looksLike("(*") },
                { s:take(#2).
                  { s:atEnd:not:and({ s:looksLike("*)"):not }) }:whileTrue({ s:step }).
                  s:atEnd:ifElse({ error:raise("a (* comment *) is not closed") },
                                 { s:take(#2) }) },
            { isNameStart:value(c) },
                { out:add(makeMtok:value('name,
                      s:takeWhile({ ch | isNameChar:value(ch) }), start)) },
            { c:equals("<") },
                { out:add(makeMtok:value('name, readAngleName:value(s), start)) },
            { c:equals("\""):or({ c:equals("'") }) },
                { out:add(makeMtok:value('lit, readLiteral:value(s), start)) },
            { c:equals("%") },
                { s:step.
                  out:add(makeMtok:value('directive,
                      s:takeWhile({ ch | isNameChar:value(ch) }):asLowercase, start)) },
            { s:looksLike("::=") },
                { s:take(#3). out:add(makeMtok:value('eq, "::=", start)) },
            { s:looksLike(":=") },
                { s:take(#2). out:add(makeMtok:value('eq, ":=", start)) },
            { s:looksLike("..") },
                { s:take(#2). out:add(makeMtok:value('dotdot, "..", start)) },
            { c:equals("=") },
                { s:step. out:add(makeMtok:value('eq, "=", start)) },
            { c:equals("."):or({ c:equals(";") }) },
                { s:step. out:add(makeMtok:value('end, c, start)) },
            { c:equals("|") },
                { s:step. out:add(makeMtok:value('bar, "|", start)) },
            { c:equals("!") },
                { s:step. out:add(makeMtok:value('bang, "!", start)) },
            { "([{":indexOf(c):notNil },
                { s:step. out:add(makeMtok:value('open, c, start)) },
            { ")]}":indexOf(c):notNil },
                { s:step. out:add(makeMtok:value('close, c, start)) },
            { error:raise("'{}' has no meaning in a grammar":fill([c])) }
        ]:ifElseIf }).
    out }.

; ---------------------------------------------------------------------------
; Meta-tokens to productions
;
; A recursive descent over the meta-tokens, in the same shape `evaluator.sol`
; has and for the same reason. It is shallow -- the deepest a grammar file
; nests its own brackets is three or four -- so nothing here is spent on frames.

mtoks := array:new.
mpos := #1.

mpeek := { mpos:lessOrEqual(mtoks:size):ifElse({ mtoks:at(mpos) }, { nil }) }.
mpeekAt := { n | | i | i := mpos:add(n).
    i:lessOrEqual(mtoks:size):ifElse({ mtoks:at(i) }, { nil }) }.
mnext := { | t | t := mpeek:value. t:notNil:ifTrue({ mpos := mpos:add(#1) }). t }.
mkind := { | t | t := mpeek:value. t:isNil:ifElse({ nil }, { t:kind }) }.
mhere := { | t | t := mpeek:value.
    t:isNil:ifElse({ gText:size:add(#1) }, { t:pos }) }.

; **The one piece of lookahead in the reader, and the reason `.` is optional.**
; A production ends where the next one starts, and the next one starts at a name
; followed by a definition symbol. Wirth's `.` says the same thing explicitly
; and is consumed when it is there; the older dialect never writes one, and this
; is what stands in for it.
atProductionStart := { | t, n |
    t := mpeek:value. n := mpeekAt:value(#1).
    t:isNil:ifElse({ false }, {
        t:kind:equals('name):and({ n:notNil:and({ n:kind:equals('eq) }) }) }) }.

atTermEnd := { | k |
    k := mkind:value.
    k:isNil:or({ k:equals('bar) }):or({ k:equals('close) })
        :or({ k:equals('end) }):or({ k:equals('directive) })
        :or({ atProductionStart:value }) }.

parseFactor := { | t, n, inner, closer |
    t := mnext:value.
    t:kind:equals('name):ifElse({
        n := makeNode:value('ref, t:pos). n:text := t:text. n },
    { t:kind:equals('lit):ifElse({
        mkind:value:equals('dotdot):ifElse({
            mnext:value.
            mkind:value:equals('lit):ifFalse({
                error:raise("'..' wants a literal after it") }).
            n := makeNode:value('range, t:pos).
            n:text := t:text. n:upTo := mnext:value:text.
            n:text:size:equals(#1):and({ n:upTo:size:equals(#1) }):ifFalse({
                error:raise("a range runs between single characters") }).
            n },
        { n := makeNode:value('lit, t:pos). n:text := t:text. n }) },
    { t:kind:equals('bang):ifElse({
        n := makeNode:value('not, t:pos). n:kids:add(parseFactor:value). n },
    { t:kind:equals('open):ifElse({
        inner := parseExpression:value.
        closer := ")]}":at("([{":indexOf(t:text)).
        mkind:value:equals('close):and({ mpeek:value:text:equals(closer) }):ifFalse({
            error:raise("'{}' is not closed by '{}'":fill([t:text, closer])) }).
        mnext:value.
        t:text:equals("("):ifElse({ inner }, {
            n := makeNode:value(t:text:equals("["):ifElse({ 'opt }, { 'rep }), t:pos).
            n:kids:add(inner). n }) },
    { error:raise("'{}' cannot start a factor":fill([t:text])) }) }) }) }) }.

; A sequence of factors. An empty one is a node that matches nothing and
; consumes nothing, which is what `a | | b` and a trailing `|` mean.
parseTerm := { | n |
    n := makeNode:value('seq, mhere:value).
    { atTermEnd:value:not }:whileTrue({ n:kids:add(parseFactor:value) }).
    n:kids:size:equals(#1):ifElse({ n:kids:at(#1) }, { n }) }.

parseExpression := { | n, first |
    first := parseTerm:value.
    mkind:value:equals('bar):ifElse({
        n := makeNode:value('alt, first:pos).
        n:kids:add(first).
        { mkind:value:equals('bar) }:whileTrue({
            mnext:value.
            n:kids:add(parseTerm:value) }).
        n },
        { first }) }.

; ---------------------------------------------------------------------------
; The file as a whole: directives, productions, and getting back on its feet
;
; A grammar with two mistakes in it should report two mistakes. Recovery is to
; skip to the next production start -- the same lookahead that ends a term --
; which is the one place in a grammar file where the reader always knows where
; it is.

skipToNextProduction := { | done |
    done := false.
    { done:not }:whileTrue({
        mpeek:value:isNil:or({ atProductionStart:value })
            :or({ mkind:value:equals('directive) })
            :ifElse({ done := true }, { mnext:value }) }) }.

readDirective := { | t, name, arg |
    t := mnext:value.
    name := t:text.
    [
        { name:equals("tokens") },  { gSection := 'lexical },
        { name:equals("syntax") },  { gSection := 'syntax },
        { name:equals("ignorecase") }, { gIgnoreCase := true },
        { name:equals("start") },
            { mkind:value:equals('name):ifElse({ gStart := mnext:value:text },
                { grammarError:value(t:pos, "%start wants the name of a rule") }) },
        { name:equals("fragment") },
            { mkind:value:equals('name):and({ atProductionStart:value:not })
                :ifElse({
                    { mkind:value:equals('name):and({ atProductionStart:value:not }) }
                        :whileTrue({ gFragment:add(mnext:value:text) }) },
                { grammarError:value(t:pos, "%fragment wants the name of a token rule") }) },
        { name:equals("skip") },
            { mkind:value:equals('name):and({ atProductionStart:value:not })
                :ifElse({
                    { mkind:value:equals('name):and({ atProductionStart:value:not }) }
                        :whileTrue({ gSkip:add(mnext:value:text) }) },
                { grammarError:value(t:pos, "%skip wants the name of a token rule") }) },
        { grammarError:value(t:pos,
            "'%{}' is not a directive -- there are %tokens, %syntax, %fragment, %skip, %start and %ignorecase":fill([name])) }
    ]:ifElseIf.
    nil }.

readProduction := { | t, r |
    t := mnext:value.
    mnext:value.
    gRules:includes(t:text):ifTrue({
        grammarError:value(t:pos, "<{}> is defined twice":fill([t:text])) }).
    r := rule:new.
    r:name := t:text.
    r:pos := t:pos.
    r:lexical := gSection:equals('lexical).
    r:body := parseExpression:value.
    mkind:value:equals('end):ifTrue({ mnext:value }).
    gRules:includes(r:name):ifFalse({
        gRules:atPut(r:name, r).
        gOrder:add(r:name) }).
    nil }.

readGrammar := { path, text |
    gPath := path. gText := text.
    gRules := dictionary:new. gOrder := array:new. gTokenOrder := array:new.
    gSkip := array:new. gFragment := array:new.
    gStart := nil. gIgnoreCase := false.
    gErrors := array:new. gWarnings := array:new.
    gSection := 'lexical.
    { mtoks := metaLex:value(text) }:onError({ e |
        mtoks := array:new.
        gErrors:add("{}: grammar error: {}":fill([path, e:message])) }).
    mpos := #1.
    { mpeek:value:notNil }:whileTrue({
        { mkind:value:equals('directive):ifElse({ readDirective:value }, {
            atProductionStart:value:ifElse({ readProduction:value }, {
                grammarError:value(mhere:value,
                    "expected a rule name and '=' here").
                skipToNextProduction:value }) }) }
        :onError({ e |
            grammarError:value(mhere:value, e:message).
            skipToNextProduction:value }) }).
    nil }.

; ---------------------------------------------------------------------------
; Checking the grammar before it is used on anything
;
; **The reason this section is as long as it is: every fault it catches would
; otherwise be reported as a fault in the subject file.** A checker that says
; `myprog.pas:12: syntax error` when the mistake is on line 40 of the grammar
; has done worse than nothing, because the file it accused is the one the reader
; will go and look at.
;
; Left recursion is the sharpest of them. `expr = expr "+" term` is how the
; older dialect writes iteration and it is what a PEG cannot do: matching `expr`
; begins by matching `expr`, and the only thing that stops it is the frame limit
; -- which arrives as `call depth exceeded` and looks like a bug in this
; program. So it is found first, by reading the grammar, and reported as what it
; is.

kidsOf := { n | n:kids:isNil:ifElse({ array:new }, { n:kids }) }.

; Whether a node can match nothing at all. A fixpoint over the rules, because
; `a = [b] .` and `b = [a] .` are each nullable only because the other is.
nodeNullable := { n | | k, all, any, i, kids |
    k := n:kind.
    kids := kidsOf:value(n).
    k:equals('lit):ifElse({ n:text:size:equals(#0) }, {
    k:equals('range):ifElse({ false }, {
    k:equals('not):ifElse({ false }, {
    k:equals('opt):ifElse({ true }, {
    k:equals('rep):ifElse({ true }, {
    k:equals('ref):ifElse({
        gRules:includes(n:text):ifElse({ gRules:at(n:text):nullable }, { true }) }, {
    k:equals('alt):ifElse({
        any := false. i := #1.
        { i:lessOrEqual(kids:size) }:whileTrue({
            nodeNullable:value(kids:at(i)):ifTrue({ any := true }).
            i := i:add(#1) }).
        any },
      { all := true. i := #1.
        { i:lessOrEqual(kids:size) }:whileTrue({
            nodeNullable:value(kids:at(i)):ifFalse({ all := false }).
            i := i:add(#1) }).
        all }) }) }) }) }) }) }) }.

computeNullable := { | changed, r |
    gOrder:do({ name | gRules:at(name):nullable := false }).
    changed := true.
    { changed }:whileTrue({
        changed := false.
        gOrder:do({ name | | was |
            r := gRules:at(name).
            was := r:nullable.
            r:nullable := nodeNullable:value(r:body).
            r:nullable:equals(was):ifFalse({ changed := true }) }) }).
    nil }.

; Every rule this node can begin by entering, without consuming anything first.
; A sequence contributes its second factor too when its first can match nothing,
; which is the case that makes `a = [x] a .` left-recursive.
leftRefsOf := { n, out | | k, kids, i, going |
    k := n:kind.
    kids := kidsOf:value(n).
    k:equals('ref):ifTrue({ out:indexOf(n:text):isNil:ifTrue({ out:add(n:text) }) }).
    k:equals('alt):ifTrue({
        i := #1.
        { i:lessOrEqual(kids:size) }:whileTrue({
            leftRefsOf:value(kids:at(i), out). i := i:add(#1) }) }).
    k:equals('opt):or({ k:equals('rep) }):ifTrue({
        leftRefsOf:value(kids:at(#1), out) }).
    k:equals('seq):ifTrue({
        i := #1. going := true.
        { going:and({ i:lessOrEqual(kids:size) }) }:whileTrue({
            leftRefsOf:value(kids:at(i), out).
            nodeNullable:value(kids:at(i)):ifFalse({ going := false }).
            i := i:add(#1) }) }).
    out }.

; The transitive closure of that, which is where a cycle shows up. Written as a
; worklist rather than a recursion so that a grammar with a cycle in it cannot
; exhaust the frames while this is trying to find out that it has one.
leftClosureOf := { name | | seen, work, cur, r |
    seen := array:new.
    work := leftRefsOf:value(gRules:at(name):body, array:new).
    { work:size:greaterThan(#0) }:whileTrue({
        cur := work:removeLast.
        seen:indexOf(cur):isNil:ifTrue({
            seen:add(cur).
            gRules:includes(cur):ifTrue({
                leftRefsOf:value(gRules:at(cur):body, array:new):do({ nx |
                    seen:indexOf(nx):isNil:ifTrue({ work:add(nx) }) }) }) }) }).
    seen }.

; Walk every node of a rule, complaining about what cannot be there. `..`, `!`
; and a reference to a syntactic rule are all questions about characters, and a
; syntactic rule has only tokens to ask them of.
checkNodes := { n, lexical | | k, kids, i, target |
    k := n:kind.
    kids := kidsOf:value(n).
    k:equals('ref):ifTrue({
        gRules:includes(n:text):ifElse({
            target := gRules:at(n:text).
            lexical:and({ target:lexical:not }):ifTrue({
                grammarError:value(n:pos,
                    "a lexical rule cannot use <{}>, which is syntactic"
                        :fill([n:text])) }) },
        { grammarError:value(n:pos, "<{}> is used and never defined"
            :fill([n:text])) }) }).
    lexical:ifFalse({
        k:equals('range):ifTrue({
            grammarError:value(n:pos,
                "'..' is a range of characters and a syntactic rule has only tokens") }).
        k:equals('not):ifTrue({
            grammarError:value(n:pos,
                "'!' is a character and a syntactic rule has only tokens") }) }).
    k:equals('lit):and({ n:text:size:equals(#0) }):ifTrue({
        grammarWarning:value(n:pos, "an empty literal matches nothing and always succeeds") }).
    i := #1.
    { i:lessOrEqual(kids:size) }:whileTrue({
        checkNodes:value(kids:at(i), lexical). i := i:add(#1) }).
    nil }.

; ---------------------------------------------------------------------------
; The one thing ordered choice gets wrong, found by reading rather than by
; failing
;
; A PEG takes the first alternative that matches and never comes back to try a
; longer one. So `stmt = "if" e "then" stmt | "if" e "then" stmt "else" stmt`
; parses the `if` without the `else`, and then the `else` is a syntax error on a
; file that is correct.
;
; It is exactly detectable in the case that matters: one alternative being a
; **proper prefix** of a later one, both of them straight lines. A signature is
; nil for anything with a choice or a repetition inside it, so nothing is
; guessed -- the check either knows or says nothing.
;
; **It runs over the lexical rules too, and that is where it earns its keep.**
; Longest match is across token *rules* and not within one, so a single rule
; reading `symbol = "." | ".."` is ordered choice like any other and will never
; produce `..` -- which is a mis-lex rather than a mis-parse, and shows up as a
; syntax error two tokens later with nothing pointing at the cause.

signatureOf := { n | | k, kids, out, i, part |
    k := n:kind.
    kids := kidsOf:value(n).
    k:equals('lit):ifElse({ ["\"":concat(n:text):concat("\"")] }, {
    k:equals('ref):ifElse({ ["<":concat(n:text):concat(">")] }, {
    k:equals('seq):ifElse({
        out := array:new. i := #1.
        { out:notNil:and({ i:lessOrEqual(kids:size) }) }:whileTrue({
            part := signatureOf:value(kids:at(i)).
            part:isNil:ifElse({ out := nil }, { part:do({ p | out:add(p) }) }).
            i := i:add(#1) }).
        out },
        { nil }) }) }) }.

isProperPrefix := { short, long | | ok, i |
    ok := short:size:lessThan(long:size).
    i := #1.
    { ok:and({ i:lessOrEqual(short:size) }) }:whileTrue({
        short:at(i):equals(long:at(i)):ifFalse({ ok := false }).
        i := i:add(#1) }).
    ok }.

; One literal's *text* being a prefix of another's, which is the same fault one
; level down. `"<" | "<="` has two alternatives of one element each, so the
; check above sees nothing wrong with it -- and it is the more damaging of the
; two, because it is a mis-lex: `<=` becomes `<` and `=`, and the complaint
; surfaces at the `=` with nothing pointing at the rule that caused it.
isTextPrefix := { short, long |
    short:size:lessThan(long:size)
        :and({ sameText:value(long:copyFrom(#1, short:size), short) }) }.

checkOrdering := { n, ruleName | | kids, i, j, si, sj, a, b |
    kids := kidsOf:value(n).
    n:kind:equals('alt):ifTrue({
        i := #1.
        { i:lessThan(kids:size) }:whileTrue({
            si := signatureOf:value(kids:at(i)).
            a := kids:at(i).
            j := i:add(#1).
            { j:lessOrEqual(kids:size) }:whileTrue({
                b := kids:at(j).
                sj := signatureOf:value(b).
                si:notNil:and({ sj:notNil }):and({ isProperPrefix:value(si, sj) })
                    :ifTrue({
                        grammarWarning:value(a:pos,
                            "in <{}>, alternative {} is a prefix of alternative {} -- ordered choice will never reach the longer one, so put it first"
                                :fill([ruleName, i:asString, j:asString])) }).
                a:kind:equals('lit):and({ b:kind:equals('lit) })
                    :and({ isTextPrefix:value(a:text, b:text) })
                    :ifTrue({
                        grammarWarning:value(a:pos,
                            "in <{}>, '{}' is written before '{}' and would always win -- the longer one has to come first"
                                :fill([ruleName, a:text, b:text])) }).
                j := j:add(#1) }).
            i := i:add(#1) }) }).
    i := #1.
    { i:lessOrEqual(kids:size) }:whileTrue({
        checkOrdering:value(kids:at(i), ruleName). i := i:add(#1) }).
    nil }.

refsOf := { n, out | | kids, i |
    n:kind:equals('ref):ifTrue({
        out:indexOf(n:text):isNil:ifTrue({ out:add(n:text) }) }).
    kids := kidsOf:value(n).
    i := #1.
    { i:lessOrEqual(kids:size) }:whileTrue({
        refsOf:value(kids:at(i), out). i := i:add(#1) }).
    out }.

; From the goal outwards, as a worklist. "Mentioned somewhere" is the wrong
; question: three abandoned rules that name each other would all be mentioned.
markReachableFrom := { roots | | work, cur |
    work := array:new.
    roots:do({ nm | work:add(nm) }).
    { work:size:greaterThan(#0) }:whileTrue({
        cur := work:removeLast.
        gRules:includes(cur):and({ gRules:at(cur):used:not }):ifTrue({
            gRules:at(cur):used := true.
            refsOf:value(gRules:at(cur):body, array:new):do({ nx | work:add(nx) }) }) }).
    nil }.

checkGrammar := { | syntactic, r, roots |
    gRules:size:equals(#0):ifTrue({
        gErrors:add("{}: grammar error: there are no rules in this file":fill([gPath])) }).

    ; A grammar with no `%syntax` has told us nothing about where the seam is,
    ; and there is no honest way to guess -- see the header.
    syntactic := gOrder:select({ name | gRules:at(name):lexical:not }).
    gRules:size:greaterThan(#0):and({ syntactic:size:equals(#0) }):ifTrue({
        gErrors:add("{}: grammar error: every rule is lexical -- put %syntax before the rules that are matched over tokens":fill([gPath])) }).

    ; %fragment first: it decides which lexical rules are tried as tokens at
    ; all, and everything after this asks that question.
    gOrder:do({ name | gRules:at(name):fragment := false }).
    gFragment:do({ name |
        gRules:includes(name):ifElse({
            gRules:at(name):lexical:ifElse({ gRules:at(name):fragment := true },
                { gErrors:add("{}: grammar error: %fragment names <{}>, which is syntactic":fill([gPath, name])) }) },
        { gErrors:add("{}: grammar error: %fragment names <{}>, which is not defined":fill([gPath, name])) }) }).
    gSkip:do({ name |
        gFragment:indexOf(name):notNil:ifTrue({
            gErrors:add("{}: grammar error: <{}> is named in both %fragment and %skip -- a fragment is never a token, so there is nothing to skip":fill([gPath, name])) }) }).
    gTokenOrder := gOrder:select({ name |
        gRules:at(name):lexical:and({ gRules:at(name):fragment:not }) }).
    gTokenOrder:size:equals(#0):and({ gRules:size:greaterThan(#0) }):ifTrue({
        gErrors:add("{}: grammar error: there are no token rules -- every lexical rule is a %fragment":fill([gPath])) }).

    computeNullable:value.
    gOrder:do({ name | gRules:at(name):used := false }).

    ; The goal rule, which is the first syntactic one unless the file says.
    gStart:isNil:ifTrue({
        syntactic:size:greaterThan(#0):ifTrue({ gStart := syntactic:at(#1) }) }).
    gStart:notNil:ifTrue({
        gRules:includes(gStart):ifElse({
            gRules:at(gStart):lexical:ifTrue({
                gErrors:add("{}: grammar error: %start names <{}>, which is a lexical rule":fill([gPath, gStart])) }).
            nil },
        { gErrors:add("{}: grammar error: %start names <{}>, which is not defined":fill([gPath, gStart])) }) }).

    gSkip:do({ name |
        gRules:includes(name):ifElse({
            gRules:at(name):lexical:ifFalse({
                gErrors:add("{}: grammar error: %skip names <{}>, which is not a token rule":fill([gPath, name])) }) },
        { gErrors:add("{}: grammar error: %skip names <{}>, which is not defined":fill([gPath, name])) }) }).

    roots := array:new.
    gStart:notNil:ifTrue({ roots:add(gStart) }).
    gSkip:do({ nm | roots:add(nm) }).
    gTokenOrder:do({ nm | roots:add(nm) }).
    markReachableFrom:value(roots).

    gOrder:do({ name |
        r := gRules:at(name).
        checkNodes:value(r:body, r:lexical).
        checkOrdering:value(r:body, name) }).

    gOrder:do({ name |
        leftClosureOf:value(name):indexOf(name):notNil:ifTrue({
            grammarError:value(gRules:at(name):pos,
                "<{}> is left-recursive -- it can begin by matching itself, which never stops. Write the repetition with "
                    :fill([name]):concat("{ }"):concat(" instead.")) }) }).

    ; A token rule nobody names is still tried on every character, so an unused
    ; *syntactic* rule is the only one worth mentioning -- and it is a warning,
    ; because a grammar under construction has them on purpose.
    gOrder:do({ name |
        r := gRules:at(name).
        r:used:or({ r:lexical }):ifFalse({
            grammarWarning:value(r:pos,
                "<{}> is defined and never used":fill([name])) }) }).
    nil }.

; ---------------------------------------------------------------------------
; The lexical half: characters to tokens
;
; **Longest match over every token rule, first rule winning a tie.** That is
; what every lexer does, and it is the reason the ordered-choice warning above
; is about syntactic rules only: `"<" | "<="` is a question here and the answer
; is `<=`, without the grammar having to put the longer one first.
;
; A character that begins no token at all is a lexical error. The scan then
; **steps over one character and carries on**, which is the arrangement
; [log.sol](log.sol) argued for: a file with two bad characters in it should
; report two, and a report that stops at the first tells you least about the
; file you know least about.

sSrc := "".
sPath := "".
cpos := #1.

; The matcher over characters. Same shape as the one over tokens below, and
; deliberately a separate block rather than one matcher with a mode flag: the
; two disagree about what every kind of node *means*, and a flag would put that
; disagreement inside eight `ifElse`s instead of between two blocks.
charMatch := { n | | k, kids, save, i, ok, going, last, c, lo, from, to |
    k := n:kind.
    kids := kidsOf:value(n).

    k:equals('lit):ifElse({
        n:text:size:equals(#0):ifElse({ true }, {
            last := cpos:add(n:text:size):sub(#1).
            last:greaterThan(sSrc:size):ifElse({ false }, {
                sameText:value(sSrc:copyFrom(cpos, last), n:text)
                    :ifElse({ cpos := last:add(#1). true }, { false }) }) }) }, {

    k:equals('range):ifElse({
        cpos:greaterThan(sSrc:size):ifElse({ false }, {
            c := sSrc:at(cpos).
            from := n:text. to := n:upTo.
            gIgnoreCase:ifTrue({
                c := c:asLowercase. from := from:asLowercase. to := to:asLowercase }).
            c:greaterOrEqual(from):and({ c:lessOrEqual(to) })
                :ifElse({ cpos := cpos:add(#1). true }, { false }) }) }, {

    k:equals('not):ifElse({
        save := cpos.
        ok := charMatch:value(kids:at(#1)):not.
        cpos := save.
        ok:and({ cpos:lessOrEqual(sSrc:size) })
            :ifElse({ cpos := cpos:add(#1). true }, { false }) }, {

    k:equals('ref):ifElse({ charMatch:value(gRules:at(n:text):body) }, {

    k:equals('opt):ifElse({
        save := cpos.
        charMatch:value(kids:at(#1)):ifFalse({ cpos := save }).
        true }, {

    k:equals('rep):ifElse({
        going := true.
        { going }:whileTrue({
            save := cpos.
            charMatch:value(kids:at(#1)):and({ cpos:greaterThan(save) })
                :ifFalse({ cpos := save. going := false }) }).
        true }, {

    k:equals('alt):ifElse({
        save := cpos. ok := false. i := #1.
        { ok:not:and({ i:lessOrEqual(kids:size) }) }:whileTrue({
            cpos := save.
            charMatch:value(kids:at(i)):ifTrue({ ok := true }).
            i := i:add(#1) }).
        ok:ifFalse({ cpos := save }).
        ok },

      { save := cpos. ok := true. i := #1.
        { ok:and({ i:lessOrEqual(kids:size) }) }:whileTrue({
            charMatch:value(kids:at(i)):ifFalse({ ok := false }).
            i := i:add(#1) }).
        ok:ifFalse({ cpos := save }).
        ok }) }) }) }) }) }) }) }.

; A byte as it can be shown in a message. The first version put the character
; straight into the text, and a file with a stray newline in the wrong place
; produced an error report two lines tall with an empty second line.
showCharacter := { c | | b |
    b := c:asByte.
    c:equals("\n"):ifElse({ "\\n" }, {
    c:equals("\t"):ifElse({ "\\t" }, {
    c:equals("\r"):ifElse({ "\\r" }, {
    b:lessThan(#32):or({ b:greaterThan(#126) })
        :ifElse({ "\\x":concat(b:asBase(#16)) }, { c }) }) }) }) }.

token := object:new. token:kind := "". token:text := "". token:pos := #0.
makeToken := { kind, text, pos | | t |
    t := token:new. t:kind := kind. t:text := text. t:pos := pos. t }.

lexErrors := array:new.

; Answers the tokens; the errors are left in `lexErrors` so that a caller who
; only wants to know whether a keyword is one token can ignore them.
tokenise := { src | | out, best, bestLen, bestName, start, gathering |
    sSrc := src.
    out := array:new.
    cpos := #1.
    { cpos:lessOrEqual(src:size) }:whileTrue({
        start := cpos.
        bestLen := #0. bestName := nil.
        gTokenOrder:do({ name |
            cpos := start.
            charMatch:value(gRules:at(name):body):ifTrue({
                cpos:sub(start):greaterThan(bestLen):ifTrue({
                    bestLen := cpos:sub(start). bestName := name }) }) }).
        bestName:isNil:ifElse({
            lexErrors:add([start, src:at(start)]).
            cpos := start:add(#1) },
        { cpos := start:add(bestLen).
          gSkip:indexOf(bestName):isNil:ifTrue({
              out:add(makeToken:value(bestName,
                  src:copyFrom(start, cpos:sub(#1)), start)) }) }) }).
    out }.

; ---------------------------------------------------------------------------
; Reserved words, which the grammar knows without being asked
;
; `begin` tokenises as an identifier, so `x := begin` would parse: the syntactic
; rule `identifier` would happily take it. Every language that has keywords
; solves this by reserving them, and **the list is already in the grammar** --
; it is every word-shaped literal any syntactic rule mentions.
;
; Derived rather than declared, so a grammar cannot get it wrong by forgetting
; to update a list. It is kept per token kind, by tokenising the literal itself
; and seeing what it comes out as: `"begin"` is one identifier and so reserves
; the word against `identifier`, while `":="` is not a word and reserves
; nothing.

gReserved := dictionary:new.

collectLiterals := { n, out, wordsOnly | | kids, i |
    n:kind:equals('lit):and({ n:text:size:greaterThan(#0) })
        :and({ wordsOnly:not:or({ isWordShaped:value(n:text) }) }):ifTrue({
            out:indexOf(n:text):isNil:ifTrue({ out:add(n:text) }) }).
    kids := kidsOf:value(n).
    i := #1.
    { i:lessOrEqual(kids:size) }:whileTrue({
        collectLiterals:value(kids:at(i), out, wordsOnly). i := i:add(#1) }).
    out }.

computeReserved := { | words, saved, toks |
    gReserved := dictionary:new.
    words := array:new.
    gOrder:do({ name |
        gRules:at(name):lexical:ifFalse({
            collectLiterals:value(gRules:at(name):body, words, true) }) }).
    saved := lexErrors.
    words:do({ w |
        lexErrors := array:new.
        toks := tokenise:value(w).
        lexErrors:size:equals(#0):and({ toks:size:equals(#1) })
            :and({ toks:at(#1):text:size:equals(w:size) }):ifTrue({ | kind |
                kind := toks:at(#1):kind.
                gReserved:includes(kind):ifFalse({ gReserved:atPut(kind, array:new) }).
                gReserved:at(kind):add(gIgnoreCase:ifElse({ w:asLowercase }, { w })) }) }).
    lexErrors := saved.
    nil }.

; ---------------------------------------------------------------------------
; The check that the first Pascal file paid for
;
; A token kind is reachable from the syntactic half two ways: a rule names it,
; or a literal in a rule tokenises to it -- `";"` is never written as
; `symbol` anywhere, and `symbol` is plainly in use all the same. A kind that is
; reachable neither way, and is not skipped, can do nothing but produce a syntax
; error, and the likeliest reason is that it was meant to be a `%fragment`.
;
; This has to run after the rules are read, because it works by tokenising --
; which is the only way to answer "what would `";"` come out as" without a
; second implementation of longest match.
checkTokenUse := { | reachable, literals, toks |
    reachable := array:new.
    literals := array:new.
    gOrder:do({ name | | r |
        r := gRules:at(name).
        r:lexical:ifFalse({
            collectLiterals:value(r:body, literals, false).
            refsOf:value(r:body, array:new):do({ nm |
                gRules:includes(nm):and({ gRules:at(nm):lexical })
                    :ifTrue({ reachable:indexOf(nm):isNil
                        :ifTrue({ reachable:add(nm) }) }) }) }) }).
    literals:do({ w | | saved |
        saved := lexErrors.
        lexErrors := array:new.
        toks := tokenise:value(w).
        lexErrors := saved.
        toks:do({ t | reachable:indexOf(t:kind):isNil
            :ifTrue({ reachable:add(t:kind) }) }) }).
    gTokenOrder:do({ name |
        gSkip:indexOf(name):isNil:and({ reachable:indexOf(name):isNil }):ifTrue({
            grammarWarning:value(gRules:at(name):pos,
                "<{}> produces a kind of token that no syntactic rule can match -- if it is a helper for the other token rules, name it in %fragment":fill([name])) }) }).
    nil }.

isReservedAs := { kind, text | | list |
    gReserved:includes(kind):ifElse({
        list := gReserved:at(kind).
        list:indexOf(gIgnoreCase:ifElse({ text:asLowercase }, { text })):notNil },
      { false }) }.

; ---------------------------------------------------------------------------
; The syntactic half: tokens against the grammar
;
; **Where the error is reported from, which is the whole difficulty.**
;
; A backtracking matcher fails at the *top*: the goal rule returns false, and the
; position it returns at is the start of the file, because everything it tried
; was rolled back. That is useless -- `myprog.pas:1: does not parse` is a
; sentence about the program that printed it.
;
; So the position is not taken from where the match ended. It is taken from
; **the furthest token any terminal ever failed at**, recorded as the match goes
; and never rolled back. That token is where the file stopped being Pascal, and
; the set of terminals that were wanted there is the list of things that would
; have let it continue. It is the standard answer for this shape of parser and
; it is the reason the messages below name a column and a set.
;
; The innermost syntactic rule in play at that moment is kept too, so the
; message can say *what was being read* -- `in <statement>` -- which is the
; difference between a list of punctuation and a sentence.

tks := array:new.
tpos := #1.
tfar := #1.
tfarExpected := dictionary:new.
tfarRule := nil.
ruleStack := array:new.
ruleStart := array:new.

tokAt := { i | i:lessOrEqual(tks:size):ifElse({ tks:at(i) }, { nil }) }.

; **Which rule to name is not "the innermost one".** At the moment a terminal
; fails, the innermost rule in play is usually a leaf like
; `multiplying-operator`, entered at the failing token and describing the token
; that is missing rather than the thing being read. The useful answer is the
; innermost rule that has already *consumed* something -- it began before the
; trouble, so it is the construct the reader is in the middle of. That turns
; `reading <multiplying-operator>` into `reading <if-statement>`.
noteExpected := { what | | i |
    tpos:greaterThan(tfar):ifTrue({
        tfar := tpos.
        tfarExpected := dictionary:new.
        tfarRule := nil.
        i := ruleStack:size.
        { tfarRule:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
            ruleStart:at(i):lessThan(tfar):ifTrue({ tfarRule := ruleStack:at(i) }).
            i := i:sub(#1) }).
        tfarRule:isNil:and({ ruleStack:size:greaterThan(#0) })
            :ifTrue({ tfarRule := ruleStack:at(ruleStack:size) }) }).
    tpos:equals(tfar):ifTrue({ tfarExpected:atPut(what, true) }).
    nil }.

; One frame a level, and the staircase costs none -- which is what the depth at
; the bottom of this file is spent on. `do` over the children would double it.
tokMatch := { n | | k, kids, save, i, ok, going, t, r, body |
    k := n:kind.
    kids := kidsOf:value(n).

    k:equals('lit):ifElse({
        t := tokAt:value(tpos).
        t:notNil:and({ sameText:value(t:text, n:text) })
            :ifElse({ tpos := tpos:add(#1). true },
                    { noteExpected:value("'":concat(n:text):concat("'")). false }) }, {

    k:equals('ref):ifElse({
        r := gRules:at(n:text).
        r:lexical:ifElse({
            t := tokAt:value(tpos).
            t:notNil:and({ t:kind:equals(n:text) })
                :and({ isReservedAs:value(n:text, t:text):not })
                :ifElse({ tpos := tpos:add(#1). true },
                        { noteExpected:value(n:text). false }) },
          { ruleStack:add(n:text). ruleStart:add(tpos).

            ; **A rule whose body is an alternation runs it here rather than
            ; recursing into it, which is a frame per level of grammar.**
            ; Descending one rule costs a frame for the reference, one for the
            ; body's `alt` and one for the chosen `seq`; this removes the
            ; middle one wherever the body is an `alt` at all.
            ;
            ; Measured on Pascal rather than assumed, because the guess was
            ; wrong: this is worth a *third* of the frames only if every rule
            ; body is an alternation, and in Wirth's Pascal most are sequences.
            ; The real numbers are 16 levels of nested `begin if` before this
            ; and **19** after, and 25 nested parentheses before and **28**
            ; after -- about a sixth, for eleven lines. Kept because a sixth of
            ; the depth is worth eleven lines, and recorded because the
            ; difference between a third and a sixth is the difference between
            ; the shape of the matcher and the shape of the grammar.
            body := r:body.
            body:kind:equals('alt):ifElse({
                save := tpos. ok := false. i := #1.
                { ok:not:and({ i:lessOrEqual(body:kids:size) }) }:whileTrue({
                    tpos := save.
                    tokMatch:value(body:kids:at(i)):ifTrue({ ok := true }).
                    i := i:add(#1) }).
                ok:ifFalse({ tpos := save }) },
              { ok := tokMatch:value(body) }).

            ruleStack:removeLast. ruleStart:removeLast.
            ok }) }, {

    k:equals('opt):ifElse({
        save := tpos.
        tokMatch:value(kids:at(#1)):ifFalse({ tpos := save }).
        true }, {

    k:equals('rep):ifElse({
        going := true.
        { going }:whileTrue({
            save := tpos.
            tokMatch:value(kids:at(#1)):and({ tpos:greaterThan(save) })
                :ifFalse({ tpos := save. going := false }) }).
        true }, {

    k:equals('alt):ifElse({
        save := tpos. ok := false. i := #1.
        { ok:not:and({ i:lessOrEqual(kids:size) }) }:whileTrue({
            tpos := save.
            tokMatch:value(kids:at(i)):ifTrue({ ok := true }).
            i := i:add(#1) }).
        ok:ifFalse({ tpos := save }).
        ok }, {

    k:equals('range):or({ k:equals('not) }):ifElse({ false },

      { save := tpos. ok := true. i := #1.
        { ok:and({ i:lessOrEqual(kids:size) }) }:whileTrue({
            tokMatch:value(kids:at(i)):ifFalse({ ok := false }).
            i := i:add(#1) }).
        ok:ifFalse({ tpos := save }).
        ok }) }) }) }) }) }) }.

; ---------------------------------------------------------------------------
; Saying it

errorCount := #0.

; How much of the offending line to show. **A line is not always a line.** The
; first version printed the whole of it, which is right for source code and
; produced four thousand bytes of one screen when somebody handed this a binary
; file -- so there is a window, and it moves to keep the caret inside it.
lineWindow := #96.

; A caret under the character, because a line number alone makes the reader
; count columns by hand and a column number alone makes them count twice.
;
; The line is rendered a byte at a time through `showCharacter`, so a stray
; control byte becomes `\x1b` rather than moving the cursor -- and the caret is
; measured on the *rendered* width rather than on the byte offset, since an
; escaped byte is four columns wide and a tab is one.
reportAt := { path, src, pos, severity, message |
              | lc, line, column, text, shown, pad, i, from, to, head, tail, width |
    lc := lineColumnIn:value(src, pos).
    line := lc:at(#1). column := lc:at(#2).
    "{}:{}:{}: {}: {}":fill([path, line, column, severity, message]):display.

    text := lineTextIn:value(src, pos).
    text:size:greaterThan(#0):ifTrue({

        ; The window, kept around the caret. **Measured in rendered columns and
        ; not in bytes**, which is the second half of the same lesson: a line
        ; of binary escapes to four columns a byte, so a 96-byte window is a
        ; 384-column line and the wrapping puts the caret nowhere near the
        ; character it points at.
        width := #0. from := column.
        { from:greaterThan(#1):and({ width:lessThan(lineWindow:div(#2)) }) }
            :whileTrue({
                width := width:add(
                    showCharacter:value(text:at(from:sub(#1))):size).
                from := from:sub(#1) }).
        width := #0. to := from:sub(#1).
        { to:lessThan(text:size):and({ width:lessThan(lineWindow) }) }:whileTrue({
            width := width:add(showCharacter:value(text:at(to:add(#1))):size).
            to := to:add(#1) }).
        head := from:greaterThan(#1):ifElse({ "..." }, { "" }).
        tail := to:lessThan(text:size):ifElse({ "..." }, { "" }).

        shown := "". pad := head:size:equals(#0):ifElse({ "" }, { "   " }).
        i := from.
        { i:lessOrEqual(to) }:whileTrue({ | rendered |
            rendered := showCharacter:value(text:at(i)).
            shown := shown:concat(rendered).
            i:lessThan(column):ifTrue({
                ; A tab is left as a tab so the caret lands under the character
                ; a terminal actually shows; everything else is padded to the
                ; width it was rendered at.
                rendered:equals("\\t"):ifElse({ pad := pad:concat("\t") }, {
                    rendered:size:repeat({ pad := pad:concat(" ") }) }) }).
            i := i:add(#1) }).

        "  {} | {}{}{}":fill([line:asString(">4"), head, shown, tail]):display.
        column:greaterOrEqual(from):and({ column:lessOrEqual(to:add(#1)) }):ifTrue({
            "  {} | {}^":fill([" ":asString(">4"), pad]):display }) }).
    errorCount := errorCount:add(#1).
    nil }.

; The expected set, in a fixed order so that two runs of the same file say the
; same thing, and capped because a list of thirty is a list nobody reads.
expectedText := { | names, shown |
    names := tfarExpected:keys:sorted.
    shown := names:first(#6).
    shown:size:equals(#1):ifElse({ shown:at(#1) }, {
        shown:size:lessThan(names:size):ifElse({
            shown:join(", "):concat(", or one of {} others":fill([names:size:sub(shown:size)])) },
          { shown:first(shown:size:sub(#1)):join(", ")
                :concat(" or "):concat(shown:at(shown:size)) }) }) }.

describeToken := { t |
    t:isNil:ifElse({ "the end of the file" }, {
        "'":concat(t:text:size:greaterThan(#20)
            :ifElse({ t:text:copyFrom(#1, #20):concat("...") }, { t:text })):concat("'") }) }.

; ---------------------------------------------------------------------------
; A run
;
; The grammar and the subject arrive as text rather than as paths, so that the
; demonstration at the bottom can run the whole program on strings it carries
; itself -- which is the house rule for this directory, and the reason every
; program here says something when run with no arguments at all.

; One `s`, in one place, rather than in the four messages that need one.
plural := { n, word |
    "{} {}{}":fill([n, word, n:equals(#1):ifElse({ "" }, { "s" })]) }.

describeGrammar := { | syn |
    syn := gOrder:select({ n | gRules:at(n):lexical:not }).
    "{}: {}, {}, {}, start <{}>{}"
        :fill([gPath, plural:value(gTokenOrder:size, "token rule"),
               plural:value(gFragment:size, "fragment"),
               plural:value(syn:size, "syntactic rule"),
               gStart:isNil:ifElse({ "?" }, { gStart }),
               gIgnoreCase:ifElse({ ", case-insensitive" }, { "" })]):display.
    gSkip:size:greaterThan(#0):ifTrue({
        "  skipping: {}":fill([gSkip:join(", ")]):display }).
    gReserved:size:greaterThan(#0):ifTrue({
        gReserved:keysAndValuesDo({ kind, words |
            "  reserved against <{}>: {}"
                :fill([kind, words:sorted:join(" ")]):display }) }).
    nil }.

; Answers a status: 0 clean, 1 the subject is wrong, 2 the grammar is.
loadGrammar := { path, text | | bad |
    readGrammar:value(path, text).
    checkGrammar:value.
    bad := gErrors:size:greaterThan(#0).

    ; These two work by tokenising, so they can only run once the rules are
    ; known to be sound -- and the token-use warning is worth the ordering,
    ; because it is the one that catches a missing %fragment.
    bad:ifFalse({ computeReserved:value. checkTokenUse:value }).

    gWarnings:do({ w | w:display }).
    gErrors:do({ e | e:display }).
    bad:ifElse({ #2 }, { #0 }) }.

; **Reported, and then counted.** A file this program was never meant to be
; handed -- a binary, a compressed archive -- is a lexical error per byte, and
; 1,673 of them is not a report. The first twenty are shown and the rest are
; counted, so the summary line stays true and the screen stays readable.
lexErrorsShown := #20.

reportLexErrors := { path, text | | i |
    i := #1.
    lexErrors:do({ pair |
        i:lessOrEqual(lexErrorsShown):ifElse({
            reportAt:value(path, text, pair:at(#1), "lexical error",
                "no token rule matches '{}'"
                    :fill([showCharacter:value(pair:at(#2))])) },
          { errorCount := errorCount:add(#1) }).
        i := i:add(#1) }).
    lexErrors:size:greaterThan(lexErrorsShown):ifTrue({
        "{}: {} not shown"
            :fill([path, plural:value(lexErrors:size:sub(lexErrorsShown),
                                      "further lexical error")]):display }).
    nil }.

dumpTokens := { path | | lc |
    tks:do({ t |
        lc := lineColumnIn:value(sSrc, t:pos).
        "{}:{}:{}: {} {}":fill([path, lc:at(#1), lc:at(#2), t:kind:asString("<12"),
            t:text:size:greaterThan(#30)
                :ifElse({ t:text:copyFrom(#1, #30):concat("...") }, { t:text })]):display }).
    "{}: {}":fill([path, plural:value(tks:size, "token")]):display.
    nil }.

matchSubject := { path, text | | ok, t, pos |
    tpos := #1. tfar := #1. tfarExpected := dictionary:new.
    tfarRule := nil. ruleStack := array:new. ruleStart := array:new.

    ; The goal rule goes on the stack like any other, so that a failure at the
    ; very top -- the `.` after `end` in Pascal -- can still say what was being
    ; read. Calling its body directly left the stack empty and the message
    ; without a context, which is the one place the context is most obviously
    ; wanted.
    ruleStack:add(gStart). ruleStart:add(#1).
    ok := tokMatch:value(gRules:at(gStart):body).

    ok:and({ tpos:greaterThan(tks:size) }):ifElse({ nil }, {
        ok:ifTrue({ noteExpected:value("the end of the file") }).
        t := tokAt:value(tfar).
        pos := t:isNil:ifElse({ text:size:add(#1) }, { t:pos }).
        reportAt:value(path, text, pos, "syntax error",
            "expected {}, found {}{}":fill([
                expectedText:value,
                describeToken:value(t),
                tfarRule:isNil:ifElse({ "" },
                    { ", reading <{}>":fill([tfarRule]) })])) }).
    nil }.

check := { grammarPath, grammarText, subjectPath, subjectText, mode | | status |
    errorCount := #0.
    status := loadGrammar:value(grammarPath, grammarText).
    status:equals(#0):ifElse({
        mode:equals("grammar"):ifElse({ describeGrammar:value. #0 }, {
            lexErrors := array:new.
            tks := tokenise:value(subjectText).
            reportLexErrors:value(subjectPath, subjectText).
            mode:equals("tokens"):ifElse({ dumpTokens:value(subjectPath). #0 }, {
                { matchSubject:value(subjectPath, subjectText) }:onError({ e |
                    ; `call depth exceeded` arrives here like any other failure,
                    ; and saying so is the whole difference between a diagnostic
                    ; and a crash. What it means is at the bottom of this file.
                    "{}: {} -- the grammar nests too deeply for this file"
                        :fill([subjectPath, e:message]):display.
                    errorCount := errorCount:add(#1) }).
                errorCount:equals(#0):ifElse({
                    "{}: {}, no errors"
                        :fill([subjectPath, plural:value(tks:size, "token")]):display.
                    #0 },
                  { "{}: {}":fill([subjectPath,
                        plural:value(errorCount, "error")]):display.
                    #1 }) }) }) },
      { status }) }.

readOr := { path |
    { system:readFile(path) }:onError({ e |
        "check_syntax: cannot read {} -- {}":fill([path, e:message]):display.
        nil }) }.

checkFiles := { grammarPath, subjectPath, mode | | gtext, stext |
    gtext := readOr:value(grammarPath).
    stext := subjectPath:isNil:ifElse({ "" }, { readOr:value(subjectPath) }).
    gtext:isNil:or({ stext:isNil }):ifElse({ #2 },
        { check:value(grammarPath, gtext,
            subjectPath:isNil:ifElse({ "" }, { subjectPath }), stext, mode) }) }.

usage := {
    "usage: solvm check_syntax.sob grammar.bnf source [tokens]":display.
    "       solvm check_syntax.sob grammar.bnf          -- the grammar alone":display.
    "       solvm check_syntax.sob                      -- the demonstration":display.
    nil }.

; ---------------------------------------------------------------------------
; The demonstration
;
; Every program in this directory runs on input it carries itself, because a
; program you have to feed before it will say anything is a program you will not
; run. The grammars below are strings rather than files for exactly that reason
; -- and because `check` was given text rather than paths so that they could be.
;
; The literals are written with `'single quotes'`, which this notation accepts
; alongside `"double"`. That is not decoration: it is what lets a grammar sit
; inside a Solum string without every quote in it being escaped.

banner := { text |
    "":display.
    "-- {}":fill([text]):display }.

demoGrammar := [
    "(* A small language, enough to show every kind of error. *)",
    "%fragment letter digit",
    "letter = 'a' .. 'z' .",
    "digit  = '0' .. '9' .",
    "name   = letter { letter | digit } .",
    "number = digit { digit } .",
    "space  = (' ' | '\\t' | '\\n') { ' ' | '\\t' | '\\n' } .",
    "symbol = ':=' | '<=' | '>=' | '<>' | '+' | '-' | '*' | '/'",
    "       | '(' | ')' | ';' | '=' | '<' | '>' .",
    "%skip space",
    "",
    "%syntax",
    "%start block",
    "block      = 'begin' statement { ';' statement } 'end' .",
    "statement  = block | name ':=' expression .",
    "expression = term { ('+' | '-') term } .",
    "term       = factor { ('*' | '/') factor } .",
    "factor     = number | name | '(' expression ')' ."
]:join("\n").

; The older dialect, and the mistake it invites. `<expr> ::= <expr> "+" ...`
; is how a BNF written before 1977 says "one or more", and it is the one thing
; a matcher like this cannot do -- so it is read, recognised and refused rather
; than run into the ground.
leftRecursive := [
    "%fragment digit",
    "digit  = '0' .. '9' .",
    "number = digit { digit } .",
    "symbol = '+' | '*' .",
    "space  = ' ' { ' ' } .",
    "%skip space",
    "%syntax",
    "<expr>   ::= <expr> '+' <term> | <term>",
    "<term>   ::= <term> '*' <factor> | <factor>",
    "<factor> ::= number"
]:join("\n").

; Two alternatives the wrong way round, in each half. The lexical one is the
; one that would be silent: `<=` never becomes a token, and the complaint
; arrives at the `=` as though the file had a stray one in it.
misordered := [
    "%fragment letter",
    "letter = 'a' .. 'z' .",
    "name   = letter { letter } .",
    "symbol = '<' | '<=' .",
    "space  = ' ' { ' ' } .",
    "%skip space",
    "%syntax",
    "%start compare",
    "compare   = 'if' name 'then' compare",
    "          | 'if' name 'then' compare 'else' compare",
    "          | name '<' name ."
]:join("\n").

demonstrate := {
    "check_syntax -- a grammar, and a file held against it":display.
    "":display.
    usage:value.
    "":display.
    "The grammar used below, in Wirth's notation:":display.
    demoGrammar:split("\n"):do({ line |
        line:trim:size:greaterThan(#0):ifTrue({ "    {}":fill([line]):display }) }).

    banner:value("what the grammar says about itself").
    check:value("demo.bnf", demoGrammar, "", "", "grammar").

    banner:value("a file that agrees with it").
    check:value("demo.bnf", demoGrammar, "ok.txt",
        "begin x := 1; y := x * (2 + 3) end", "").

    banner:value("a missing semicolon").
    check:value("demo.bnf", demoGrammar, "semicolon.txt",
        "begin\n  x := 1\n  y := 2\nend", "").

    banner:value("a bracket never closed").
    check:value("demo.bnf", demoGrammar, "bracket.txt",
        "begin\n  x := (1 + 2\nend", "").

    banner:value("a character no token rule matches").
    check:value("demo.bnf", demoGrammar, "lexical.txt",
        "begin\n  x := 1 @ 2;\n  y := 3 ? 4\nend", "").

    ; `end` is a reserved word because a syntactic rule mentions it, and
    ; nothing in the grammar had to say so.
    banner:value("a keyword used as a name").
    check:value("demo.bnf", demoGrammar, "reserved.txt",
        "begin\n  end := 1\nend", "").

    banner:value("the same file, as tokens").
    check:value("demo.bnf", demoGrammar, "ok.txt",
        "begin x := 12 * (y + 3) end", "tokens").

    banner:value("a grammar that is left-recursive, in the older dialect").
    check:value("old.bnf", leftRecursive, "", "", "grammar").

    banner:value("a grammar whose alternatives are the wrong way round").
    check:value("misordered.bnf", misordered, "", "", "grammar").

    nil }.

; ---------------------------------------------------------------------------
; What to do about the arguments

args := system:arguments.

args:size:equals(#0):ifTrue({ demonstrate:value }).
args:size:equals(#1):ifTrue({
    system:exit(checkFiles:value(args:at(#1), nil, "grammar")) }).
; The third word is the only free-form thing a caller types, so it is checked
; here rather than inside `checkFiles` -- which is also handed `"grammar"`, a
; mode this program uses on itself and nobody asks for by name.
args:size:greaterOrEqual(#2):ifTrue({ | mode |
    mode := args:size:greaterOrEqual(#3):ifElse({ args:at(#3) }, { "" }).
    mode:equals(""):or({ mode:equals("tokens") }):ifFalse({
        "check_syntax: '{}' is not a mode -- the only one is 'tokens'"
            :fill([mode]):display.
        usage:value.
        system:exit(#2) }).
    system:exit(checkFiles:value(args:at(#1), args:at(#2), mode)) }).

; ---------------------------------------------------------------------------
; What it cost in frames, which is the number this program is here to report
;
; A tree-walking matcher recurses once per node of the grammar, and Solum's
; frames run out at 254. So the question is not whether this hits the limit but
; where, and the answer had to be measured against a real grammar rather than
; guessed from the shape of the matcher.
;
; **Against pascal.bnf, on this machine: 19 levels of nested `begin ... if`, and
; 28 nested parentheses in one expression.** Descending one level of Pascal
; statement nesting costs about four rule references, and a rule reference costs
; two frames -- one for the reference and one for the sequence it chooses.
;
; Three things about that are worth having written down.
;
; **It is a diagnostic and not a crash.** `call depth exceeded` arrives at
; `onError` like any other failure -- which `evaluator.sol` established and this
; program depends on -- so a file too deep for the matcher is reported as being
; too deep, by name, and the exit status is an error rather than a signal. The
; alternative is a checker that dies on the input it was given and says nothing
; about why.
;
; **The frames are spent on the grammar, not on the file.** A ten-thousand-line
; Pascal program with ordinary nesting uses the same depth as a ten-line one.
; What costs depth is a construct inside a construct, and 19 of those is past
; anything written by hand -- it is generated code that reaches it, which is
; also the code nobody reads the error message of.
;
; **Where the depth went is not where it looked.** Inlining a rule's alternation
; into the reference that names it (see `tokMatch`) was expected to be worth a
; third of the frames, one of three per level. It was worth a sixth: 16 levels
; became 19, and 25 parentheses became 28. The difference is that most of
; Wirth's Pascal rules have a *sequence* for a body rather than an alternation,
; so most of them never had the middle frame to save. A measurement of the
; matcher would have said a third. Only a measurement through a grammar says a
; sixth.
;
; An explicit stack machine -- a list of instructions and a backtrack stack --
; has no such limit, and is the thing to build if this is ever pointed at
; generated input. It was not built here because it costs the property this
; version has of being readable against the notation it implements, and because
; the limit it removes is one no hand-written file reaches. That is a trade
; recorded rather than settled.
;
; ---------------------------------------------------------------------------
; What the grammar had to say about itself
;
; **Every diagnostic this program has about grammars came from a grammar being
; wrong, and every one of them was wrong in a way that blamed the wrong file.**
; That is the pattern, and it is why the checking half is as large as the
; matching half.
;
;   `%fragment`  The first Pascal file read as a stream of `letter` and `digit`.
;                Both rules match `T`; longest match ties go to the rule
;                declared first; `letter` is declared first. The report was 130
;                syntax errors in a file with nothing wrong with it. The
;                directive says which lexical rules are helpers, and the warning
;                -- a token kind no syntactic rule can match -- finds the case
;                where somebody forgot it.
;
;   ordering     `symbol = "." | ".."` never produces `..`, because ordered
;                choice inside one rule is not longest match across rules. The
;                subrange `1 .. 20` then fails at the second `.` and the message
;                points at the type declaration. Two alternatives, one literal a
;                prefix of the other, is exactly detectable, so it is detected.
;
;   left         `<expr> ::= <expr> "+" <term>` is how the older dialect writes
;   recursion    iteration and is the one thing this matcher cannot do at all.
;                Left unchecked it exhausts the frames, and the message is
;                `call depth exceeded` against the *subject* file -- a sentence
;                about Pascal when the mistake is in the BNF. It is found by
;                reading the grammar, before anything is matched.
;
; The one that is stated rather than checked is ordered choice itself: a choice
; that succeeds is never revisited when the rule containing it fails later. On
; an LL(1) grammar -- Wirth's Pascal, and most published grammars -- that costs
; nothing. Where it costs something, the prefix check above is the part of it
; that can be found by looking, and the rest is in the header in as many words,
; because a limitation a program does not admit to is one its user discovers as
; a wrong answer.
