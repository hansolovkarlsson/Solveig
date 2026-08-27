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
; One object with a kind. **Nothing walks this tree at match time any more** --
; it is compiled to instructions once and the machine runs those -- so the shape
; below is now the compiler's input rather than the matcher's, and it is kept
; because it is the shape the *notation* has. Reading a grammar produces a tree
; because a grammar is one.
;
; It is still walked by recursion at *compile* time, and by every check in the
; section on grammars, all of which run once and none of which is hot. That is
; where [control.sol](../lib/control.sol)'s rule still applies: `ifElseIf` costs
; three frames a level and belongs outside a recursion, so it appears once in
; this file, in the grammar's own lexer, and nowhere else.
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

; ---------------------------------------------------------------------------
; The machine
;
; **The grammar is compiled to instructions and run by a loop, because a tree
; walked by recursion costs a frame per node and Solum has 254 of them.**
;
; That limit was measured rather than feared: 19 levels of nested `begin ... if`
; against Wirth's Pascal, 13 nested blocks against Solum -- and
; `experiment/lexer.sol`, a file already in this repository, reached it. The
; recursive matcher this replaces is the one those numbers were taken with, and
; the whole of what it did wrong was to keep its stack somewhere it did not own.
;
; So the stack moves here, into arrays. Depth is bounded by memory now, which is
; the same thing as saying it is not bounded by anything a grammar or a file
; will reach.
;
; ---------------------------------------------------------------------------
; The instruction set, which is LPeg's
;
; Roberto Ierusalimschy, *A Text Pattern-Matching Tool based on Parsing
; Expression Grammars* (2009), which is the machine behind Lua's `lpeg`. It is
; eleven instructions and the interesting three are about *choice*:
;
;   Call t / Ret        enter a rule, leave it
;   Choice t            remember: if what follows fails, rewind and go to `t`
;   Commit t            it did not fail -- throw that memory away, go to `t`
;   LoopCommit t        Commit, unless nothing was consumed
;   FailTwice           throw it away *and* fail, which is negative lookahead
;   MatchChars/Range/Any        terminals over characters
;   MatchText/MatchKind         terminals over tokens
;
; **Every EBNF construct is two or three of them**, and the compiler below is
; the whole translation:
;
;     a b       ->  <a> <b>
;     a | b     ->  Choice L1 ; <a> ; Commit L2 ; L1: <b> ; L2:
;     [ a ]     ->  Choice L1 ; <a> ; Commit L1 ; L1:
;     { a }     ->  L1: Choice L2 ; <a> ; LoopCommit L1 ; L2:
;     ! a       ->  Choice L1 ; <a> ; FailTwice ; L1: Any
;
; **One stack holds both return addresses and choice points**, and that is not
; an economy -- it is what makes backtracking correct. Popping to a choice point
; discards every call made since it, which is exactly the unwinding the
; recursive version got from the language and had to be given here.
;
; **`LoopCommit` is where the old empty-repetition guard went.** `{ a }` where
; `a` can match nothing would spin forever; the recursive matcher compared
; positions each turn, and here the position at the choice point is already on
; the stack, so the comparison is free.
;
; ---------------------------------------------------------------------------
; What this cost, stated plainly
;
; **Legibility.** The matcher it replaces read beside the notation it
; implemented -- `alt` was a loop over alternatives, and you could hold the two
; side by side. This reads as a bytecode interpreter, and the shape of a grammar
; is visible only in the compiler that emitted the code. That is a real loss and
; it is the reason the trade was recorded as unsettled rather than taken the
; first time.
;
; **What is left of the limit is in a better place.** `compileNode` recurses over
; the grammar tree, so a *grammar* that nests brackets a few hundred deep still
; runs out of frames. That is a property of the grammar file, reported the same
; way every time, before any subject is read -- not a property of the input,
; discovered on the one file that happened to be deep.

instruction := object:new.
instruction:op := 'ret.
instruction:text := "".
instruction:upTo := "".
instruction:target := #0.
instruction:folded := "".      ; `text` lowercased, for %ignorecase

vmCode := array:new.          ; every rule's code, end to end
vmEntry := dictionary:new.    ; rule name -> where its code starts
vmPos := #1.                  ; the subject position: a character, or a token

; Answers where it put the instruction, so the caller can patch its target once
; it knows where the jump goes. Forward references are the normal case here:
; `Choice` is emitted before anything it might skip over exists.
emitAt := { op | | i |
    i := instruction:new. i:op := op. vmCode:add(i). vmCode:size }.

patchTo := { at, target | vmCode:at(at):target := target. nil }.

