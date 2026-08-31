; sed.sol -- the stream editor: a script of addressed commands, run over every
; line of the input.
;
; Run with:  ./bin/solas programs/sed.sol && ./bin/solvm programs/sed.sob
;
;     solvm sed.sob 's/foo/bar/g' file.txt
;     solvm sed.sob -n '/^ERROR/p' < log.txt
;     solvm sed.sob -e '2,5d' -e '$=' file.txt
;
; With no arguments it demonstrates itself on text it carries, which is the
; house rule for these programs.
;
; ---------------------------------------------------------------------------
; What is here
;
; The everyday half of POSIX sed, which is what nearly every invocation of it
; actually uses:
;
;   addresses   17   $   /re/   \,re,   17,25   /a/,/b/   and `!` for the rest
;   commands    s  p  d  q  =  y  a  i  c  { }
;   flags       -n, -e script, -f file, and the files to read
;
; **What is not here** is the other half, and it is a coherent half rather than
; a list of leftovers: the hold space (`h H g G x`), branching (`b t :label`),
; the multi-line commands (`n N D P`), and reading and writing named files
; (`r w`). Those are what make sed a stream *language* rather than a filter --
; `1!G;h;$!d` reverses a file -- and they want a pattern space that is a
; two-line window and a program counter that can jump. This has neither, and
; adding them changes the runner rather than anything below it.
;
; **The regular expressions are [pattern.sol](../lib/pattern.sol)'s**, which is
; the subset vi searches with: `. * [ ] ^ $ \` and nothing else. No groups, no
; backreferences, no `+` or `?`. A sed script written for GNU sed and using
; `\(...\)` will be refused rather than misread, because `\(` is a literal
; parenthesis here and would silently match the wrong thing.
;
; ---------------------------------------------------------------------------
; Why write this one
;
; The sixteenth program here, and the third to be held against an independent
; implementation of its own job -- after [sola](sola.sol), which wants
; QuickBASIC, and [pascal](pascal.sol), which wants `fpc`. It is the first whose
; oracle needed nothing installed: `sed` is on the machine already, and
; [sed/oracle.sh](sed/oracle.sh) is what that buys.
;
; Because the interesting half was already here and this is the way to find out
; what it is missing. `pattern.sol` has the matcher and the substituter, and
; `scan.sol` has the cursor a script parser wants; what sed adds is the
; *cycle* -- read a line, run every command against it, print it unless told
; not to -- and the addressing that decides which lines a command sees.
;
; A program is the only thing here allowed to say the library is short of
; something. What this one asked for is at the bottom of the file, after the
; code, because a finding written before the code is a prediction.

@include "pattern.sol".
@include "text.sol".

; ---------------------------------------------------------------------------
; An address
;
; Three kinds and no more: a line number, the last line, or a pattern. The
; second is why the reader below has a line of lookahead -- `$` is a question
; about what comes *after* the line being worked on, and nothing else in the
; program needs to know that.

address := object:new.
address:kind := 'line.              ; 'line, 'last or 'regexp
address:line := #0.
address:pattern := nil.

; ---------------------------------------------------------------------------
; A command
;
; One prototype with a kind rather than one prototype per command, following
; `pattern:item`: every command has an address, a negation and a body of some
; sort, and the differences between them are three slots wide.
;
; `active` is the one piece of *state* a compiled script holds. A range address
; is not a predicate over one line -- `/start/,/end/` is a machine with two
; states, and the machine belongs to the command rather than to the run, since
; two commands with the same range are independently in or out of it.

command := object:new.
command:kind := 'noop.
command:addr1 := nil.
command:addr2 := nil.
command:negated := false.
command:active := false.            ; a two-address range is open

command:pattern := nil.             ; s: what to find
command:replacement := "".          ; s: what to put there
command:global := false.            ; s: the `g` flag
command:occurrence := #1.           ; s: the `N` flag
command:showIt := false.            ; s: the `p` flag

command:from := "".                 ; y: the characters to map
command:to := "".                   ; y: what to map them to

command:text := "".                 ; a, i, c: the text
command:body := nil.                ; { }: the commands inside

; ---------------------------------------------------------------------------
; Reading a script
;
; A cursor over the script text, and the grammar taken one command at a time.
; The parser is an object rather than a set of blocks so that `{ }` can recurse
; through `self` -- a block that called itself by its global name would work
; too, and this reads as what it is.

parser := object:new.

parser:isDigit := { c |
    c:notNil:and({ c:greaterOrEqual("0"):and({ c:lessOrEqual("9") }) }) }.

parser:blanks := { s |
    s:skipWhile({ c | c:equals(" "):or({ c:equals("\t") }) }) }.

; Between commands: whitespace, `;`, newlines, and a comment running to the end
; of its line. `}` is not skipped -- it closes a block and the caller is the one
; that wants to see it.
parser:separators := { s | | going |
    going := true.
    { going }:whileTrue({
        self:blanks(s).
        s:looksLike(";"):or({ s:looksLike("\n") })
            :ifElse({ s:step },
                    { s:looksLike("#"):ifElse(
                        { s:skipWhile({ c | c:equals("\n"):not }) },
                        { going := false }) }) }) }.

; The text between two delimiters, with the backslash escapes left exactly as
; they were written.
;
; **They are left alone on purpose.** `pattern:on` reads `\x` as *the character
; x, literally*, and so does its replacement side, so `s|a\|b|X|` and
; `s/a\/b/X/` both arrive at the matcher spelling the delimiter as an ordinary
; character without this file having to know which delimiter was chosen. Undoing
; the escape here and re-escaping it there would be two chances to get one thing
; wrong.
parser:delimited := { s, delim, what | | out, c, done |
    out := "".
    done := false.
    { done:not }:whileTrue({
        s:atEnd:ifTrue({ error:raise("unterminated {}":fill([what])) }).
        c := s:next.
        c:equals("\\"):ifElse(
            { s:atEnd:ifTrue({ error:raise("unterminated {}":fill([what])) }).
              out := out:concat(c):concat(s:next) },
            { c:equals(delim):ifElse({ done := true },
                                     { out := out:concat(c) }) }) }).
    out }.

; The same span with the escapes resolved, which is what `y` wants: it maps
; characters and has no matcher behind it to do the reading.
parser:literal := { s, delim, what | | out, c, done, e |
    out := "".
    done := false.
    { done:not }:whileTrue({
        s:atEnd:ifTrue({ error:raise("unterminated {}":fill([what])) }).
        c := s:next.
        c:equals("\\"):ifElse(
            { s:atEnd:ifTrue({ error:raise("unterminated {}":fill([what])) }).
              e := s:next.
              e:equals("n"):ifTrue({ e := "\n" }).
              e:equals("t"):ifTrue({ e := "\t" }).
              out := out:concat(e) },
            { c:equals(delim):ifElse({ done := true },
                                     { out := out:concat(c) }) }) }).
    out }.

; A regular expression, refusing the empty one by name.
;
; `//` in sed means *the expression the last one used*, which is a piece of
; state shared between every address and every `s` in a script. It is not here,
; and an empty pattern would otherwise compile to one that matches everywhere --
; the difference between a script that does nothing and a script that does
; everything, decided silently.
parser:expression := { s, delim, what | | source |
    source := self:delimited(s, delim, what).
    source:size:equals(#0):ifTrue({
        error:raise("an empty regular expression means the last one used, "
                        :concat("and this sed has no memory of it")) }).
    pattern:on(source) }.

