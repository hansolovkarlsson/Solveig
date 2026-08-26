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
;   h j k l, arrows   move           i a I A   insert here, at the start, at the end
;   w b               by word        o O       open a line below or above
;   0 $               line ends      x dd J    a character, a line, join
;   gg G              file ends      :w :q :q! :wq :w name
;   ctrl-f ctrl-b     by a screen    :17       go to a line
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
; **The escape key cannot be told from the start of an escape sequence.**
; examples/keys.sol says so and could only say it in the abstract: nothing had
; yet bound the escape key to anything. A modal editor binds it to the most
; frequent action there is, and here is what that costs.
;
; An arrow is `escape [ A`, three bytes, and `readKey` answers one. So an escape
; is followed by a read, and that read **blocks until the next key**. Press
; escape in insert mode and nothing happens; press the next key and both happen
; at once -- the escape leaves insert mode and the byte after it is acted on as
; a normal-mode command. `edit:pushed` is what makes the second half true: the
; byte that turned out not to be part of a sequence is kept rather than thrown
; away, which is one line more than examples/keys.sol does and the difference
; between a lost keystroke and a late one.
;
; Nothing here can fix it. Telling the two apart needs a read that gives up
; after a few milliseconds, and the language has no such read -- which is a
; sentence worth writing exactly once, in the program that most wanted it.
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
; What it does not do
;
; No undo, no search, no counts before a command, no registers, no marks. Each
; of those is more of the same rather than more of the language, and this was
; written to ask the language a question rather than to replace anybody's
; editor. What is here is what it takes to open a file, move around it, change
; it and write it back -- which is enough to have edited this comment.
;
; It is held to a **recorded transcript** in tests/test_cli.c: a fixed screen
; size, a scripted stream of keystrokes, and the bytes it writes compared with
; the bytes it wrote when somebody last looked at them. `readKey` reading a pipe
; the same way it reads a terminal is what makes that possible at all.

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
edit:pending := nil.        ; the first key of a two-key command: d, g
edit:command := "".         ; the ':' line as it is typed
edit:pushed := nil.         ; one key read and not used -- see `nextKey`

