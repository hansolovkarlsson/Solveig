; edit.sol -- a modal terminal editor, in the manner of vi.
;
; Run with:  ./bin/solas programs/edit.sol && ./bin/solvm programs/edit.sob
; Over a file of your own:  ./bin/solvm programs/edit.sob path/to/file
;
; The twelfth program here, and the first that **draws**. Every other one writes
; a line and reads a line; this one owns the screen, puts the cursor where it
; wants it, and redraws the whole of what you are looking at between one
; keystroke and the next.
;
;   h j k l, arrows   move           i a I A   insert here, or at the ends
;   w b               by word        o O       open a line below or above
;   0 $               line ends      x J       a character, join
;   gg G              file ends      d y       delete, yank -- over any motion
;   ctrl-f ctrl-b     by a screen    dd yy     the line, or the count of them
;   ma                mark here      p P       put it back, after or before
;   'a  `a            back to it     /pat ?pat search on, and back
;   ''                where you were n N       the same search again, either way
;   u  ctrl-r         undo, and back  .         do that last change again
;
;   3j   d2w   2dd   10G   3p   3.   a count repeats it, or reaches that far
;   :s/a/b/   :s/a/b/g   :%s/a/b/g   :w :q :q! :wq :w name :17
;
; ---------------------------------------------------------------------------
; What it was written to find, which was written down before it was written
;
; docs/ideas.md predicted, before this file existed, that an editor would want
; **the size of the terminal** and find nothing to ask -- the one prediction on
; that list made about an absence already confirmed rather than guessed at. It
; is what happened, in the first hour, and it is why `system:terminalSize`
; exists (ROADMAP 6.34, closed the day it was raised).
;
; **The absence was never the interesting part; the price of the workaround
; was.** The number was always reachable, because `stty` prints it:
;
;   stty size through /bin/sh            7.0  ms an ask
;   stty size with no shell              2.3  ms an ask
;   the ioctl behind terminalSize        0.001 ms an ask
;
; 7ms is a fork, an exec and a pipe **per keystroke** for a program that
; measures every time it draws -- so this program measured once at startup
; instead, and a window resized after that was a window it drew wrong until it
; was restarted. Nothing tells a program the size changed: there is no signal
; here and there is no message that waits for one. **The cheap ask is what makes
; the missing signal not matter.** `screen:measure` now runs once per frame, at
; the top of the loop at the bottom of this file, and a resize is wrong for one
; frame rather than until the editor is restarted.
;
; And the second-obvious answer is worse than the first: `tput lines` down a
; pipe answers the terminfo default rather than failing, confidently and wrongly.
; `COLUMNS` and `LINES` are shell locals and are not exported, so the
; environment cannot be asked either.
;
; ---------------------------------------------------------------------------
; What it confirmed, which had only ever been a warning
;
; **The escape key cannot be told from the start of an escape sequence** by a
; byte-level reader alone. examples/keys.sol said so and could only say it in
; the abstract: nothing had yet bound that key. A modal editor binds it to the
; most frequent action there is, and what it cost was this -- an arrow is
; `escape [ A`, three bytes, and `readKey` answers one, so an escape had to be
; followed by a read, and that read **blocked until the next key**. Press escape
; in insert mode and nothing happened; press the next key and both happened at
; once.
;
; **That is what `system:keyWaiting` is, and this program is why it exists**
; ([6.35](../docs/COMPLETED.md#635-a-read-that-gives-up--done)). *Is a byte
; coming within fifty milliseconds?* -- and nothing follows an escape that fast
; except a machine, so a false is a person pressing the key and the editor
; leaves insert mode there and then.
;
; `edit:pushed` is still what makes the other half right: a byte that turned out
; not to be part of a sequence is kept rather than thrown away. And **piped
; input has no timing in it** -- every byte is already there, so an escape is
; always read as the start of a sequence, which is exactly how this editor
; behaved before the message existed and is why its recorded transcript did not
; change by a byte when it landed.
;
; ---------------------------------------------------------------------------
; Three smaller findings, none of them worth an entry
;
; **An array cannot have an element put into the middle or taken out of it.**
; `add` appends and `removeLast` pops, and a line arriving in the middle of a
; file is neither. `insertLine` and `removeLine` below rebuild the array around
; the change -- one pass over the lines per line inserted, which for a file
; anybody edits by hand is nothing, and would not be for a program editing a
; million-line file without a person in front of it.
;
; **`system:write` flushes**, so one call is one frame. A redraw that arrived in
; pieces would be a redraw you can watch happening, and the whole screen is
; built as one string here for exactly that reason.
;
; **A tab is one byte and eight columns**, and everything that positions a
; cursor holds both numbers at once. Every editor ever written has this; it is
; where most of the arithmetic in this file went.
;
; ---------------------------------------------------------------------------
; Searching, which came a day later
;
; `/pattern`, `?pattern`, `n` and `N`, over the regular expressions in
; [lib/pattern.sol](../lib/pattern.sol) -- `.`, `*`, `[abc]`, `[^a-z]`, `^`, `$`
; and `\` to escape any of them. The library is the interesting half and says
; why it is shaped as it is; what the editor added to it was three things:
;
; **A file is not one string.** It is an array of lines and the cursor is a row
; and a column, so a search is a walk over lines rather than one call over the
; text -- and `^` and `$` mean the ends of a *line* without anybody deciding
; that they should. A matcher over the whole buffer would have had to be told.
;
; **Wrapping has to be said out loud.** A search that comes round to the line it
; started on looks exactly like a search that found something new, so both
; directions report the wrap.
;
; **A pattern that will not compile is a typing mistake, not a fault.** `/[ab`
; puts *a pattern has an unclosed '['* on the bottom line and leaves the cursor
; where it was; the alternative is an editor that dies of a missing bracket.
;
; ---------------------------------------------------------------------------
; And replacing, which is the other half of the same day
;
; `:s/find/replace/`, `/g` for every match on the line, `:%s` for every line in
; the file, and `&` in a replacement standing for what was matched. The
; delimiter is whatever character follows the `s`, so
; `:s#/usr/bin#/usr/local/bin#` needs no escaping.
;
; **It is not `/find/replace/`**, and it cannot be. `/src/lib` is a perfectly
; good search for a pattern with a slash in it, so a bare `/a/b/` would mean
; deciding that certain searches are silently substitutions instead. vi put
; substitution on the colon line for that reason, and so does this.
;
; **The report is counted, not compared.** *17 substitutions on 9 lines*, where
; the number of lines whose text ended up different would be a smaller number
; and a wrong one: replacing `a` with `a` changes nothing and is still a
; substitution, and that is exactly the case somebody checks by hand.
;
; **`:%s` is the first thing here that can change a hundred lines at once, and
; there is still no undo.** What it has instead is the count, and `:q!`.
;
; ---------------------------------------------------------------------------
; The grammar, which is the part worth reading
;
; **vi is not a table of keys, and an editor that implements it as one is a pile
; of special cases.** The notation is
;
;     [count] operator [count] motion
;
; where any of the three may be absent. With no operator the motion just moves;
; with no count it is once; and an operator standing where its own motion would
; go means whole lines, which is what `dd` and `yy` are. Everything else falls
; out: `dw`, `3dw`, `d3w`, `2d3w`, `d$`, `dj`, `dG`, `y'a`, `2yy`, `10G`, `3p`.
;
; So this file has **two dictionaries and one dispatcher**. A *motion* answers a
; place and moves nothing; an *action* does something. `edit:normalKey` decides
; which a key is, and whether an operator is waiting for a place to work over.
; Adding `e` or `f` later is one line in the motion table and no change anywhere
; else -- which is the test of whether the grammar was implemented or imitated.
;
; **The motions are the ones the cursor uses.** `dw` and `w` cannot disagree
; about where a word ends, because there is one `wordForward`: an operator runs
; it and puts the cursor back, which is what `placeAfter` is. That trick is why
; the table is short, and it is the reason the one bug this refactor produced was
; where it was -- see `clamp`, which had to learn that a *range end* may stand
; one past the last character of a line where a *cursor* may not.
;
; **A place carries how it should be read**: whole lines or a piece of text, and
; whether the character it lands on is inside the range. `dj` is two whole lines,
; `d$` includes the last character, `dw` does not include the first character of
; the next word. Those three sentences are the whole of why vi's deletions feel
; right, and every one of them is a boolean on `edit:place`.
;
; And one rule from the real thing, which is not decoration: **an exclusive
; motion that ends in the first column ends at the end of the line before it
; instead.** That is what makes `dw` on the last word of a line clear the tail of
; that line rather than dragging the next line up into it.
;
; ---------------------------------------------------------------------------
; What it does not do
;
; No `U` -- vi's *undo every change on this line*, which is a different
; mechanism and not a level of this one. No `c`, no `e f t`, and no named
; registers: one unnamed register is what `d`, `y` and `x` all write to and `p`
; reads. `J` joins without inserting a space, where vi inserts one and has
; exceptions about when. No line ranges beyond `%`;
; `:1,5s/a/b/` is a parser this has not got. Each of those is more of the same
; rather than more of the language, and this was written to ask the language a
; question rather than to replace anybody's editor. What is here is what it
; takes to open a file, move around it, change it and write it back -- which is
; enough to have edited this comment.
;
; It is held to a **recorded transcript** in tests/test_cli.c: a fixed screen
; size, a scripted stream of keystrokes, and the bytes it writes compared with
; the bytes it wrote when somebody last looked at them. `readKey` reading a pipe
; the same way it reads a terminal is what makes that possible at all.

@include "pattern.sol".

esc := #27:asCharacter.
csi := esc:concat("[").

; ---------------------------------------------------------------------------
; The screen
;
; **Asked again on every redraw**, which is the only reason a window can be
; resized under this editor and have it notice. Nothing tells a program the size
; changed -- there is no signal to hear and no message to ask for one -- so the
; alternative to asking every time is a size read once at startup and wrong from
; the first drag of a corner. It is affordable because `system:terminalSize` is
; one ioctl; when this program was written it did not exist and the only way to
; the number was `stty size` through a shell, at 7ms an ask, which is a fork per
; keystroke and was measured rather than guessed. That measurement is what got
; the message built; the measurement is at the top of this file.
;
; Nil means the output is not a terminal -- under a pipe, or a test harness --
; and then the size is 24 by 80, which is a decision this program is entitled to
; make and the language is not.

screen := object:new.
screen:rows := #24.
screen:columns := #80.

screen:measure := { | size |
    size := system:terminalSize.
    size:notNil:ifElse(
        { self:rows := size:at("rows"). self:columns := size:at("columns") },
        { self:rows := #24. self:columns := #80 }).
    ; A screen too small to hold the two bottom lines and one line of text is
    ; not drawn small, it is drawn wrong, so this refuses to believe in one.
    self:rows:lessThan(#4):ifTrue({ self:rows := #4 }).
    self:columns:lessThan(#20):ifTrue({ self:columns := #20 }) }.

; ---------------------------------------------------------------------------
; The buffer
;
; An array of lines, each a string without its newline, and never empty: an
; empty file is one empty line, because a cursor has to be somewhere.

edit := object:new.
edit:lines := nil.          ; the text, one string per line
edit:path := nil.           ; where it came from, and where `:w` writes it
edit:row := #1.             ; the cursor, as an index into `lines`
edit:column := #1.          ; and into the line, one past the end in insert
edit:top := #1.             ; the first line on the screen
edit:mode := 'normal.       ; 'normal, 'insert or 'command
edit:message := "".         ; the bottom line, when it is not a command
edit:dirty := false.        ; whether there is anything to lose
edit:running := true.
edit:count := #0.           ; the digits typed before a command; #0 is none
edit:measuring := false.    ; a motion is being run to find a place, not to move
edit:operator := nil.       ; "d" or "y", waiting for a motion to work over
edit:prefix := nil.         ; a key that needs a second one: m, ', ` or g
edit:register := nil.       ; what was last deleted or yanked
edit:registerIsLines := false.   ; whether that is whole lines or a piece of text
edit:marks := nil.          ; name -> [row, column]
edit:undone := nil.         ; states to go back to, oldest first
edit:redone := nil.         ; states undo took away, for ctrl-r
edit:group := false.        ; whether this change joins the one before it
edit:typing := nil.         ; the keys of the command being typed, for `.`
edit:lastChange := nil.     ; the keys of the last one that changed the text
edit:changedHere := false.  ; whether the command being typed has changed it
edit:replaying := false.    ; whether those keys are being fed back in
edit:undoLimit := #100.     ; how many changes are kept
edit:prompt := ":".         ; which bottom line is being typed: ':', '/' or '?'
edit:command := "".         ; that line, as it is typed
edit:pushed := nil.         ; one key read and not used -- see `nextKey`
edit:pattern := nil.        ; the last search, compiled
edit:patternSource := "".   ; and as it was typed, for the message
edit:direction := 'forward. ; which way `n` goes

edit:open := { path |
    self:path := path.
    self:marks := dictionary:new.
    self:undone := array:new.
    self:redone := array:new.
    self:group := false.
    self:typing := nil.
    self:lastChange := nil.
    self:lines := (path:notNil:and({ system:fileExists(path) })):ifElse(
        { self:linesOf(system:readFile(path)) },
        { [""] }).
    self:row := #1.
    self:column := #1 }.

; A file ending in a newline is not a file with an empty last line: the
; terminator ends the line before it. One that does not end in a newline has a
; last line all the same, and `:w` will give it the terminator it was missing --
; which is a change to the file and is the only one this editor makes without
; being asked.
edit:linesOf := { text | | out |
    out := text:split("\n").
    out:size:greaterThan(#1):and({ out:at(out:size):equals("") }):ifTrue({
        out := out:copyFrom(#1, out:size:sub(#1)) }).
    out:size:equals(#0):ifTrue({ out := [""] }).
    out }.

edit:text := { self:lines:join("\n"):concat("\n") }.

edit:line := { self:lines:at(self:row) }.
edit:setLine := { text | self:setLineAt(self:row, text) }.

; **Every change to the text goes through one of three methods** -- this one,
; `insertLine` and `removeLine` -- which is what makes undo possible without a
; call to `remember` at the top of every command that might change something.
; A command cannot forget to be undoable, because the forgetting would have to
; happen in the three places that do the changing.
edit:setLineAt := { row, text |
    self:remember.
    self:lines:atPut(row, text).
    self:dirty := true }.

; An array can be appended to and popped, and neither is what a line does when
; it arrives in the middle. Both of these rebuild the array around the point of
; the change -- one of the three smaller findings at the top of this file.
edit:insertLine := { at, text | | out |
    self:remember.
    out := self:lines:copyFrom(#1, at:sub(#1)).
    out:add(text).
    self:lines:copyFrom(at, self:lines:size):do({ each | out:add(each) }).
    self:lines := out.
    self:shiftMarks(at, #1).
    self:dirty := true }.

edit:removeLine := { at | | out |
    self:remember.
    self:lines:size:equals(#1):ifElse(
        ; The last line is emptied rather than removed, because a buffer with no
        ; lines has nowhere to put the cursor. Nothing moved, so no mark does.
        { self:lines:atPut(#1, "") },
        { out := self:lines:copyFrom(#1, at:sub(#1)).
          self:lines:copyFrom(at:add(#1), self:lines:size):do({ each |
              out:add(each) }).
          self:lines := out.
          self:shiftMarks(at, #-1) }).
    self:dirty := true }.

; ---------------------------------------------------------------------------
; Drawing
;
; The whole screen is built as one string and written once. Not for speed --
; twenty-four lines is nothing -- but because a redraw that arrives in pieces is
; a redraw you can watch happening, and `system:write` flushes, so one call is
; one frame. `display` would end every line and could not place a cursor.

edit:textRows := { screen:rows:sub(#2) }.

; A tab is one byte and eight columns, and the two have to be told apart:
; everything the cursor is measured in is screen columns, and everything the
; buffer holds is bytes.
edit:expand := { text | | out, c |
    out := "".
    [#1, text:size]:loop({ i |
        c := text:at(i).
        c:equals("\t"):ifElse(
            { { out := out:concat(" ") }
                :doUntil({ out:size:mod(#8):equals(#0) }) },
            { out := out:concat(c) }) }).
    out }.

edit:screenColumn := {
    self:expand(self:line:copyFrom(#1, self:column:sub(#1))):size:add(#1) }.

; The slice of one line that is on the screen. `left` is the same for every
; line, because a screen that scrolled each line to its own cursor would not be
; a screen of the file.
;
; A line that ends before the screen begins is empty rather than an error:
; `copyFrom` refuses a start past the end of a string, and a screen scrolled
; right past a short line is the ordinary case rather than a mistake. Found by
; pressing `$` on a long line with a short one under it.
edit:visible := { text, left | | wide, last |
    wide := self:expand(text).
    left:greaterThan(wide:size):ifElse({ "" }, {
        last := left:add(screen:columns):sub(#2).
        last:greaterThan(wide:size):ifTrue({ last := wide:size }).
        wide:copyFrom(left, last) }) }.

edit:scroll := {
    self:row:lessThan(self:top):ifTrue({ self:top := self:row }).
    self:row:greaterThan(self:top:add(self:textRows):sub(#1)):ifTrue({
        self:top := self:row:sub(self:textRows):add(#1) }).
    self:top:lessThan(#1):ifTrue({ self:top := #1 }) }.

edit:status := { | name |
    name := self:path:isNil:ifElse({ "[no name]" }, { self:path }).
    "{}{}  line {} of {}, column {}":fill([
        name,
        self:dirty:ifElse({ " [+]" }, { "" }),
        self:row, self:lines:size, self:column]) }.

edit:pad := { text | | wide |
    wide := screen:columns:sub(#1).
    text:size:greaterThan(wide):ifTrue({ text := text:copyFrom(#1, wide) }).
    text:asString("<{}":fill([wide])) }.

edit:bottom := {
    self:mode:equals('command):ifElse(
        { self:prompt:concat(self:command) },
        { self:message:equals(""):and({ self:mode:equals('insert) }):ifElse(
            { "-- INSERT --" },
            { self:message }) }) }.

edit:render := { | out, index, left, column |
    column := self:screenColumn.
    left := #1.
    column:greaterThan(screen:columns:sub(#1)):ifTrue({
        left := column:sub(screen:columns):add(#2) }).

    out := csi:concat("H").
    [#1, self:textRows]:loop({ i |
        index := self:top:add(i):sub(#1).
        out := out:concat(index:greaterThan(self:lines:size):ifElse(
            { "~" },
            { self:visible(self:lines:at(index), left) })):concat(csi):concat("K\r\n") }).

    out := out:concat(csi):concat("7m"):concat(self:pad(self:status))
              :concat(csi):concat("0m"):concat("\r\n").
    out := out:concat(self:bottom):concat(csi):concat("K").

    out := out:concat(csi):concat(self:mode:equals('command):ifElse(
        { "{};{}H":fill([screen:rows, self:command:size:add(#2)]) },
        { "{};{}H":fill([
            self:row:sub(self:top):add(#1),
            column:sub(left):add(#1)]) })).
    system:write(out) }.

; ---------------------------------------------------------------------------
; Keys
;
; One byte at a time, which is what `system:readKey` answers. An arrow is three
; of them and has to be assembled; the escape *key* is one, and is told from the
; first byte of an arrow by `system:keyWaiting` -- a read that gives up, which
; the top of this file explains and this program is the reason for.

edit:nextKey := { | key |
    self:pushed:notNil:ifElse(
        { key := self:pushed. self:pushed := nil. key },
        { system:readKey }) }.

edit:arrowFor := { letter |
    ['up, 'down, 'right, 'left]:at("ABCD":indexOf(letter)) }.

; How long an escape waits for the rest of a sequence before it is taken for the
; escape key. Nothing follows an escape that fast except a machine, and fifty
; milliseconds is what every terminal program settles on: long enough to cross a
; slow link, short enough that nobody notices the key is thinking.
edit:escapeWait := 0.05.

edit:decode := { key |
    key:notNil:and({ key:equals(esc) }):ifElse(
        { self:decodeEscape },
        { key }) }.

; **An escape is a keypress if nothing follows it.** `system:keyWaiting` is what
; makes that decidable: without it this had to read the next byte to find out
; whether there was one, which meant the escape key did nothing until the key
; after it arrived. A byte already pushed back counts as one waiting -- it is
; here, so nothing has to be asked about it.
edit:decodeEscape := { | second, third |
    self:pushed:isNil:and({ system:keyWaiting(self:escapeWait):not }):ifElse(
        { esc },
        { second := self:nextKey.
          second:isNil:ifElse({ esc }, {
          second:equals("["):ifElse(
              { third := self:nextKey.
                third:isNil:ifElse({ esc }, {
                "ABCD":indexOf(third):notNil:ifElse(
                    { self:arrowFor(third) },
                    ; `\e[5~` and its kind: read to the end of the sequence
                    ; rather than leaving its tail to be typed into the buffer.
                    { { third:notNil:and({ "0123456789;":indexOf(third):notNil }) }
                        :whileTrue({ third := self:nextKey }).
                      'unknown }) }) },
              ; An escape that begins nothing: the key itself, and the byte
              ; after it is a key in its own right and is kept.
              { self:pushed := second. esc }) }) }) }.

; ---------------------------------------------------------------------------
; Moving
;
; The cursor is a row and a column into the text, never into the screen: what
; is on the screen is decided at the last moment, by `render`. A motion that
; walks off the end of a line therefore has no screen to fall off.

; **A cursor may not stand past the last character; a range end must be able
; to.** `dw` on the last word of a file ends *after* it, and a motion that
; clamped itself to the last character would leave that character behind. Insert
; mode is allowed there for the same reason -- something has to be able to name
; the place after the end.
edit:clamp := { | limit |
    limit := self:mode:equals('insert):or({ self:measuring }):ifElse(
        { self:line:size:add(#1) },
        { self:line:size }).
    limit:lessThan(#1):ifTrue({ limit := #1 }).
    self:column:greaterThan(limit):ifTrue({ self:column := limit }).
    self:column:lessThan(#1):ifTrue({ self:column := #1 }) }.

edit:left := { self:column := self:column:sub(#1). self:clamp }.
edit:right := { self:column := self:column:add(#1). self:clamp }.

edit:up := {
    self:row:greaterThan(#1):ifTrue({ self:row := self:row:sub(#1) }).
    self:clamp }.

edit:down := {
    self:row:lessThan(self:lines:size):ifTrue({ self:row := self:row:add(#1) }).
    self:clamp }.

edit:lineStart := { self:column := #1 }.
edit:lineEnd := { self:column := self:line:size. self:clamp }.

edit:pageDown := {
    self:row := self:row:add(self:textRows).
    self:row:greaterThan(self:lines:size):ifTrue({ self:row := self:lines:size }).
    self:clamp }.

edit:pageUp := {
    self:row := self:row:sub(self:textRows).
    self:row:lessThan(#1):ifTrue({ self:row := #1 }).
    self:clamp }.

edit:firstLine := { self:row := #1. self:column := #1 }.
edit:lastLine := { self:row := self:lines:size. self:column := #1 }.

; The end of a line is a character here, spelled `\n`, and it is not in the
; buffer -- `charHere` invents it. That is what makes a motion across lines the
; same loop as a motion along one.
edit:charHere := {
    self:column:greaterThan(self:line:size):ifElse(
        { "\n" },
        { self:line:at(self:column) }) }.

wordCharacters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".

edit:classOf := { c |
    " \t\n":indexOf(c):notNil:ifElse({ 'space }, {
    wordCharacters:indexOf(c):notNil:ifElse({ 'word }, { 'punctuation }) }) }.

edit:stepForward := {
    self:column:lessOrEqual(self:line:size):ifElse(
        { self:column := self:column:add(#1). true },
        { self:row:lessThan(self:lines:size):ifElse(
            { self:row := self:row:add(#1). self:column := #1. true },
            { false }) }) }.

edit:stepBack := {
    self:column:greaterThan(#1):ifElse(
        { self:column := self:column:sub(#1). true },
        { self:row:greaterThan(#1):ifElse(
            { self:row := self:row:sub(#1).
              self:column := self:line:size:add(#1).
              true },
            { false }) }) }.

; `w` and `b`, over the three classes vi has: a run of word characters, a run of
; punctuation, or the space between them. An empty line is space here, where vi
; stops on one -- the difference is one line of code and no reader has ever
; wanted it the other way.
edit:wordForward := { | class, moved |
    moved := true.
    class := self:classOf(self:charHere).
    class:equals('space):ifFalse({
        { moved:and({ self:classOf(self:charHere):equals(class) }) }
            :whileTrue({ moved := self:stepForward }) }).
    { moved:and({ self:classOf(self:charHere):equals('space) }) }
        :whileTrue({ moved := self:stepForward }).
    self:clamp }.

edit:wordBack := { | class, moved |
    moved := self:stepBack.
    { moved:and({ self:classOf(self:charHere):equals('space) }) }
        :whileTrue({ moved := self:stepBack }).
    class := self:classOf(self:charHere).
    class:equals('space):ifFalse({
        { self:column:greaterThan(#1)
            :and({ self:classOf(self:line:at(self:column:sub(#1))):equals(class) }) }
            :whileTrue({ self:column := self:column:sub(#1) }) }).
    self:clamp }.

; ---------------------------------------------------------------------------
; Changing the text

edit:insertText := { text | | line |
    line := self:line.
    self:setLine(line:copyFrom(#1, self:column:sub(#1)):concat(text)
        :concat(line:copyFrom(self:column, line:size))).
    self:column := self:column:add(text:size) }.

edit:backspace := { | line, previous |
    self:column:greaterThan(#1):ifElse(
        { line := self:line.
          self:setLine(line:copyFrom(#1, self:column:sub(#2))
              :concat(line:copyFrom(self:column, line:size))).
          self:column := self:column:sub(#1) },
        { self:row:greaterThan(#1):ifTrue({
            previous := self:lines:at(self:row:sub(#1)).
            self:setLineAt(self:row:sub(#1), previous:concat(self:line)).
            self:removeLine(self:row).
            self:row := self:row:sub(#1).
            self:column := previous:size:add(#1) }) }) }.

edit:splitLine := { | line |
    line := self:line.
    self:setLine(line:copyFrom(#1, self:column:sub(#1))).
    self:insertLine(self:row:add(#1), line:copyFrom(self:column, line:size)).
    self:row := self:row:add(#1).
    self:column := #1 }.

; `x`, and `3x`. It fills the register like every other delete, so `xp` swaps
; two characters -- which is the smallest thing in vi that is only possible
; because deleting and yanking put their result in the same place.
edit:deleteChars := { n | | line, last |
    line := self:line.
    line:size:greaterThan(#0):ifTrue({
        last := self:column:add(n):sub(#1).
        last:greaterThan(line:size):ifTrue({ last := line:size }).
        self:register := line:copyFrom(self:column, last).
        self:registerIsLines := false.
        self:setLine(line:copyFrom(#1, self:column:sub(#1))
            :concat(line:copyFrom(last:add(#1), line:size))).
        self:clamp }) }.

; **`J` joins without putting a space in, where vi puts one.** vi's rule has
; exceptions -- not after a line that already ends in white space, two spaces
; after a full stop in some versions -- and the exceptions are the reason this
; does not copy it: a rule with three cases in it should be wanted by somebody
; before it is written. `xJ` and a typed space are the two keys it costs.
edit:joinLine := { | next |
    self:row:lessThan(self:lines:size):ifTrue({
        next := self:lines:at(self:row:add(#1)).
        self:column := self:line:size:add(#1).
        self:setLine(self:line:concat(next:trim)).
        self:removeLine(self:row:add(#1)).
        self:clamp }) }.

edit:enterInsert := { self:mode := 'insert. self:clamp }.

edit:openBelow := {
    self:insertLine(self:row:add(#1), "").
    self:row := self:row:add(#1).
    self:column := #1.
    self:enterInsert }.

edit:openAbove := {
    self:insertLine(self:row, "").
    self:column := #1.
    self:enterInsert }.

; ---------------------------------------------------------------------------
; What each key does
;
; **This is vi's grammar and not a table of keys**, which is the one structural
; thing an editor of this shape has to get right: `[count] operator [count]
; motion`, where the operator may be absent (and then the motion just moves),
; the count may be absent, and `dd` is the operator standing in for its own
; motion. `dw`, `3dw`, `d3w`, `d$`, `dj`, `y'a`, `2yy` and `10G` all fall out of
; that; a table of keys would need a row for each of them.
;
; So there are two dictionaries. **A motion answers a *place*** and moves
; nothing. **An action does something** and answers nothing anybody reads. The
; dispatcher below decides which of the two a key is, and whether an operator is
; waiting for a place to work over.

; ---------------------------------------------------------------------------
; A place
;
; Where a motion says to go, and how the text between here and there should be
; read. `linewise` is whole lines -- `dj` takes two of them, not the tail of one
; and the head of another. `inclusive` is whether the character it lands on is
; part of the range: `$` includes it and `w` does not, which is why `dw` leaves
; the next word alone and `d$` clears the line. `home` is for the jumps that
; land on the first non-blank character rather than keeping the column.

edit:place := object:new.
edit:place:row := #1.
edit:place:column := #1.
edit:place:linewise := false.
edit:place:inclusive := false.
edit:place:home := false.

edit:placeAt := { row, column | | p |
    p := self:place:new.
    p:row := row.
    p:column := column.
    p }.

edit:linePlace := { row | | p |
    p := self:placeAt(row, #1).
    p:linewise := true.
    p }.

; A jump: linewise, and it lands on the text rather than in the indentation.
edit:jumpPlace := { row | | p |
    p := self:linePlace(row).
    p:home := true.
    p }.

edit:times := { n | n:lessThan(#1):ifElse({ #1 }, { n }) }.

edit:lineWithin := { n |
    n:lessThan(#1):ifElse({ #1 }, {
    n:greaterThan(self:lines:size):ifElse({ self:lines:size }, { n }) }) }.

edit:firstNonBlank := { row | | line, i |
    line := self:lines:at(row).
    i := #1.
    { i:lessOrEqual(line:size):and({ " \t":indexOf(line:at(i)):notNil }) }
        :whileTrue({ i := i:add(#1) }).
    i }.

; **The motions were written to move the cursor**, and an operator needs to know
; where they would have gone without their having gone there. Running one and
; putting the cursor back is the whole of the difference, and it is why `dw` and
; `w` cannot disagree about what a word is: there is one `wordForward`.
edit:placeAfter := { block, count | | row, column, p |
    row := self:row.
    column := self:column.
    self:measuring := true.
    self:times(count):repeat(block).
    self:measuring := false.
    p := self:placeAt(self:row, self:column).
    self:row := row.
    self:column := column.
    p }.

edit:linePlaceAfter := { block, count | | p |
    p := self:placeAfter(block, count).
    p:linewise := true.
    p }.

; ---------------------------------------------------------------------------
; The motions

motions := dictionary:new.

motions:atPut("h", { n | edit:placeAfter({ edit:left }, n) }).
motions:atPut("l", { n | edit:placeAfter({ edit:right }, n) }).
motions:atPut("w", { n | edit:placeAfter({ edit:wordForward }, n) }).
motions:atPut("b", { n | edit:placeAfter({ edit:wordBack }, n) }).
motions:atPut('left, { n | edit:placeAfter({ edit:left }, n) }).
motions:atPut('right, { n | edit:placeAfter({ edit:right }, n) }).

motions:atPut("j", { n | edit:linePlaceAfter({ edit:down }, n) }).
motions:atPut("k", { n | edit:linePlaceAfter({ edit:up }, n) }).
motions:atPut('down, { n | edit:linePlaceAfter({ edit:down }, n) }).
motions:atPut('up, { n | edit:linePlaceAfter({ edit:up }, n) }).
motions:atPut(#6:asCharacter, { n | edit:linePlaceAfter({ edit:pageDown }, n) }).
motions:atPut(#2:asCharacter, { n | edit:linePlaceAfter({ edit:pageUp }, n) }).

motions:atPut("0", { n | edit:placeAt(edit:row, #1) }).

; `$` is inclusive -- the character it lands on is the last one on the line, and
; `d$` that left it behind would be a strange thing to have typed. With a count
; it is the end of the line that many further down.
motions:atPut("$", { n | | row, p |
    row := edit:lineWithin(edit:row:add(edit:times(n):sub(#1))).
    p := edit:placeAt(row, edit:lines:at(row):size).
    p:inclusive := true.
    p }).

; `G` is the last line, or the line the count names -- which is why `:17` and
; `17G` are the same thing said twice, as they are in vi.
motions:atPut("G", { n |
    edit:rememberJump.
    edit:jumpPlace(n:greaterThan(#0):ifElse(
        { edit:lineWithin(n) },
        { edit:lines:size })) }).

; ---------------------------------------------------------------------------
; The actions
;
; Everything that is not a motion and not an operator. Each takes the count,
; which most of them ignore.

normalKeys := dictionary:new.

normalKeys:atPut("i", { n | edit:enterInsert }).
normalKeys:atPut("a", { n | edit:column := edit:column:add(#1). edit:enterInsert }).
normalKeys:atPut("A", { n | edit:column := edit:line:size:add(#1). edit:enterInsert }).
normalKeys:atPut("I", { n | edit:column := edit:firstNonBlank(edit:row). edit:enterInsert }).
normalKeys:atPut("o", { n | edit:openBelow }).
normalKeys:atPut("O", { n | edit:openAbove }).
normalKeys:atPut("x", { n | edit:deleteChars(edit:times(n)) }).
normalKeys:atPut("J", { n | edit:times(n):repeat({ edit:joinLine }) }).
normalKeys:atPut("p", { n | edit:put(true, edit:times(n)) }).
normalKeys:atPut("P", { n | edit:put(false, edit:times(n)) }).
normalKeys:atPut(".", { n | edit:repeatChange(n) }).
normalKeys:atPut("u", { n | edit:undo }).
normalKeys:atPut(#18:asCharacter, { n | edit:redo }).      ; ctrl-r
normalKeys:atPut(":", { n | edit:beginPrompt(":") }).

; Searching. `/` and `?` are the same line the colon commands are typed on, with
; a different first character -- which is what `prompt` holds and the only thing
; that tells the three apart. `n` and `N` repeat the last one, forwards and the
; other way, and neither reads a line at all.
normalKeys:atPut("/", { n | edit:beginPrompt("/") }).
normalKeys:atPut("?", { n | edit:beginPrompt("?") }).
normalKeys:atPut("n", { n | edit:repeatSearch(edit:direction) }).
normalKeys:atPut("N", { n | edit:repeatSearch(
    edit:direction:equals('forward):ifElse({ 'backward }, { 'forward })) }).

operators := ["d", "y"].
prefixes := ["m", "'", "`", "g"].
digits := "0123456789".

; ---------------------------------------------------------------------------
; The dispatcher

edit:normalKey := { key |
    self:isDigit(key):ifElse(
        { self:count := self:count:mul(#10)
              :add(digits:indexOf(key):sub(#1)) },
        { self:prefix:notNil:ifElse(
            { self:resolvePrefix(key) },
            { self:normalCommand(key) }) }) }.

; A digit builds the count -- except a `0` with no count under way, which is the
; motion to the start of the line. Every vi has that rule and it is the only
; ambiguity in the notation. Arrows arrive as symbols and are never digits.
edit:isDigit := { key |
    key:isKindOf(string)
        :and({ digits:indexOf(key):notNil })
        :and({ key:equals("0"):not:or({ self:count:greaterThan(#0) }) }) }.

edit:normalCommand := { key | | place, done, given |
    done := false.

    ; `dd` and `yy`: an operator standing where its motion would go means the
    ; whole line, and the count is how many.
    self:operator:notNil:and({ key:equals(self:operator) }):ifTrue({
        self:operateLines(self:operator,
            self:lineWithin(self:row:add(self:times(self:count):sub(#1)))).
        self:operator := nil.
        self:count := #0.
        done := true }).

    ; A flag rather than a return, which is
    ; [3.2](../docs/ROADMAP.md#32-no-non-local-return) in its simplest form:
    ; a block answers its last expression and there is no way to leave one
    ; early, so the rest of the method has to ask whether it still has anything
    ; to do. Not a loop this time -- the two libraries that cite that entry
    ; wanted to stop a `whileTrue`, and this wants to stop a *method*.
    done:ifFalse({
        prefixes:indexOf(key):notNil:ifElse(
            { self:prefix := key },
            { motions:includes(key):ifElse(
                { place := motions:at(key):value(self:count).
                  self:count := #0.
                  self:applyPlace(place) },
                { operators:indexOf(key):notNil:and({ self:operator:isNil })
                      :ifElse(
                    { self:operator := key },
                    ; **The count is taken and cleared before the action runs**,
                    ; not after. `.` is the first action that dispatches keys of
                    ; its own, and with the count still pending its `3` became
                    ; the `33` of the count in progress -- `x3.` deleted the
                    ; line. An action that runs other commands has to start from
                    ; a clean state, and the only way to be sure is to leave one
                    ; behind.
                    { self:operator := nil.
                      given := self:count.
                      self:count := #0.
                      normalKeys:includes(key):ifTrue({
                          normalKeys:at(key):value(given) }) }) }) }) }) }.

edit:resolvePrefix := { key | | which, place |
    which := self:prefix.
    self:prefix := nil.

    which:equals("m"):ifTrue({
        self:marks:atPut(key, array:of(self:row, self:column)).
        self:count := #0 }).

    which:equals("g"):ifTrue({
        key:equals("g"):ifElse(
            { self:rememberJump.
              place := self:jumpPlace(self:count:greaterThan(#0):ifElse(
                  { self:lineWithin(self:count) },
                  { #1 })).
              self:count := #0.
              self:applyPlace(place) },
            { self:operator := nil. self:count := #0 }) }).

    which:equals("'"):or({ which:equals("`") }):ifTrue({
        place := self:markPlace(key, which:equals("`")).
        self:count := #0.
        place:isNil:ifElse(
            { self:operator := nil },
            { self:rememberJump. self:applyPlace(place) }) }) }.

edit:applyPlace := { place |
    self:operator:isNil:ifElse(
        { place:linewise:ifElse(
            { self:row := place:row.
              place:home:ifTrue({ self:column := self:firstNonBlank(self:row) }).
              self:clamp },
            { self:row := place:row.
              self:column := place:column.
              self:clamp }) },
        { self:applyOperator(place) }) }.

; ---------------------------------------------------------------------------
; Undo
;
; **A change is remembered by keeping the whole buffer**, which sounds
; extravagant and is not, because of one property of the language: **a string
; cannot be changed.** A line is a string, so a copy of the array of lines
; shares every line with the buffer it came from -- the copy is one allocation
; of one pointer per line, and the text itself is never copied at all. Editing a
; line makes a new string and puts it in one slot of one of the arrays; every
; other line in every other state is the same object it always was.
;
; That is why this is a stack of buffers rather than a list of inverse
; operations. Recording *how to undo a delete* is the design a mutable-string
; language is pushed towards, and it is a second implementation of every command
; -- one to do it and one to undo it, with the second one exercised only when
; something has already gone wrong. Here it buys nothing: the whole state costs
; a `copyFrom`.
;
; **What a change is**: one keystroke, except in insert mode, where everything
; typed between `i` and escape is one change. That is what makes `u` useful
; after typing a paragraph rather than infuriating. The boundary is drawn in
; `dispatch` -- a key arriving in normal mode closes the group, and the next
; thing that touches the text opens a new one.
;
; **Measured rather than argued.** Ten thousand lines of ten characters and ten
; thousand lines of a *thousand* characters snapshot in the same time --
; 0.095ms and 0.078ms, which is one measurement twice -- and a hundred times the
; text costing nothing is what sharing looks like from the outside.
;
; **`u` is a stack and not a toggle.** Real vi has one level and `u` undoes the
; undo; this keeps a hundred, and `ctrl-r` is the way back. The price is the
; array slots: a hundred states of a ten-thousand-line file runs under
; `--memory=16M` and not under 15M, which is sixteen bytes a line a state and is
; the cost of the simple design stated plainly rather than hidden.

edit:state := object:new.
edit:state:lines := nil.
edit:state:row := #1.
edit:state:column := #1.
edit:state:dirty := false.
edit:state:marks := nil.

edit:stateNow := { | st |
    st := self:state:new.
    st:lines := self:lines:copyFrom(#1, self:lines:size).
    st:row := self:row.
    st:column := self:column.
    st:dirty := self:dirty.
    ; Marks are part of the state, because a mark that survived an undo would be
    ; pointing at a line the undo has moved -- which is the failure this editor
    ; already refused once, when a mark had to move with the text.
    st:marks := self:copyOfMarks.
    st }.

edit:copyOfMarks := { | out |
    out := dictionary:new.
    self:marks:keysAndValuesDo({ name, m |
        out:atPut(name, array:of(m:at(#1), m:at(#2))) }).
    out }.

edit:restore := { st |
    self:lines := st:lines:copyFrom(#1, st:lines:size).
    self:marks := st:marks.
    self:row := st:row.
    self:column := st:column.
    self:dirty := st:dirty.
    self:clamp }.

; Called by the three methods that change the text, and by nothing else. The
; group flag is what makes a hundred keystrokes in insert mode one change.
edit:remember := {
    ; The one place that knows a command has changed the text, which is exactly
    ; what `.` needs to know as well. Undo and repeat want the same boundary and
    ; the same fact, so they are told by the same line.
    self:changedHere := true.
    self:group:ifFalse({
        self:undone:add(self:stateNow).
        self:undone:size:greaterThan(self:undoLimit):ifTrue({
            self:undone := self:undone:copyFrom(#2, self:undone:size) }).
        ; A new change is a new future: whatever was undone cannot be redone
        ; over the top of it.
        self:redone := array:new.
        self:group := true }) }.

edit:undo := {
    self:undone:size:equals(#0):ifElse(
        { self:message := "nothing left to undo" },
        { self:redone:add(self:stateNow).
          self:restore(self:undone:removeLast).
          self:message := "undone" }) }.

edit:redo := {
    self:redone:size:equals(#0):ifElse(
        { self:message := "nothing to redo" },
        { self:undone:add(self:stateNow).
          self:restore(self:redone:removeLast).
          self:message := "redone" }) }.

; ---------------------------------------------------------------------------
; The operators
;
; `d` and `y` differ in one line -- whether the text is taken out as well as
; taken down -- which is why they are one pair of methods with the operator
; passed in rather than two of everything.
;
; **One register**, holding either whole lines or a piece of text, and which of
; the two it is decides what `p` does with it. That flag is the whole of the
; difference between `yy` `p` (a copy of the line, below this one) and `yw` `p`
; (a copy of the word, after the cursor), and an editor that lost it would put
; text in the wrong place about half the time.

edit:applyOperator := { place | | op |
    op := self:operator.
    self:operator := nil.
    place:linewise:ifElse(
        { self:operateLines(op, place:row) },
        { self:operateChars(op, place) }) }.

edit:operateLines := { op, row | | from, to |
    from := self:row:lessOrEqual(row):ifElse({ self:row }, { row }).
    to := self:row:lessOrEqual(row):ifElse({ row }, { self:row }).
    from := self:lineWithin(from).
    to := self:lineWithin(to).

    self:register := self:lines:copyFrom(from, to).
    self:registerIsLines := true.

    op:equals("y"):ifElse(
        { self:row := from },
        { to:sub(from):add(#1):repeat({ self:removeLine(from) }).
          self:row := self:lineWithin(from).
          self:dirty := true }).
    self:column := self:firstNonBlank(self:row).
    self:clamp }.

edit:operateChars := { op, place | | fromRow, fromColumn, toRow, toColumn |
    self:row:lessThan(place:row):or({
        self:row:equals(place:row)
            :and({ self:column:lessOrEqual(place:column) }) }):ifElse(
        { fromRow := self:row.     fromColumn := self:column.
          toRow := place:row.      toColumn := place:column.
          ; The character a motion lands on belongs to the range only if the
          ; motion says so, and then the range ends one past it.
          place:inclusive:ifTrue({ toColumn := toColumn:add(#1) }) },
        { fromRow := place:row.    fromColumn := place:column.
          toRow := self:row.       toColumn := self:column }).

    ; vi's rule for an exclusive motion that ends in the first column: the range
    ; ends at the end of the line before instead. It is what makes `dw` on the
    ; last word of a line clear the tail of that line rather than dragging the
    ; next line up into it.
    place:inclusive:not
        :and({ toColumn:equals(#1) })
        :and({ toRow:greaterThan(fromRow) }):ifTrue({
        toRow := toRow:sub(#1).
        toColumn := self:lines:at(toRow):size:add(#1) }).

    self:register := self:textBetween(fromRow, fromColumn, toRow, toColumn).
    self:registerIsLines := false.

    op:equals("d"):ifTrue({
        self:removeBetween(fromRow, fromColumn, toRow, toColumn) }).
    self:row := fromRow.
    self:column := fromColumn.
    self:clamp }.

; From one place up to but not including another, newlines and all. A range
; inside one line is a slice; a range across several is a head, some whole
; lines, and a tail -- which is the same shape `removeBetween` puts back.
edit:textBetween := { fromRow, fromColumn, toRow, toColumn | | out |
    fromRow:equals(toRow):ifElse(
        { self:lines:at(fromRow):copyFrom(fromColumn, toColumn:sub(#1)) },
        { out := self:lines:at(fromRow):copyFrom(
              fromColumn, self:lines:at(fromRow):size).
          fromRow:add(#1):lessOrEqual(toRow:sub(#1)):ifTrue({
              [fromRow:add(#1), toRow:sub(#1)]:loop({ r |
                  out := out:concat("\n"):concat(self:lines:at(r)) }) }).
          out:concat("\n")
             :concat(self:lines:at(toRow):copyFrom(#1, toColumn:sub(#1))) }) }.

edit:removeBetween := { fromRow, fromColumn, toRow, toColumn | | head, tail |
    head := self:lines:at(fromRow):copyFrom(#1, fromColumn:sub(#1)).
    tail := self:lines:at(toRow):copyFrom(toColumn, self:lines:at(toRow):size).
    self:setLineAt(fromRow, head:concat(tail)).
    toRow:sub(fromRow):repeat({ self:removeLine(fromRow:add(#1)) }).
    self:dirty := true }.

; ---------------------------------------------------------------------------
; Putting it back

edit:put := { after, n |
    self:register:isNil:ifElse(
        { self:message := "nothing to put" },
        { self:registerIsLines:ifElse(
            { self:putLines(after, n) },
            { self:putText(after, n) }) }) }.

edit:putLines := { after, n | | at, put |
    at := after:ifElse({ self:row:add(#1) }, { self:row }).
    put := #0.
    n:repeat({
        self:register:do({ line |
            self:insertLine(at:add(put), line).
            put := put:add(#1) }) }).
    self:row := at.
    self:column := self:firstNonBlank(self:row).
    self:clamp }.

edit:putText := { after, n | | text, at, line, tail, pieces, last |
    text := "".
    n:repeat({ text := text:concat(self:register) }).

    line := self:line.
    at := after:ifElse({ self:column:add(#1) }, { self:column }).
    at:greaterThan(line:size:add(#1)):ifTrue({ at := line:size:add(#1) }).

    pieces := text:split("\n").
    pieces:size:equals(#1):ifElse(
        { self:setLine(line:copyFrom(#1, at:sub(#1)):concat(text)
              :concat(line:copyFrom(at, line:size))).
          self:column := at:add(text:size):sub(#1) },
        ; A piece of text with newlines in it -- `yw` never makes one, `y`a`
        ; across lines does -- goes in as a head, some lines, and a tail.
        { tail := line:copyFrom(at, line:size).
          self:setLine(line:copyFrom(#1, at:sub(#1)):concat(pieces:at(#1))).
          [#2, pieces:size]:loop({ k |
              self:insertLine(self:row:add(k:sub(#1)), pieces:at(k)) }).
          last := self:row:add(pieces:size):sub(#1).
          self:setLineAt(last, self:lines:at(last):concat(tail)).
          self:row := last.
          self:column := pieces:at(pieces:size):size }).
    self:dirty := true.
    self:clamp }.

; ---------------------------------------------------------------------------
; Marks
;
; `ma` remembers where the cursor is; `'a` goes back to that line and `` `a ``
; to that exact spot. The difference is the same one the operators care about,
; so `d'a` deletes whole lines and ``d`a`` deletes a piece of text.
;
; **A mark is a row and a column, and the row moves when the text does.** A mark
; set below the line you are deleting has to come up with it, or it points at
; the wrong text and says nothing about being wrong -- so `insertLine` and
; `removeLine` are the two places that call `shiftMarks`, and a mark on a line
; that is deleted is dropped rather than left pointing at whatever moved into
; its place.

edit:markPlace := { name, exact | | m |
    m := self:marks:at(name, nil).
    m:isNil:or({ m:at(#1):greaterThan(self:lines:size) }):ifElse(
        { self:message := "mark not set: {}":fill([name]). nil },
        { exact:ifElse(
            { self:placeAt(m:at(#1), m:at(#2)) },
            { self:jumpPlace(m:at(#1)) }) }) }.

edit:shiftMarks := { at, by |
    self:marks:keys:do({ name | | m |
        m := self:marks:at(name).
        by:greaterThan(#0):ifTrue({
            m:at(#1):greaterOrEqual(at):ifTrue({
                m:atPut(#1, m:at(#1):add(#1)) }) }).
        by:lessThan(#0):ifTrue({
            m:at(#1):equals(at):ifTrue({ self:marks:remove(name) }).
            m:at(#1):greaterThan(at):ifTrue({
                m:atPut(#1, m:at(#1):sub(#1)) }) }) }) }.

; The place a jump was made from, under the name `'` -- so `''` goes back to
; where you were, which is the mark you never have to remember to set.
edit:rememberJump := {
    self:marks:atPut("'", array:of(self:row, self:column)) }.

edit:arrowMove := { key |
    key:equals('up):ifTrue({ self:up }).
    key:equals('down):ifTrue({ self:down }).
    key:equals('left):ifTrue({ self:left }).
    key:equals('right):ifTrue({ self:right }) }.

edit:insertKey := { key | | byte |
    key:isKindOf(symbol):ifElse(
        { self:arrowMove(key) },
        { key:equals(esc):ifElse(
            { self:mode := 'normal.
              self:column:greaterThan(#1):ifTrue({
                  self:column := self:column:sub(#1) }).
              self:clamp },
            { byte := key:asByte.
              byte:equals(#13):or({ byte:equals(#10) }):ifElse(
                  { self:splitLine },
                  { byte:equals(#127):or({ byte:equals(#8) }):ifElse(
                      { self:backspace },
                      { byte:equals(#9):or({ byte:greaterOrEqual(#32) }):ifTrue({
                          self:insertText(key) }) }) }) }) }) }.

edit:beginPrompt := { which |
    self:mode := 'command.
    self:prompt := which.
    self:command := "" }.

edit:commandKey := { key | | byte, text |
    key:isKindOf(symbol):ifFalse({
        key:equals(esc):ifElse(
            { self:mode := 'normal. self:command := "" },
            { byte := key:asByte.
              byte:equals(#13):or({ byte:equals(#10) }):ifElse(
                  { text := self:command.
                    self:command := "".
                    self:mode := 'normal.
                    self:prompt:equals(":"):ifElse(
                        { self:runCommand(text) },
                        { self:runSearch(text, self:prompt:equals("/"):ifElse(
                            { 'forward }, { 'backward })) }) },
                  { byte:equals(#127):or({ byte:equals(#8) }):ifElse(
                      { self:command:size:equals(#0):ifElse(
                          { self:mode := 'normal },
                          { self:command := self:command:copyFrom(
                              #1, self:command:size:sub(#1)) }) },
                      { byte:greaterOrEqual(#32):ifTrue({
                          self:command := self:command:concat(key) }) }) }) }) }) }.

edit:dispatch := { key |
    self:message := "".
    ; Where one change ends and the next begins. A key pressed in normal mode
    ; closes the group, so whatever it does to the text is one thing to undo;
    ; insert mode does not, so everything typed until escape is one thing.
    self:mode:equals('insert):ifFalse({ self:group := false }).

    self:replaying:ifFalse({ self:recordBefore(key) }).

    self:mode:equals('insert):ifElse(
        { self:insertKey(key) },
        { self:mode:equals('command):ifElse(
            { self:commandKey(key) },
            { self:normalKey(key) }) }).

    self:replaying:ifFalse({ self:recordAfter }) }.

; ---------------------------------------------------------------------------
; Repeating a change
;
; **`.` repeats the keys, not a description of them.** The other way is to
; remember *what was done* -- an operator, a motion, a count, some inserted text
; -- and do it again, which is a second description of every command that can
; change the text and a second place for them to disagree. Keys are the thing
; the editor already understands: feeding them back in is the same path they
; took the first time, so `.` cannot drift from what it repeats.
;
; **What counts as a change is what `undo` already decided.** `remember` is
; called by the three methods that alter the text, so it is the one place that
; knows; it sets a flag here on the way past. A command that only moves the
; cursor records nothing, and neither does `yy` -- a yank is not a change, which
; is vi's rule and falls out rather than being written.
;
; **The colon line is left out on purpose.** `:s/a/b/` changes the text and `.`
; does not repeat it, here or in vi: a colon command takes a line of its own
; syntax and can name a range, and repeating one with a single key would be a
; different feature wearing the same key. `&` is what vi offers instead, and it
; is not here either.

; A key that arrives with nothing pending begins a new command, and that is
; where the recording starts.
edit:recordBefore := { key |
    self:mode:equals('normal)
        :and({ self:operator:isNil })
        :and({ self:prefix:isNil })
        :and({ self:count:equals(#0) }):ifTrue({
        self:typing := array:new.
        self:changedHere := false }).
    self:typing:notNil:ifTrue({ self:typing:add(key) }) }.

; And a command is over when nothing is pending again. The colon line takes the
; recording with it, which is how `:` commands stay out of `.`.
edit:recordAfter := {
    self:mode:equals('command):ifTrue({ self:typing := nil }).
    self:mode:equals('normal)
        :and({ self:operator:isNil })
        :and({ self:prefix:isNil })
        :and({ self:count:equals(#0) }):ifTrue({
        self:typing:notNil:and({ self:changedHere }):ifTrue({
            self:lastChange := self:typing }).
        self:typing := nil.
        self:changedHere := false }) }.

edit:repeatChange := { n |
    self:lastChange:isNil:ifElse(
        { self:message := "nothing to repeat" },
        { self:replaying := true.
          self:withCount(self:lastChange, n):do({ key | self:dispatch(key) }).
          self:replaying := false.
          ; The `.` itself is not a change to remember -- what it repeated
          ; already is, and a `.` that recorded itself would repeat a repeat.
          self:typing := nil.
          self:changedHere := false }) }.

; A count in front of `.` replaces the one that was typed the first time, which
; is what makes `3.` mean *three of those* rather than *that, three times*.
edit:withCount := { keys, n | | out, digits, past |
    n:lessThan(#1):ifElse({ keys }, {
        out := array:new.
        digits := n:asString.
        [#1, digits:size]:loop({ i | out:add(digits:at(i)) }).

        ; Everything the command was except the count it opened with. A `0` that
        ; is a *motion* is never first, so dropping the leading digits cannot
        ; take one.
        past := false.
        keys:do({ key |
            past:ifFalse({
                key:isKindOf(string)
                    :and({ "0123456789":indexOf(key):notNil }):ifFalse({
                    past := true }) }).
            past:ifTrue({ out:add(key) }) }).
        out }) }.



; ---------------------------------------------------------------------------
; The colon line

edit:writeTo := { where | | target |
    target := where:equals(""):ifElse({ self:path }, { where }).
    target:isNil:ifElse(
        { self:message := "no file name" },
        { { system:writeFile(target, self:text).
            self:path := target.
            self:dirty := false.
            self:message := "\"{}\" {} lines written":fill([
                target, self:lines:size]) }
            :onError({ e | self:message := e:message }) }) }.

edit:quit := { force |
    self:dirty:and({ force:not }):ifElse(
        { self:message := "no write since the last change (:q! overrides)" },
        { self:running := false }) }.

edit:goToLine := { n |
    self:row := n:lessThan(#1):ifElse({ #1 }, {
        n:greaterThan(self:lines:size):ifElse({ self:lines:size }, { n }) }).
    self:column := #1 }.

; `s/a/b/` and `%s/a/b/` take the whole of the rest of the line as their own
; syntax -- a pattern may hold spaces and a replacement usually does -- so they
; are recognised before the line is cut into words, and everything else is a
; word and its argument.
edit:runCommand := { text | | trimmed |
    trimmed := text:trim.
    trimmed:equals(""):ifTrue({ trimmed := "q" }).
    self:looksLikeSubstitute(trimmed):ifElse(
        { { self:runSubstitute(trimmed) }
            :onError({ e | self:message := e:message }) },
        { self:runWordCommand(trimmed) }) }.

edit:runWordCommand := { text | | words, name, rest, force |
    words := text:split(" ").
    name := words:at(#1).
    rest := words:copyFrom(#2, words:size):join(" "):trim.
    force := false.
    name:size:greaterThan(#0):and({
        name:copyFrom(name:size, name:size):equals("!") }):ifTrue({
        force := true.
        name := name:copyFrom(#1, name:size:sub(#1)) }).

    { name:equals(""):ifTrue({ nil }).
      name:equals("w"):ifTrue({ self:writeTo(rest) }).
      name:equals("q"):ifTrue({ self:quit(force) }).
      name:equals("wq"):or({ name:equals("x") }):ifTrue({
          self:writeTo(rest).
          self:dirty:ifFalse({ self:quit(true) }) }).
      ["", "w", "q", "wq", "x"]:indexOf(name):isNil:ifTrue({
          self:goToLine(name:asInteger) }) }
        :onError({ e | self:message := "not an editor command: {}":fill([text]) }) }.

; ---------------------------------------------------------------------------
; Searching
;
; The pattern is [lib/pattern.sol](../lib/pattern.sol)'s, compiled once when it
; is typed and asked about one line at a time. A file is not one string here --
; it is an array of lines, and the cursor is a row and a column -- so the search
; is a walk over lines rather than one call over the text. `^` and `$` therefore
; mean the ends of a *line*, which is what they mean in vi and is a property of
; how the buffer is held rather than a decision anybody took.
;
; Both directions wrap, and say so when they do. Wrapping without a word for it
; is how a search that found the thing you started on looks exactly like a
; search that found a new one.

edit:runSearch := { text, direction | | source |
    ; An empty pattern repeats the last one, which is what typing `/` and
    ; return means everywhere this key has ever existed.
    source := text:equals(""):ifElse({ self:patternSource }, { text }).
    source:equals(""):ifElse(
        { self:message := "no previous search" },
        { { self:pattern := pattern:on(source).
            self:patternSource := source.
            self:direction := direction.
            self:jumpToMatch(direction) }
            ; A pattern that will not compile is a typing mistake, not a fault:
            ; it says what is wrong with it and the editor carries on.
            :onError({ e |
                self:pattern := nil.
                self:message := e:message }) }) }.

; `n` and `N`. The stored direction is not changed by `N` -- it reverses this
; search rather than turning the searching around, which is vi's rule and the
; one that makes `N` usable for stepping back over something you passed.
edit:repeatSearch := { direction |
    self:pattern:isNil:ifElse(
        { self:message := "no previous search" },
        { self:jumpToMatch(direction) }) }.

edit:jumpToMatch := { direction | | hit |
    hit := direction:equals('forward):ifElse(
        { self:matchAfter },
        { self:matchBefore }).
    hit:isNil:ifElse(
        { self:message := "pattern not found: {}":fill([self:patternSource]) },
        { self:row := hit:at(#1).
          self:column := hit:at(#2).
          self:clamp.
          hit:at(#3):ifTrue({
              self:message := direction:equals('forward):ifElse(
                  { "search hit the bottom, continued at the top" },
                  { "search hit the top, continued at the bottom" }) }) }) }.

; Every line once, starting on the one the cursor is on and coming back to it:
; a match earlier in the current line is found on the last pass rather than the
; first, which is what makes the wrap complete rather than nearly so. Answers
; the row, the column, and whether it went round.
edit:matchAfter := { | found, i, row, from, wrapped |
    found := nil.
    i := #0.
    { found:isNil:and({ i:lessOrEqual(self:lines:size) }) }:whileTrue({ | at |
        row := self:row:add(i).
        wrapped := row:greaterThan(self:lines:size).
        wrapped:ifTrue({ row := row:sub(self:lines:size) }).
        from := i:equals(#0):ifElse({ self:column:add(#1) }, { #1 }).
        at := self:pattern:findFrom(self:lines:at(row), from).
        at:notNil:ifTrue({ found := [row, at, wrapped] }).
        i := i:add(#1) }).
    found }.

edit:matchBefore := { | found, i, row, before, wrapped |
    found := nil.
    i := #0.
    { found:isNil:and({ i:lessOrEqual(self:lines:size) }) }:whileTrue({ | at |
        row := self:row:sub(i).
        wrapped := row:lessThan(#1).
        wrapped:ifTrue({ row := row:add(self:lines:size) }).
        ; One past the end of the line, so `findLast` will consider a match
        ; that begins at its last character.
        before := i:equals(#0):ifElse(
            { self:column },
            { self:lines:at(row):size:add(#2) }).
        at := self:pattern:findLast(self:lines:at(row), before).
        at:notNil:ifTrue({ found := [row, at, wrapped] }).
        i := i:add(#1) }).
    found }.

; ---------------------------------------------------------------------------
; Substituting
;
; `:s/find/replace/`, `:s/find/replace/g` for every match on the line, and
; `:%s/...` for every line in the file. The `&` in a replacement is what was
; matched; [lib/pattern.sol](../lib/pattern.sol) does that part, and everything
; here is about which lines to offer it.
;
; **The delimiter is whatever follows the `s`**, so `:s#/usr/bin#/usr/local/bin#`
; needs no escaping at all -- which is vi's rule and is worth having the moment a
; path is being edited. `\/` inside a pattern is a `/` either way.
;
; **`/find/replace/` is not this command**, and cannot be: `/src/lib` is a
; perfectly good search for a pattern with a slash in it, and there is no way to
; tell the two apart without deciding that some searches are now substitutions.
; vi solved this by putting substitution on the colon line, which is where it is
; here.
;
; **There is still no undo**, and `:%s` is the first command in this editor that
; can change a hundred lines at once. What it has instead is a count -- *17
; substitutions on 9 lines* -- and `:q!`, which is a coarse undo for anything not
; yet written.

edit:looksLikeSubstitute := { text | | rest |
    rest := text:size:greaterThan(#0):and({ text:at(#1):equals("%") }):ifElse(
        { text:copyFrom(#2, text:size) },
        { text }).
    ; `s` and then something that is not a letter, a digit or a space: that
    ; something is the delimiter. `s` on its own is not a substitution here, and
    ; neither is anything that merely begins with an s.
    rest:size:greaterThan(#1):and({ rest:at(#1):equals("s") })
        :and({ "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
                   :indexOf(rest:at(#2)):isNil }) }.

; The pattern and the replacement, cut apart on the delimiter -- honouring a
; backslash before one, so a delimiter can appear inside either half.
edit:cutOn := { text, delimiter | | parts, current, s, c |
    parts := array:new.
    current := "".
    s := scan:on(text).
    { s:atEnd:not }:whileTrue({
        c := s:next.
        c:equals("\\"):and({ s:peek:notNil })
            :and({ s:peek:equals(delimiter) }):ifElse(
            { current := current:concat(s:next) },
            { c:equals(delimiter):ifElse(
                { parts:add(current). current := "" },
                { current := current:concat(c) }) }) }).
    parts:add(current).
    parts }.

edit:runSubstitute := { text | | everywhere, rest, delimiter, parts, source,
                               replacement, all, p, last, changed, total |
    everywhere := text:at(#1):equals("%").
    rest := everywhere:ifElse(
        { text:copyFrom(#3, text:size) },
        { text:copyFrom(#2, text:size) }).
    delimiter := rest:at(#1).
    parts := self:cutOn(rest:copyFrom(#2, rest:size), delimiter).

    source := parts:at(#1).
    replacement := parts:size:greaterThan(#1):ifElse({ parts:at(#2) }, { "" }).
    all := parts:size:greaterThan(#2)
        :and({ parts:at(#3):indexOf("g"):notNil }).

    ; An empty pattern is the last one searched for, the same as `/` alone.
    source:equals(""):ifTrue({ source := self:patternSource }).
    source:equals(""):ifElse(
        { self:message := "no previous search" },
        { p := pattern:on(source).
          ; A substitution sets the search too, so `n` walks what it changed --
          ; which is vi's rule and the reason to look before writing.
          self:pattern := p.
          self:patternSource := source.
          self:direction := 'forward.

          last := nil.
          changed := #0.
          total := #0.
          [everywhere:ifElse({ #1 }, { self:row }),
           everywhere:ifElse({ self:lines:size }, { self:row })]:loop({ r | | done |
              ; **One walk of the line, answering the text and the count.**
              ; Counted rather than compared: replacing `a` with `a` changes
              ; nothing and is still a substitution, and a report that said
              ; otherwise would be wrong in the one case somebody is checking.
              ; Counting it in a *second* walk was 2.2 seconds of the 7.7 that
              ; `:%s` over fifty thousand lines used to take.
              done := p:substitutionIn(self:lines:at(r), replacement, all).
              done:at("count"):greaterThan(#0):ifTrue({
                  self:setLineAt(r, done:at("text")).
                  total := total:add(done:at("count")).
                  changed := changed:add(#1).
                  last := r }) }).

          last:isNil:ifElse(
              { self:message := "pattern not found: {}":fill([source]) },
              { self:dirty := true.
                self:row := last.
                self:column := #1.
                self:clamp.
                self:message := "{} substitution{} on {} line{}":fill([
                    total, total:equals(#1):ifElse({ "" }, { "s" }),
                    changed, changed:equals(#1):ifElse({ "" }, { "s" })]) }) }) }.

; ---------------------------------------------------------------------------
; Running it
;
; With no argument it writes a file of its own and opens that, the same as every
; other program here: one you have to feed before it will say anything is one
; you will not run.

sample := "-- edit.sol --

h j k l or the arrows   move          i a I A   insert, here or at the ends
0 and $                 the ends      o and O   a new line below or above
w and b                 by word       x         delete a character
gg and G                the file      J         join the line below

d and y take a motion: dw d$ dj dG d'a, and dd yy for whole lines.
p and P put it back. x deletes a character. ma marks, 'a and `a go back.
u undoes, ctrl-r redoes; a hundred changes are kept. . does it again.
A count repeats: 3j, 2dd, d2w, 10G, 3p, and 3. means three of those.

/pattern and ?pattern search, forwards and back; n and N do it again.
A pattern is . * [abc] [^a-z] ^ $ and \\ to escape one of them.
:s/find/replace/ changes this line, /g every match on it, :%s every line.

:w  :w name  :q  :q!  :wq       and a bare number goes to that line
escape leaves insert mode, and takes effect the moment you press it --
which needed a message the language did not have. See the file.

Type in this buffer. `:w` writes it where it came from.
".

path := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1) },
    { | fallback |
      fallback := "build/edit-sample.txt".
      system:makeDirectory("build").
      system:fileExists(fallback):ifFalse({
          system:writeFile(fallback, sample) }).
      fallback }).

screen:measure.
edit:open(path).
edit:message := "{} -- :q to leave":fill([path]).

; The alternate screen, which is what makes an editor an editor: the shell's
; scrollback is still there when it leaves, with nothing of this on it.
system:write(csi:concat("?1049h")).

{ { edit:running }:whileTrue({ | key |
      screen:measure.
      edit:scroll.
      edit:render.
      key := edit:decode(edit:nextKey).
      key:isNil:ifElse(
          { edit:running := false },      ; the input ended: there is no one there
          { edit:dispatch(key) }) }) }
    :ensure({ system:write(csi:concat("?1049l")) }).