parser:address := { s | | a, delim |
    a := nil.

    s:looksLike("$"):ifTrue({
        s:step.
        a := address:new.
        a:kind := 'last }).

    a:isNil:and({ self:isDigit(s:peek) }):ifTrue({
        a := address:new.
        a:kind := 'line.
        a:line := s:takeWhile({ c | self:isDigit(c) }):asInteger }).

    a:isNil:and({ s:looksLike("/") }):ifTrue({
        s:step.
        a := address:new.
        a:kind := 'regexp.
        a:pattern := self:expression(s, "/", "address") }).

    ; `\,text,` -- any delimiter, for an expression full of slashes.
    a:isNil:and({ s:looksLike("\\") }):ifTrue({
        s:step.
        delim := s:next.
        delim:isNil:ifTrue({ error:raise("expected a delimiter after `\\`") }).
        a := address:new.
        a:kind := 'regexp.
        a:pattern := self:expression(s, delim, "address") }).

    a }.

; The text of `a`, `i` and `c`.
;
; Two spellings are taken. POSIX writes the command, a backslash, a newline, and
; the text on the lines that follow, each continued with a trailing backslash;
; everything since has also taken the text on the same line, which is what
; anybody writing at a shell prompt does. The one-liner is the common case and
; refusing it would make this a different program from the one people know.
;
; Either way the text runs to the end of its line and `;` does not end it, which
; is sed's rule and the reason `a hello; p` appends `hello; p`.
parser:appendText := { s | | out, c, done |
    self:blanks(s).
    s:looksLike("\\"):and({ s:peekAt(#1):equals("\n") }):ifTrue({
        s:step. s:step }).

    out := "".
    done := false.
    { done:not }:whileTrue({
        s:atEnd:ifElse(
            { done := true },
            { c := s:next.
              c:equals("\\"):ifElse(
                  ; A backslash at the end of a line carries the text onto the
                  ; next one, newline and all; anywhere else it is the character
                  ; after it.
                  { s:atEnd:ifElse({ done := true },
                                   { out := out:concat(s:next) }) },
                  { c:equals("\n"):ifElse({ done := true },
                                          { out := out:concat(c) }) }) }) }).
    out }.

parser:substitution := { s, c | | delim, flags, done, f |
    delim := s:next.
    delim:isNil:or({ delim:equals("\n"):or({ delim:equals("\\") }) }):ifTrue({
        error:raise("`s` wants a delimiter") }).

    c:kind := 'subst.
    c:pattern := self:expression(s, delim, "`s`").
    c:replacement := self:delimited(s, delim, "`s`").

    done := false.
    { done:not }:whileTrue({
        f := s:peek.
        f:isNil:ifElse({ done := true }, {
            f:equals("g"):ifElse({ c:global := true. s:step }, {
            f:equals("p"):ifElse({ c:showIt := true. s:step }, {
            self:isDigit(f):ifElse(
                { c:occurrence := s:takeWhile({ d | self:isDigit(d) }):asInteger.
                  c:occurrence:equals(#0):ifTrue({
                      error:raise("`s` counts occurrences from 1") }) },
                { done := true }) }) }) }) }).
    c }.

parser:transliteration := { s, c | | delim |
    delim := s:next.
    delim:isNil:ifTrue({ error:raise("`y` wants a delimiter") }).
    c:kind := 'transliterate.
    c:from := self:literal(s, delim, "`y`").
    c:to := self:literal(s, delim, "`y`").
    c:from:size:equals(c:to:size):ifFalse({
        error:raise("`y` wants two lists of the same length, got {} and {}"
                        :fill([c:from:size, c:to:size])) }).
    c }.

; One command: its addresses, its negation, its letter, and whatever that letter
; takes after it.
parser:command := { s | | c, letter |
    c := command:new.

    c:addr1 := self:address(s).
    c:addr1:notNil:ifTrue({
        self:blanks(s).
        s:match(","):ifTrue({
            self:blanks(s).
            c:addr2 := self:address(s).
            c:addr2:isNil:ifTrue({
                error:raise("expected a second address after `,`") }) }) }).

    self:blanks(s).
    { s:match("!") }:whileTrue({ c:negated := true. self:blanks(s) }).

    letter := s:next.
    letter:isNil:ifTrue({ error:raise("expected a command") }).

    letter:equals("{"):ifTrue({
        c:kind := 'block.
        c:body := self:commands(s, true) }).

    letter:equals("s"):ifTrue({ self:substitution(s, c) }).
    letter:equals("y"):ifTrue({ self:transliteration(s, c) }).

    letter:equals("p"):ifTrue({ c:kind := 'print }).
    letter:equals("d"):ifTrue({ c:kind := 'delete }).
    letter:equals("q"):ifTrue({ c:kind := 'quit }).
    letter:equals("="):ifTrue({ c:kind := 'lineNumber }).

    letter:equals("a"):ifTrue({ c:kind := 'append. c:text := self:appendText(s) }).
    letter:equals("i"):ifTrue({ c:kind := 'insert. c:text := self:appendText(s) }).
    letter:equals("c"):ifTrue({ c:kind := 'change. c:text := self:appendText(s) }).

    c:kind:equals('noop):ifTrue({
        error:raise("unknown command `{}`":fill([letter])) }).

    ; The commands that take nothing must be followed by the end of one, so that
    ; `pq` is a mistake rather than a `p` and a stray letter nobody reads.
    ['print, 'delete, 'quit, 'lineNumber]:indexOf(c:kind):notNil:ifTrue({
        self:blanks(s).
        s:atEnd:or({ s:looksLike(";"):or({ s:looksLike("\n")
            :or({ s:looksLike("}"):or({ s:looksLike("#") }) }) }) }):ifFalse({
            error:raise("`{}` takes nothing after it, and `{}` follows it"
                            :fill([letter, s:peek])) }) }).
    c }.

parser:commands := { s, inBlock | | out, done |
    out := array:new.
    done := false.
    { done:not }:whileTrue({
        self:separators(s).
        s:atEnd:ifElse(
            { inBlock:ifTrue({ error:raise("a `{` was never closed") }).
              done := true },
            { s:looksLike("}"):ifElse(
                { inBlock:ifElse({ s:step. done := true },
                                 { error:raise("a `}` closes nothing") }) },
                { out:add(self:command(s)) }) }) }).
    out }.

; The whole script. `#n` on the first line is sed's own way of saying -n, and is
; the one place a comment means something.
parser:on := { script | | s |
    s := scan:on(script).
    s:looksLike("#n"):and({ s:peekAt(#2):isNil:or({ s:peekAt(#2):equals("\n") }) })
        :ifTrue({ s:step. s:step. runner:quiet := true }).
    self:commands(s, false) }.

; ---------------------------------------------------------------------------
; Reading the input
;
; One line at a time, from the files named or from standard input, with a line
; of lookahead so that `$` can be answered.
;
; **A named file is read whole and split**, and that is not what a stream editor
; should do -- see the note at the bottom of this file. `system:readLine` reads
; standard input a line at a time and there is no equivalent for a file, so the
; two routes into this program are different shapes underneath, and the reader
; is where the difference is kept.

reader := object:new.
reader:files := nil.
reader:fileIndex := #0.
reader:lines := nil.
reader:lineIndex := #1.
reader:buffer := nil.
reader:buffered := false.
reader:exhausted := false.
reader:terminated := true.          ; did the input's last line end with a newline
reader:fromStdin := false.

reader:onFiles := { paths |
    self:files := paths.
    self:lines := array:new.
    self:fromStdin := paths:size:equals(#0).
    self }.

; The demonstration reads a string, and so could a test.
reader:onText := { text |
    self:files := array:new.
    self:fromStdin := false.
    self:lines := self:linesOf(text).
    self }.

; "a\nb\n" is two lines; "a\nb" is two lines and a missing terminator; "" is no
; lines at all, which `split` cannot say on its own because it answers `[""]`.
reader:linesOf := { text | | parts |
    text:size:equals(#0):ifElse(
        { array:new },
        { parts := text:split("\n").
          parts:at(parts:size):equals("")
              :ifElse({ parts:copyFrom(#1, parts:size:sub(#1)) },
                      { self:terminated := false. parts }) }) }.

reader:openNext := {
    self:fileIndex := self:fileIndex:add(#1).
    self:terminated := true.
    self:lines := self:linesOf(system:readFile(self:files:at(self:fileIndex))).
    self:lineIndex := #1 }.

reader:fetch := {
    self:fromStdin:ifElse({ system:readLine }, { self:fromLines }) }.

reader:fromLines := { | line, done |
    line := nil.
    done := false.
    { done:not }:whileTrue({
        self:lineIndex:lessOrEqual(self:lines:size):ifElse(
            { line := self:lines:at(self:lineIndex).
              self:lineIndex := self:lineIndex:add(#1).
              done := true },
            { self:fileIndex:lessThan(self:files:size)
                :ifElse({ self:openNext }, { done := true }) }) }).
    line }.

; A line ending `\r\n` arrives from `readLine` without the carriage return and
; from `split` with it, so the file route takes it off too. The alternative is
; one program answering two ways about the same bytes depending on whether it
; was handed a name or a pipe.
reader:fill := { | line |
    self:buffered:or({ self:exhausted }):ifFalse({
        line := self:fetch.
        line:isNil:ifElse(
            { self:exhausted := true },
            { line:endsWith("\r"):ifTrue({
                  line := line:copyFrom(#1, line:size:sub(#1)) }).
              self:buffer := line.
              self:buffered := true }) }) }.

reader:hasNext := { self:fill. self:buffered }.

reader:next := { | line |
    self:fill.
    line := self:buffer.
    self:buffered := false.
    line }.

; Asked after a line has been taken: is there another behind it.
reader:onLastLine := { self:fill. self:buffered:not }.

; ---------------------------------------------------------------------------
; Writing the output
;
; One line of lag, and the reason is the last one.
;
; A file whose final line carries no newline is copied by sed without gaining
; one, and there is no way to know a line is the last thing this program will
; write until the next thing is asked for. So a line is held, written when the
; one after it arrives, and the terminator on the held one is decided at the
; end.

out := object:new.
out:pending := nil.
out:terminated := true.

out:emit := { text |
    self:pending:isNil:ifFalse({
        system:write(self:pending). system:write("\n") }).
    self:pending := text }.

out:flush := {
    self:pending:isNil:ifFalse({
        system:write(self:pending).
        self:terminated:ifTrue({ system:write("\n") }).
        self:pending := nil }) }.

; ---------------------------------------------------------------------------
; The cycle
;
; Read a line into the pattern space, run the script over it, print it unless
; `-n` said not to or a command threw it away, then do it again.

runner := object:new.
runner:quiet := false.
runner:space := "".
runner:lineNumber := #0.
runner:appends := nil.
runner:stopped := false.

runner:matchesAddress := { a |
    a:kind:equals('line):ifElse(
        { self:lineNumber:equals(a:line) },
        { a:kind:equals('last):ifElse(
            { reader:onLastLine },
            { a:pattern:matches(self:space) }) }) }.

; A range is a two-state machine, and the states differ in which address is
; being watched.
;
; **The second address is looked at from the line after the first matched**,
; which is why `/a/,/a/` spans from one `a` to the *next* one rather than
; ending on the line it started. A numeric second address is the exception: it
; names a line rather than a thing to look for, so a number already passed
; closes the range at once and `4,2p` prints line 4 alone.
runner:inRange := { c |
    c:active:ifElse(
        { c:addr2:kind:equals('line):ifElse(
            { self:lineNumber:greaterOrEqual(c:addr2:line):ifTrue({
                  c:active := false }) },
            { self:matchesAddress(c:addr2):ifTrue({ c:active := false }) }).
          true },
        { self:matchesAddress(c:addr1):ifElse(
            { c:addr2:kind:equals('line):ifElse(
                { c:active := c:addr2:line:greaterThan(self:lineNumber) },
                { c:active := true }).
              true },
            { false }) }) }.

runner:selects := { c | | yes |
    yes := c:addr2:notNil:ifElse(
        { self:inRange(c) },
        { c:addr1:isNil:ifElse({ true }, { self:matchesAddress(c:addr1) }) }).
    c:negated:ifElse({ yes:not }, { yes }) }.

; ---------------------------------------------------------------------------
; Substituting
;
; `pattern:substitutionIn` does the whole job when the script asks for the first
; match or for all of them, which is what `s/x/y/` and `s/x/y/g` are. A number
; asks for something its boolean cannot say -- the third match and no other --
; and the way round it is here rather than in the library: find where the Nth
; match begins, then let the library substitute in what is left of the line.
;
; **That is only correct because a pattern that can look leftwards can match
; only once.** `^` is the sole thing in this expression language that cares what
; precedes a match, and a pattern carrying it is anchored, so it has no second
; occurrence for a number to name. Handing the library a tail of the line is
; therefore handing it the same question about the same characters. A language
; with `\<` or a lookbehind would break this, and would be the moment to move it.
runner:substitute := { c | | at, seen, start, stop, head, result |
    c:occurrence:equals(#1):ifElse(
        { result := c:pattern:substitutionIn(
                        self:space, c:replacement, c:global) },
        { at := #1.
          seen := #0.
          start := nil.
          { seen:lessThan(c:occurrence):and({ at:lessOrEqual(self:space:size:add(#1)) }) }
              :whileTrue({
                  start := c:pattern:findFrom(self:space, at).
                  start:isNil:ifElse(
                      { at := self:space:size:add(#2). seen := c:occurrence },
                      { seen := seen:add(#1).
                        stop := c:pattern:endOfMatchAt(self:space, start).
                        at := stop:equals(start):ifElse(
                                  { start:add(#1) }, { stop }) }) }).
          start:isNil:ifElse(
              { result := dictionary:new.
                result:atPut("text", self:space).
                result:atPut("count", #0) },
              { head := start:equals(#1):ifElse(
                            { "" }, { self:space:copyFrom(#1, start:sub(#1)) }).
                result := c:pattern:substitutionIn(
                              self:space:copyFrom(start, self:space:size),
                              c:replacement, c:global).
                result:atPut("text", head:concat(result:at("text"))) }) }).

    result:at("count"):greaterThan(#0):ifTrue({
        self:space := result:at("text").
        c:showIt:ifTrue({ out:emit(self:space) }) }) }.

runner:transliterate := { c | | built, i, ch, where |
    built := "".
    i := #1.
    { i:lessOrEqual(self:space:size) }:whileTrue({
        ch := self:space:at(i).
        where := c:from:indexOf(ch).
        built := built:concat(where:isNil:ifElse({ ch }, { c:to:at(where) })).
        i := i:add(#1) }).
    self:space := built }.

; One command against the line in hand. Answers what should happen next:
; 'normal to carry on, 'deleted to end the cycle without printing, 'quit to end
; the run after printing.
runner:apply := { c | | verdict |
    verdict := 'normal.
    self:selects(c):ifTrue({

        c:kind:equals('block):ifTrue({ verdict := self:execute(c:body) }).
        c:kind:equals('subst):ifTrue({ self:substitute(c) }).
        c:kind:equals('transliterate):ifTrue({ self:transliterate(c) }).
        c:kind:equals('print):ifTrue({ out:emit(self:space) }).
        c:kind:equals('lineNumber):ifTrue({
            out:emit(self:lineNumber:asString) }).
        c:kind:equals('insert):ifTrue({ out:emit(c:text) }).
        c:kind:equals('append):ifTrue({ self:appends:add(c:text) }).
        c:kind:equals('delete):ifTrue({ verdict := 'deleted }).
        c:kind:equals('quit):ifTrue({ verdict := 'quit }).

        ; `c` over a range replaces the whole range with one copy of the text,
        ; so the text is written when the range closes and every line in it is
        ; thrown away. `selects` has just run the machine, so a range that is no
        ; longer active is one that ended on this line.
        c:kind:equals('change):ifTrue({
            c:addr2:isNil:or({ c:active:not }):ifTrue({ out:emit(c:text) }).
            verdict := 'deleted }) }).
    verdict }.

runner:execute := { commands | | verdict, i |
    verdict := 'normal.
    i := #1.
    { verdict:equals('normal):and({ i:lessOrEqual(commands:size) }) }:whileTrue({
        verdict := self:apply(commands:at(i)).
        i := i:add(#1) }).
    verdict }.

runner:go := { commands | | verdict |
    self:appends := array:new.
    { self:stopped:not:and({ reader:hasNext }) }:whileTrue({
        self:space := reader:next.
        self:lineNumber := self:lineNumber:add(#1).
        reader:onLastLine:ifTrue({ out:terminated := reader:terminated }).

        verdict := self:execute(commands).

        verdict:equals('deleted):ifFalse({
            self:quiet:ifFalse({ out:emit(self:space) }) }).

        ; What `a` queued goes out after the line it was queued on, printed or
        ; not: appended text is not the pattern space and `-n` does not silence
        ; it.
        self:appends:size:greaterThan(#0):ifTrue({
            self:appends:do({ t | out:emit(t) }).
            self:appends := array:new }).

        verdict:equals('quit):ifTrue({ self:stopped := true }) }).
    out:flush }.

; Each of the three objects above holds the state of one run, so a program that
; runs a script twice -- the demonstration below does -- puts them back first.
; A compiled script holds state too, in the `active` slot of every range, and
; that is why the demonstration compiles each script rather than reusing one.

reader:reset := {
    self:fileIndex := #0.
    self:lines := array:new.
    self:lineIndex := #1.
    self:buffer := nil.
    self:buffered := false.
    self:exhausted := false.
    self:terminated := true.
    self }.

out:reset := { self:pending := nil. self:terminated := true. self }.

runner:reset := {
    self:quiet := false.
    self:space := "".
    self:lineNumber := #0.
    self:appends := array:new.
    self:stopped := false.
    self }.

; ---------------------------------------------------------------------------
; The command line
;
;     sed [-n] script [file...]
;     sed [-n] [-e script]... [-f scriptfile]... [file...]
;
; Clustered flags are taken -- `-ne` is the way this gets typed -- and a flag
; that takes an argument may carry it in the same word or in the next one, which
; is what every tool a reader has used does.

options := object:new.
options:quiet := false.
options:pieces := nil.              ; the script, in the order the flags gave it
options:files := nil.
options:sawScript := false.

options:read := { args | | i, a, j, c, done |
    self:pieces := array:new.
    self:files := array:new.
    i := #1.

    { i:lessOrEqual(args:size) }:whileTrue({
        a := args:at(i).

        a:equals("--"):ifElse(
            { i := i:add(#1).
              { i:lessOrEqual(args:size) }:whileTrue({
                  self:files:add(args:at(i)). i := i:add(#1) }) },

            { a:size:greaterThan(#1):and({ a:startsWith("-") }):ifElse(
                { j := #2.
                  done := false.
                  { done:not:and({ j:lessOrEqual(a:size) }) }:whileTrue({
                      c := a:at(j).
                      c:equals("n"):ifTrue({ self:quiet := true. j := j:add(#1) }).
                      c:equals("e"):or({ c:equals("f") }):ifTrue({ | value |
                          ; The rest of this word, or the whole of the next one.
                          j:lessThan(a:size):ifElse(
                              { value := a:copyFrom(j:add(#1), a:size) },
                              { i := i:add(#1).
                                i:greaterThan(args:size):ifTrue({
                                    error:raise("-{} wants something after it"
                                                    :fill([c])) }).
                                value := args:at(i) }).
                          c:equals("e"):ifElse(
                              { self:pieces:add(value) },
                              { system:fileExists(value):ifFalse({
                                    error:raise("no script file `{}`"
                                                    :fill([value])) }).
                                self:pieces:add(system:readFile(value)) }).
                          self:sawScript := true.
                          done := true }).
                      c:equals("n"):or({ c:equals("e"):or({ c:equals("f") }) })
                          :ifFalse({
                              error:raise("unknown option `-{}`":fill([c])) }) }).
                  i := i:add(#1) },

                { ; An operand. The first is the script when no -e or -f gave one.
                  self:sawScript:ifElse(
                      { self:files:add(a) },
                      { self:pieces:add(a). self:sawScript := true }).
                  i := i:add(#1) }) }) }).

    self:sawScript:ifFalse({ error:raise("no script") }).
    self:files:do({ f |
        system:fileExists(f):ifFalse({
            error:raise("cannot read `{}`":fill([f])) }) }).
    self }.

; ---------------------------------------------------------------------------
; What it does with no arguments
;
; Every program here runs on input it carries, because one that has to be fed
; before it will say anything is one nobody runs twice.

sample := "alice   42  ok\nbob     17  warn\ncarol   93  ok\ndave     5  error\nerin    68  warn\n".

demo := { title, flags, script | | commands |
    "":display.
    "  {}":fill([title]):display.
    "  $ sed {}'{}'":fill([flags, script:replace("\n", "; ")]):display.
    "":display.

    runner:reset.
    out:reset.
    reader:reset.
    runner:quiet := flags:indexOf("-n"):notNil.
    commands := parser:on(script).
    reader:onText(sample).
    runner:go(commands) }.

demonstrate := {
    "":display.
    "sed -- the everyday half of the stream editor.":display.
    "":display.
    "The input, which this program carries:":display.
    "":display.
    system:write(sample).

    demo:value("Substitute, every time it appears on a line.",
               "", "s/o/0/g").
    demo:value("Print only what matches, which is grep with a script.",
               "-n ", "/warn/p").
    demo:value("Delete a range of lines by number.",
               "", "2,4d").
    demo:value("Number the lines a pattern picks out.",
               "-n ", "/ok/{=;p}").
    demo:value("Everything from the first warning to the first error.",
               "-n ", "/warn/,/error/p").
    demo:value("Insert, append, and replace a whole range.",
               "", "1i\\-- report --\n$a\\-- ends --\n/warn/c\\(withheld)").
    demo:value("Transliterate, and stop after the third line.",
               "", "y/abcde/ABCDE/\n3q").

    "":display.
    "Give it a script and it reads the files named, or standard input:":display.
    "":display.
    "  solvm sed.sob -n '/^ERROR/p' log.txt":display.
    "  ... | solvm sed.sob 's/  */ /g'":display.
    "":display }.

; ---------------------------------------------------------------------------
; Running

{ system:arguments:size:equals(#0):ifElse(
    { demonstrate:value },
    { | commands |
      options:read(system:arguments).
      runner:reset.
      out:reset.
      reader:reset.
      runner:quiet := options:quiet.
      commands := parser:on(options:pieces:join("\n")).
      reader:onFiles(options:files).
      runner:go(commands) }) }
    :onError({ e |
        out:flush.
        system:writeError("sed: ":concat(e:message):concat("\n")).
        system:exit(#1) }).

; ---------------------------------------------------------------------------
; What this program asked for
;
; Written after the code and after the oracle, because a finding written before
; either is a prediction. Everything below was run.
;
; A defect in pattern.sol, found on the first run of the oracle
;
; **`s/o*/-/g` was wrong wherever the star actually matched something**, and it
; was wrong in the library rather than here. Reproduced without this program in
; the picture, which is how it was established as the library's:
;
;     pattern:on("o*"):replaceAllIn("aoc", "-")     ; "-a--c-", and sed says "-a-c-"
;     pattern:on("o*"):replaceAllIn("oo",  "-")     ; "--",     and sed says "-"
;     pattern:on("b*"):replaceAllIn("abc", "-")     ; "-a--c-", and sed says "-a-c-"
;     pattern:on("o*"):countIn("aoc")               ; #4, and there are three
;
; **The rule that was missing**: an empty match at the position where the
; previous match ended is not a match -- it is the same position seen twice.
; `substitutionIn` had the neighbouring rule, that a zero-width match must not
; stand still or the loop never ends, and that one was right all along.
;
; **The library's own example is the single case that cannot show the
; difference.** `s/x*/-/g` over `abc` answers `-a-b-c-` under both readings,
; because the star never matches a character there and so no match has an end
; for a later empty one to land on. Telling them apart needs a pattern that
; matches something, which is what an oracle supplies and what a documented
; example written by the author of the code does not.
;
; Fixed in `substitutionIn` and again in `countIn`, which walks the text
; separately and on purpose. Four cases went into
; [examples/matching.sol](../examples/matching.sol) so `expect.sol` holds it,
; the editor's 181 scripted sessions still pass, and three cases in `agree/`
; keep it honest here.
;
; ---------------------------------------------------------------------------
; The Nth occurrence has no word in `substitutionIn`
;
; `s/x/y/`, `s/x/y/g` and `s/x/y/3` are one command with a count that can be
; *the first*, *all*, or *this one*. The library takes a boolean, which spells
; the first two and cannot spell the third -- it is the two ends of a range with
; a middle.
;
; `runner:substitute` above works round it by finding where the Nth match begins
; and handing the library the rest of the line, and the note there says why that
; is exact rather than nearly so. **The workaround is sound and the shape is
; still worth reporting**, because the next caller will write the same loop.
;
; **The export boundary is what decided how.** `pattern:replacementFor` -- the
; piece that expands `&` and the backslashes -- is not exported, so the tail of
; the line had to go back through `substitutionIn` rather than be walked here.
; That is the boundary doing its job: the workaround that stayed inside it is
; twenty lines and reuses the library's replacement rules, and the one that
; wanted its own copy of `&` was never written.
;
; ---------------------------------------------------------------------------
; A file cannot be read a line at a time, and this is what it costs
;
; [3.22](../docs/COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done) says a file
; is read whole or not at all, that the peak cost is twice the file, and that
; the trigger for changing it is *a program with a file that does not fit*.
;
; **This program is the first one here that can price the entry**, because it
; does the same work by both routes: `system:readLine` streams standard input a
; line at a time, and a named file is read whole and split. Same script, same
; bytes, `-n '$p'`, peak resident:
;
; | input | lines | named file | standard input |
; | --- | --- | --- | --- |
; | 618 KB | 20,000 | 5.3 MB | 2.5 MB |
; | 6.4 MB | 200,000 | 32.3 MB | 2.5 MB |
;
; **The stream is flat and the file is not**, and the slope is about 4.7 times
; the file rather than the twice the entry states. Twice is right for
; `readFile` alone; a program that works line by line then splits, and holds a
; string object per line, and the entry does not cover that shape. A tenfold
; file costs tenfold memory on one route and nothing on the other.
;
; **The trigger still has not fired.** Nothing here has a file that does not
; fit, this one read 6.4 MB without complaint, and a stream editor that reads
; its input whole is embarrassing rather than broken. What the measurement
; changes is the *price* in the entry, not whether it has been paid.
;
; ---------------------------------------------------------------------------
; `readLine` loses one bit, and it is the one a stream editor needs
;
; A file whose last line carries no newline must not gain one, and every sed
; gets that right. This one gets it right for a named file and cannot for a
; pipe: `system:readLine` answers the line without its terminator and there is
; no way to ask whether there was one. The last line of a file and the last line
; of a pipe are the same bytes and this program answers differently about them.
;
; That is why the oracle runs every case both ways and why three of its cases
; carry a `pipediffers:` line saying the pipe's answer must be the file's plus
; exactly one newline -- a difference that is allowed, bounded, and checked.
;
; **And `\r\n` is the same boundary from the other side.** `readLine` takes the
; carriage return off and `split("\n")` leaves it on, so the two routes would
; have disagreed about every file written on Windows. `reader:fill` takes it off
; on the file route to match, which is a program choosing sides in something the
; language decided for it.
;
; ---------------------------------------------------------------------------
; Two limitations that were exactly as advertised
;
; **[3.2](../docs/ROADMAP.md#32-no-non-local-return)**, no non-local return. `d`
; and `q` are early exits from a list of commands, and `runner:execute` threads
; a verdict symbol through its loop instead. Three lines longer than a `return`
; and no harder to read -- the honest report is that this cost nothing.
;
; **[3.1](../docs/ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame)**,
; blocks that cannot outlive their frame, never came up. A compiled script here
; is *data* -- a command is slots, not a closure -- which is the shape
; `pattern:item` already had and the shape this file reached for without
; thinking about it. A sed built out of one block per command would have met 3.1
; on its first line.
;
; ---------------------------------------------------------------------------
; What it costs to run
;
; 20,000 lines and one substitution on each, `-O2`, against the system sed on
; the same file: **0.26 s against 0.01 s**. The default `CFLAGS` in the Makefile
; has no optimiser in it and that build takes 0.83 s, which is
; [performance.md](../docs/performance.md)'s standing warning arriving again.
;
; Twenty-six times a C program written in 1974 and tuned ever since, for 500
; lines of Solum written in an afternoon. That is the trade this language is
; for, and it is worth writing down rather than implying.