here := { vmCode:size:add(#1) }.

compileNode := { n, lexical | | k, kids, i, c, ends, top, e |
    k := n:kind.
    kids := kidsOf:value(n).

    k:equals('lit):ifTrue({
        ; An empty literal matches and consumes nothing, so it is no
        ; instruction at all rather than an instruction that does nothing.
        n:text:size:greaterThan(#0):ifTrue({
            e := emitAt:value(lexical:ifElse({ 'matchChars }, { 'matchText })).
            vmCode:at(e):text := n:text.
            vmCode:at(e):folded := n:text:asLowercase }) }).

    k:equals('range):ifTrue({
        e := emitAt:value('matchRange).
        vmCode:at(e):text := n:text.
        vmCode:at(e):upTo := n:upTo }).

    k:equals('not):ifTrue({
        c := emitAt:value('choice).
        compileNode:value(kids:at(#1), lexical).
        emitAt:value('failTwice).
        patchTo:value(c, here:value).
        emitAt:value('any) }).

    ; A reference to a *token* rule from a syntactic one is a terminal, not a
    ; call: there is nothing to enter, only a token to look at.
    k:equals('ref):ifTrue({
        lexical:not:and({ gRules:at(n:text):lexical }):ifElse({
            e := emitAt:value('matchKind) },
          { e := emitAt:value('call) }).
        vmCode:at(e):text := n:text }).

    k:equals('seq):ifTrue({
        i := #1.
        { i:lessOrEqual(kids:size) }:whileTrue({
            compileNode:value(kids:at(i), lexical).
            i := i:add(#1) }) }).

    k:equals('alt):ifTrue({
        ends := array:new.
        i := #1.
        { i:lessThan(kids:size) }:whileTrue({
            c := emitAt:value('choice).
            compileNode:value(kids:at(i), lexical).
            ends:add(emitAt:value('commit)).
            patchTo:value(c, here:value).
            i := i:add(#1) }).
        ; The last alternative needs no choice point: there is nothing left to
        ; fall through to, so its failure is the whole alternation's.
        compileNode:value(kids:at(kids:size), lexical).
        ends:do({ at | patchTo:value(at, here:value) }) }).

    k:equals('opt):ifTrue({
        c := emitAt:value('choice).
        compileNode:value(kids:at(#1), lexical).
        e := emitAt:value('commit).
        patchTo:value(e, here:value).
        patchTo:value(c, here:value) }).

    k:equals('rep):ifTrue({
        top := here:value.
        c := emitAt:value('choice).
        compileNode:value(kids:at(#1), lexical).
        e := emitAt:value('loopCommit).
        patchTo:value(e, top).
        patchTo:value(c, here:value) }).
    nil }.

; Both halves into one program. They never call each other -- a lexical rule
; naming a syntactic one is refused by `checkNodes` -- so the terminals a rule
; uses are decided by which half it was written in, and a run is entirely one
; mode or the other.
compileGrammar := { | r |
    vmCode := array:new.
    vmEntry := dictionary:new.
    gOrder:do({ name |
        r := gRules:at(name).
        vmEntry:atPut(name, here:value).
        compileNode:value(r:body, r:lexical).
        emitAt:value('ret) }).

    ; The calls are resolved afterwards because a rule may name one defined
    ; further down the file, which is the ordinary case and not an exception.
    vmCode:do({ i |
        i:op:equals('call):ifTrue({ i:target := vmEntry:at(i:text) }) }).
    nil }.

; ---------------------------------------------------------------------------
; The stack
;
; Four parallel arrays and a height, rather than an array of entries: this is
; pushed and popped once per rule and once per alternative over the whole of a
; file, and an object apiece would be a few million of them for nothing. The
; arrays are never shortened, only overwritten, so a run after the first
; allocates nothing at all.

stkKind := array:new.     ; 'ret or 'choice
stkPc   := array:new.     ; where to go: a return address, or an alternative
stkPos  := array:new.     ; the subject position to rewind to, or to report from
stkName := array:new.     ; the rule a 'ret entry is returning out of
stkTop  := #0.

vmPush := { kind, pc, pos, name |
    stkTop := stkTop:add(#1).
    stkTop:greaterThan(stkKind:size):ifElse({
        stkKind:add(kind). stkPc:add(pc). stkPos:add(pos). stkName:add(name) },
      { stkKind:atPut(stkTop, kind). stkPc:atPut(stkTop, pc).
        stkPos:atPut(stkTop, pos). stkName:atPut(stkTop, name) }).
    nil }.

; ---------------------------------------------------------------------------
; The loop
;
; A staircase rather than `ifElseIf`, and this is the site
; [control.sol](../lib/control.sol) describes as the one its own measurement
; rules out: many arms, and hot. Nothing here recurses, so the three frames
; would not accumulate -- they would simply be paid four million times.
;
; The arms are ordered by how often they run, which on a real file means the
; terminals first: tokenising asks `matchChars` at every character of every
; token rule, and that one arm is most of the work this program does.

runMachine := { entry, lexical, ruleName |
                | pc, ins, op, going, failing, answer, t, c, last, from, to,
                  saved, target |
    ; The goal rule goes on the stack like any other, with a return address of
    ; zero standing for "and then you are done". It is also what lets a failure
    ; at the very top -- the `.` after `end` in Pascal -- still name what was
    ; being read. Pushed by hand rather than through `vmPush`, this being once
    ; per token rule per character of the subject.
    stkTop := #1.
    stkKind:size:greaterThan(#0):ifElse({
        stkKind:atPut(#1, 'ret). stkPc:atPut(#1, #0).
        stkPos:atPut(#1, vmPos). stkName:atPut(#1, ruleName) },
      { stkKind:add('ret). stkPc:add(#0).
        stkPos:add(vmPos). stkName:add(ruleName) }).
    pc := entry.
    going := true. failing := false. answer := false.

    { going }:whileTrue({
        failing:ifElse({

            ; Unwind to the most recent choice point, restoring the position it
            ; was taken at. Every return address pushed since then goes with it,
            ; which is the whole of what backtracking has to undo.
            { failing:and({ stkTop:greaterThan(#0) }) }:whileTrue({
                stkKind:at(stkTop):equals('choice):ifTrue({
                    vmPos := stkPos:at(stkTop).
                    pc := stkPc:at(stkTop).
                    failing := false }).
                stkTop := stkTop:sub(#1) }).
            failing:ifTrue({ going := false. answer := false }) },

        { ins := vmCode:at(pc).
          op := ins:op.

          ; `sameText` spelled out rather than called, and the literal folded
          ; once at compile time rather than once per character -- 1.3%, and
          ; see the note above for why that is the number.
          ; **The arms are in frequency order, and it is worth less than it
          ; looks.** `matchRange` was eighth at first -- eight symbol
          ; comparisons for every letter of every identifier in the file, where
          ; a range is what a lexical grammar is mostly made of -- and moving it
          ; second bought **2.4%**. Spelling out `sameText` in the arm below and
          ; folding the literal at compile time bought **1.3%**.
          ;
          ; Both were predicted to be worth much more, and the measurement says
          ; what the loop actually costs: not the comparisons that choose an
          ; arm, but the fetch and the sends inside it. There is no computed
          ; jump in this language, so the order of a staircase *is* the dispatch
          ; table -- and this is the whole of what that is worth.
          op:equals('matchChars):ifElse({
              last := vmPos:add(ins:text:size):sub(#1).
              last:greaterThan(sSrc:size):ifElse({ failing := true }, {
                  c := sSrc:copyFrom(vmPos, last).
                  gIgnoreCase:ifTrue({ c := c:asLowercase }).
                  c:equals(gIgnoreCase:ifElse({ ins:folded }, { ins:text })):ifElse(
                      { vmPos := last:add(#1). pc := pc:add(#1) },
                      { failing := true }) }) }, {

          op:equals('matchRange):ifElse({
              vmPos:greaterThan(sSrc:size):ifElse({ failing := true }, {
                  c := sSrc:at(vmPos). from := ins:text. to := ins:upTo.
                  gIgnoreCase:ifTrue({
                      c := c:asLowercase.
                      from := from:asLowercase. to := to:asLowercase }).
                  c:greaterOrEqual(from):and({ c:lessOrEqual(to) }):ifElse(
                      { vmPos := vmPos:add(#1). pc := pc:add(#1) },
                      { failing := true }) }) }, {

          op:equals('choice):ifElse({
              vmPush:value('choice, ins:target, vmPos, "").
              pc := pc:add(#1) }, {

          op:equals('commit):ifElse({
              stkTop := stkTop:sub(#1).
              pc := ins:target }, {

          op:equals('call):ifElse({
              vmPush:value('ret, pc:add(#1), vmPos, ins:text).
              pc := ins:target }, {

          op:equals('ret):ifElse({
              target := stkPc:at(stkTop).
              stkTop := stkTop:sub(#1).
              target:equals(#0):ifElse({ going := false. answer := true },
                                       { pc := target }) }, {

          ; The position at the choice point is already on the stack, so the
          ; empty-repetition guard is a comparison rather than bookkeeping.
          op:equals('loopCommit):ifElse({
              saved := stkPos:at(stkTop).
              target := stkPc:at(stkTop).
              stkTop := stkTop:sub(#1).
              vmPos:equals(saved):ifElse({ pc := target }, { pc := ins:target }) }, {

          op:equals('any):ifElse({
              vmPos:lessOrEqual(sSrc:size):ifElse(
                  { vmPos := vmPos:add(#1). pc := pc:add(#1) },
                  { failing := true }) }, {

          ; The two token terminals are last because they run once per token of
          ; the subject, where the eight above run once per character of it.
          op:equals('matchText):ifElse({
              t := tokAt:value(vmPos).
              t:notNil:and({ sameText:value(t:text, ins:text) }):ifElse(
                  { vmPos := vmPos:add(#1). pc := pc:add(#1) },
                  { noteExpected:value("'":concat(ins:text):concat("'")).
                    failing := true }) }, {

          op:equals('matchKind):ifElse({
              t := tokAt:value(vmPos).
              t:notNil:and({ t:kind:equals(ins:text) })
                  :and({ isReservedAs:value(ins:text, t:text):not }):ifElse(
                  { vmPos := vmPos:add(#1). pc := pc:add(#1) },
                  { noteExpected:value(ins:text). failing := true }) }, {

          ; `! a` where `a` matched: throw away the choice point that would have
          ; let the character through, and fail.
          stkTop := stkTop:sub(#1). failing := true })
          }) }) }) }) }) }) }) }) }) }) }).
    answer }.

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
tokenise := { src | | out, bestLen, bestName, start |
    sSrc := src.
    out := array:new.
    vmPos := #1.
    { vmPos:lessOrEqual(src:size) }:whileTrue({
        start := vmPos.
        bestLen := #0. bestName := nil.
        gTokenOrder:do({ name |
            vmPos := start.
            runMachine:value(vmEntry:at(name), true, name):ifTrue({
                vmPos:sub(start):greaterThan(bestLen):ifTrue({
                    bestLen := vmPos:sub(start). bestName := name }) }) }).
        bestName:isNil:ifElse({
            lexErrors:add([start, src:at(start)]).
            vmPos := start:add(#1) },
        { vmPos := start:add(bestLen).
          gSkip:indexOf(bestName):isNil:ifTrue({
              out:add(makeToken:value(bestName,
                  src:copyFrom(start, vmPos:sub(#1)), start)) }) }) }).
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
tfar := #1.
tfarExpected := dictionary:new.
tfarRule := nil.

tokAt := { i | i:lessOrEqual(tks:size):ifElse({ tks:at(i) }, { nil }) }.

; **Which rule to name is not "the innermost one".** At the moment a terminal
; fails, the innermost rule in play is usually a leaf like
; `multiplying-operator`, entered at the failing token and describing the token
; that is missing rather than the thing being read. The useful answer is the
; innermost rule that has already *consumed* something -- it began before the
; trouble, so it is the construct the reader is in the middle of. That turns
; `reading <multiplying-operator>` into `reading <if-statement>`.
noteExpected := { what | | i |
    vmPos:greaterThan(tfar):ifTrue({
        tfar := vmPos.
        tfarExpected := dictionary:new.
        tfarRule := nil.

        ; **The rule context is read off the machine's stack**, which is the
        ; part of this the stack machine made simpler rather than harder. The
        ; recursive matcher carried two arrays of its own beside the frames it
        ; was already spending; here the `'ret` entries *are* the rules in play,
        ; each with the position it was entered at, and backtracking has already
        ; truncated them correctly.
        i := stkTop.
        { tfarRule:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
            stkKind:at(i):equals('ret):and({ stkPos:at(i):lessThan(tfar) })
                :ifTrue({ tfarRule := stkName:at(i) }).
            i := i:sub(#1) }).

        ; Nothing had consumed anything -- the file went wrong at its first
        ; token -- so name the innermost rule rather than none.
        tfarRule:isNil:ifTrue({
            i := stkTop.
            { tfarRule:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
                stkKind:at(i):equals('ret):ifTrue({ tfarRule := stkName:at(i) }).
                i := i:sub(#1) }) }) }).
    vmPos:equals(tfar):ifTrue({ tfarExpected:atPut(what, true) }).
    nil }.

; The matcher over tokens used to be here, one method recursing over the
; grammar tree. It is the machine above now -- see "The machine" and ROADMAP
; 3.5 for what that was costing and what it bought.

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
    bad:ifFalse({ compileGrammar:value. computeReserved:value. checkTokenUse:value }).

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

; **The one place `lineColumnIn` may not be used.** That block counts newlines
; from the start of the file, which is free when a run wants four of them and
; quadratic when it wants one per token. Measured on the largest file here,
; `programs/sola.sol` at 4,778 lines and 31,887 tokens: **seventeen and a half
; minutes to list the tokens of a file it checks in under four seconds.**
; 1,052s to 3.6s, which is 270 times, and the whole of it was arithmetic
; nobody asked for.
;
; Tokens arrive in order, so the line and the column can be *carried* -- one
; pass over the source for the whole dump rather than one pass per token. The
; design note above `lineColumnIn` is still right about errors and was wrong
; about this, which is the sort of thing only a large input says out loud.
dumpTokens := { path | | line, lineStart, at |
    line := #1. lineStart := #1. at := #1.
    tks:do({ t |
        { at:lessThan(t:pos) }:whileTrue({
            sSrc:at(at):equals("\n"):ifTrue({
                line := line:add(#1). lineStart := at:add(#1) }).
            at := at:add(#1) }).
        "{}:{}:{}: {} {}":fill([path, line, t:pos:sub(lineStart):add(#1),
            t:kind:asString("<12"),
            t:text:size:greaterThan(#30)
                :ifElse({ t:text:copyFrom(#1, #30):concat("...") }, { t:text })]):display }).
    "{}: {}":fill([path, plural:value(tks:size, "token")]):display.
    nil }.

matchSubject := { path, text | | ok, t, pos |
    vmPos := #1. tfar := #1. tfarExpected := dictionary:new. tfarRule := nil.
    ok := runMachine:value(vmEntry:at(gStart), false, gStart).

    ok:and({ vmPos:greaterThan(tks:size) }):ifElse({ nil }, {
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
                ; **This used to be about depth**, and said so: matching
                ; recursed, `call depth exceeded` arrived here, and saying so
                ; was the difference between a diagnostic and a crash. The
                ; machine has no depth to run out of, so what is left is a
                ; handler for anything else going wrong in a match -- which
                ; should be nothing, and is reported rather than assumed.
                { matchSubject:value(subjectPath, subjectText) }:onError({ e |
                    "{}: the match failed: {}"
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
; What the depth cost, and what removing it cost
;
; **There is no depth limit now, and this section is the history of the one
; there was**, because the numbers are the argument for the machine that
; replaced it.
;
; The matcher was a tree walk: one Solum frame per node of the grammar, against
; a machine with 254. Measured rather than guessed, and measured through real
; grammars rather than through the matcher:
;
;   pascal.bnf   19 levels of nested `begin ... if`, 28 nested parentheses
;   solum.bnf    13 nested blocks
;
; Descending one rule cost about two frames -- one for the reference, one for
; the sequence it chose -- and a language nests about four rules per level of
; its own syntax, which is where those numbers come from.
;
; Three things were worth writing down about that, and two of them survive the
; machine.
;
; **It was a diagnostic and not a crash.** `call depth exceeded` arrives at
; `onError` like any other failure -- which `evaluator.sol` established -- so a
; file too deep was reported as being too deep rather than killing the checker.
; That property is why the limit was liveable for as long as it was.
;
; **The frames were spent on the grammar, not on the file.** A ten-thousand-line
; program with ordinary nesting reached the same depth as a ten-line one. What
; cost depth was a construct inside a construct.
;
; **And a real file reached it.** `experiment/lexer.sol` holds a 24-level nested
; `ifElse` staircase -- the deepest expression in this repository, and exactly
; the shape [control.sol](../lib/control.sol) recommends. Every earlier
; measurement on [ROADMAP 3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels)
; needed a generator to reach the limit; that one was already sitting here. It
; is what settled the trade this file had recorded as unsettled.
;
; **What removing it cost is 38% of the running time**, and that is the honest
; headline. `programs/sola.sol` went from 3.79 seconds to 5.25. Two attempts to
; get it back are described in `runMachine` and are worth 3.7% between them --
; the loop's cost is the instruction fetch and the sends inside an arm, not the
; comparisons that choose the arm.
;
; **And 2,000 levels of nesting now check in both languages**, where 19 and 13
; were the numbers. What bounds depth is memory, which is the same thing as
; saying nothing a grammar or a file will reach.
;
; **What is left of the limit is in a better place.** `compileNode` still
; recurses over the grammar tree, so a *grammar* nesting brackets a few hundred
; deep runs out of frames. That is a property of the grammar file, reported the
; same way every time and before any subject is read -- not a property of the
; input, discovered on the one file that happened to be deep.
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