edit:open := { path |
    self:path := path.
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
edit:setLine := { text | self:lines:atPut(self:row, text). self:dirty := true }.

; An array can be appended to and popped, and neither is what a line does when
; it arrives in the middle. Both of these rebuild the array around the point of
; the change -- one of the three smaller findings at the top of this file.
edit:insertLine := { at, text | | out |
    out := self:lines:copyFrom(#1, at:sub(#1)).
    out:add(text).
    self:lines:copyFrom(at, self:lines:size):do({ each | out:add(each) }).
    self:lines := out.
    self:dirty := true }.

edit:removeLine := { at | | out |
    self:lines:size:equals(#1):ifElse(
        { self:lines:atPut(#1, "") },
        { out := self:lines:copyFrom(#1, at:sub(#1)).
          self:lines:copyFrom(at:add(#1), self:lines:size):do({ each |
              out:add(each) }).
          self:lines := out }).
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
        { ":":concat(self:command) },
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
; of them and has to be assembled; the escape *key* is one, and cannot be told
; from the first byte of an arrow without a read that gives up after a few
; milliseconds. There is none, and what that costs is at the top of this file.

edit:nextKey := { | key |
    self:pushed:notNil:ifElse(
        { key := self:pushed. self:pushed := nil. key },
        { system:readKey }) }.

edit:arrowFor := { letter |
    ['up, 'down, 'right, 'left]:at("ABCD":indexOf(letter)) }.

edit:decode := { key | | second, third |
    key:notNil:and({ key:equals(esc) }):ifElse(
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
              { self:pushed := second. esc }) }) },
        { key }) }.

; ---------------------------------------------------------------------------
; Moving
;
; The cursor is a row and a column into the text, never into the screen: what
; is on the screen is decided at the last moment, by `render`. A motion that
; walks off the end of a line therefore has no screen to fall off.

edit:clamp := { | limit |
    limit := self:mode:equals('insert):ifElse(
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
            self:lines:atPut(self:row:sub(#1), previous:concat(self:line)).
            self:removeLine(self:row).
            self:row := self:row:sub(#1).
            self:column := previous:size:add(#1) }) }) }.

edit:splitLine := { | line |
    line := self:line.
    self:setLine(line:copyFrom(#1, self:column:sub(#1))).
    self:insertLine(self:row:add(#1), line:copyFrom(self:column, line:size)).
    self:row := self:row:add(#1).
    self:column := #1 }.

edit:deleteChar := { | line |
    line := self:line.
    line:size:greaterThan(#0):ifTrue({
        self:setLine(line:copyFrom(#1, self:column:sub(#1))
            :concat(line:copyFrom(self:column:add(#1), line:size))).
        self:clamp }) }.

edit:deleteLine := {
    self:removeLine(self:row).
    self:row:greaterThan(self:lines:size):ifTrue({ self:row := self:lines:size }).
    self:column := #1 }.

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
; A dictionary of blocks rather than a nest of `ifElse`, because this is a table
; in every editor ever written and it reads as one here too. The keys are the
; bytes themselves, and the four arrows are symbols, which is what `decode`
; makes of the three bytes each of them arrives as.

normalKeys := dictionary:new.

normalKeys:atPut("h", { edit:left }).
normalKeys:atPut("l", { edit:right }).
normalKeys:atPut("k", { edit:up }).
normalKeys:atPut("j", { edit:down }).
normalKeys:atPut('left, { edit:left }).
normalKeys:atPut('right, { edit:right }).
normalKeys:atPut('up, { edit:up }).
normalKeys:atPut('down, { edit:down }).
normalKeys:atPut("0", { edit:lineStart }).
normalKeys:atPut("$", { edit:lineEnd }).
normalKeys:atPut("w", { edit:wordForward }).
normalKeys:atPut("b", { edit:wordBack }).
normalKeys:atPut("G", { edit:lastLine }).
normalKeys:atPut(#6:asCharacter, { edit:pageDown }).      ; ctrl-f
normalKeys:atPut(#2:asCharacter, { edit:pageUp }).        ; ctrl-b

normalKeys:atPut("i", { edit:enterInsert }).
normalKeys:atPut("a", { edit:column := edit:column:add(#1). edit:enterInsert }).
normalKeys:atPut("A", { edit:column := edit:line:size:add(#1). edit:enterInsert }).
normalKeys:atPut("I", { edit:column := #1. edit:enterInsert }).
normalKeys:atPut("o", { edit:openBelow }).
normalKeys:atPut("O", { edit:openAbove }).
normalKeys:atPut("x", { edit:deleteChar }).
normalKeys:atPut("J", { edit:joinLine }).

; The two-key commands. The first key is remembered rather than read, because a
; key that waits for the next one is a key the screen cannot redraw behind.
normalKeys:atPut("d", { edit:pending := "d" }).
normalKeys:atPut("g", { edit:pending := "g" }).
normalKeys:atPut(":", { edit:mode := 'command. edit:command := "" }).

edit:normalKey := { key | | first |
    self:pending:notNil:ifElse(
        { first := self:pending.
          self:pending := nil.
          first:equals("d"):and({ key:equals("d") }):ifTrue({ self:deleteLine }).
          first:equals("g"):and({ key:equals("g") }):ifTrue({ self:firstLine }) },
        { normalKeys:includes(key):ifTrue({ normalKeys:at(key):value }) }) }.

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

edit:commandKey := { key | | byte, text |
    key:isKindOf(symbol):ifFalse({
        key:equals(esc):ifElse(
            { self:mode := 'normal. self:command := "" },
            { byte := key:asByte.
              byte:equals(#13):or({ byte:equals(#10) }):ifElse(
                  { text := self:command.
                    self:command := "".
                    self:mode := 'normal.
                    self:runCommand(text) },
                  { byte:equals(#127):or({ byte:equals(#8) }):ifElse(
                      { self:command:size:equals(#0):ifElse(
                          { self:mode := 'normal },
                          { self:command := self:command:copyFrom(
                              #1, self:command:size:sub(#1)) }) },
                      { byte:greaterOrEqual(#32):ifTrue({
                          self:command := self:command:concat(key) }) }) }) }) }) }.

edit:dispatch := { key |
    self:message := "".
    self:mode:equals('insert):ifElse(
        { self:insertKey(key) },
        { self:mode:equals('command):ifElse(
            { self:commandKey(key) },
            { self:normalKey(key) }) }) }.

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

edit:runCommand := { text | | words, name, rest, force |
    text:trim:equals(""):ifTrue({ text := "q" }).
    words := text:trim:split(" ").
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
; Running it
;
; With no argument it writes a file of its own and opens that, the same as every
; other program here: one you have to feed before it will say anything is one
; you will not run.

sample := "-- edit.sol --

h j k l or the arrows   move          i a I A   insert, here or at the ends
0 and $                 the ends      o and O   a new line below or above
w and b                 by word       x  dd     a character, a line
gg and G                the file      J         join the line below

:w  :w name  :q  :q!  :wq       and a bare number goes to that line
escape leaves insert mode -- and is read on the key after it, which is
the one thing this editor cannot do anything about. See the file.

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
