; checks.sol -- the editor, driven by scripted keys and held to what it wrote.
;
; Run with:  ./bin/solas programs/edit/checks.sol && ./bin/solvm programs/edit/checks.sob
;
; **A hundred and sixty-five sessions.** Each one writes a file, feeds
; [edit.sol](../edit.sol) a string of keys through a pipe, and compares the file
; it wrote against what those keys should have done to it. `readKey` reading a
; pipe exactly as it reads a terminal is what makes that possible at all, and is
; the reason the editor could be tested from its first hour.
;
; **It checks the text and not the screen**, which is the difference between
; this and [session.out](session.out). That transcript is every byte the editor
; drew and catches a redraw that moved; these catch a command that did the wrong
; thing to the buffer, and there are a hundred and sixty-five of them because
; the answer is short enough to write down for every case worth having.
;
; **Where the failures came from.** Four days of building the editor produced
; one defect per feature, and this file is where each of them would have been
; caught the next day: the clamp that let `dw` leave the last character of a
; file, the count that was cleared after an action rather than before, `c$`
; eating the space before the cursor. Roughly three of every four checks that
; failed while being written were the check rather than the editor -- which is
; the argument for writing the expectation first, since a wrong one costs a
; minute and a real defect is found in the same minute.

esc := #27:asCharacter.

; A key sequence is written as text, and the keys that have no escape of their
; own get one here: `\e` is escape, `\d` is the delete key, `\c` is ctrl-r, and
; `\f` and `\b` are ctrl-f and ctrl-b. Everything else is the byte it looks
; like, which is what a person types.
keysOf := { text |
    text:split("\\e"):join(esc)
        :split("\\d"):join(#127:asCharacter)
        :split("\\c"):join(#18:asCharacter)
        :split("\\f"):join(#6:asCharacter)
        :split("\\b"):join(#2:asCharacter) }.

editor := "build/checks/edit.sob".
work   := "build/checks/file.txt".
typed  := "build/checks/keys.in".

system:makeDirectory("build").
system:makeDirectory("build/checks").

system:run(["bin/solas", "programs/edit.sol", "-o", editor],
    ["stdout", 'discard, "stderr", 'discard]):equals(#0):ifFalse({
    "checks: cannot compile programs/edit.sol":display.
    system:exit(#1) }).

failures := array:new.
checked := #0.

; The editor's own output goes nowhere: what it drew is [session.out](session.out)'s
; business, and what it wrote is this file's.
check := { group, name, keys, start, want | | got |
    system:writeFile(work, start).
    system:writeFile(typed, keysOf:value(keys)).
    system:run(["bin/solvm", editor, work],
        ["stdin", typed, "stdout", 'discard, "stderr", 'discard]).
    checked := checked:add(#1).
    got := system:readFile(work).
    got:equals(want):ifFalse({ failures:add([group, name, want, got]) }) }.

; ---------------------------------------------------------------------------
; Moving, inserting and deleting

check:value("run", "insert at start",
    "iX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "Xalpha\nbeta\ngamma\n").
check:value("run", "append after cursor",
    "aX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "aXlpha\nbeta\ngamma\n").
check:value("run", "A at end of line",
    "AX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alphaX\nbeta\ngamma\n").
check:value("run", "o opens below",
    "oX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nX\nbeta\ngamma\n").
check:value("run", "O opens above",
    "OX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "X\nalpha\nbeta\ngamma\n").
check:value("run", "x deletes",
    "xx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "pha\nbeta\ngamma\n").
check:value("run", "dd deletes a line",
    "jdd:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\ngamma\n").
check:value("run", "dd on the last line",
    "Gdd:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\n").
check:value("run", "J joins",
    "J:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alphabeta\ngamma\n").
check:value("run", "G then x",
    "Gx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\namma\n").
check:value("run", "gg after G",
    "GggiX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "Xalpha\nbeta\ngamma\n").
check:value("run", "return splits",
    "lli\r\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "al\npha\nbeta\ngamma\n").
check:value("run", "backspace joins",
    "ji\\d\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alphabeta\ngamma\n").
check:value("run", "backspace in a line",
    "lli\\d\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "apha\nbeta\ngamma\n").
check:value("run", "colon number",
    ":2\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\neta\ngamma\n").
check:value("run", "w moves by word",
    "wx:w\r:q\r",
    "alpha beta\n",
    "alpha eta\n").
check:value("run", "b moves back",
    "\\$bix\\e:w\r:q\r",
    "alpha beta\n",
    "alpha xbeta\n").
check:value("run", "q! drops changes",
    "iX\\e:q!\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("run", "q refuses when dirty",
    "iX\\e:q\r:q!\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("run", "wq writes and goes",
    "iX\\e:wq\r",
    "alpha\nbeta\ngamma\n",
    "Xalpha\nbeta\ngamma\n").
check:value("run", "arrows move",
    "\\e[B\\e[CiX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbXeta\ngamma\n").
check:value("run", "empty file",
    "iX\\e:w\r:q\r",
    "",
    "X\n").

; ---------------------------------------------------------------------------
; Searching

check:value("search", "forward search",
    "/gam\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\namma\n").
check:value("search", "search from cursor+1",
    "/a\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alph\nbeta\ngamma\n").
check:value("search", "not found stays put",
    "/zz\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("search", "backwards wraps",
    "?mm\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngama\n").
check:value("search", "n repeats",
    "/a\rnx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbet\ngamma\n").
check:value("search", "N reverses",
    "/a\rnNx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alph\nbeta\ngamma\n").
check:value("search", "anchor start",
    "/^b\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\neta\ngamma\n").
check:value("search", "anchor end",
    "/a$\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alph\nbeta\ngamma\n").
check:value("search", "a class",
    "/[gm]a\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\namma\n").
check:value("search", "star",
    "/b*e\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\neta\ngamma\n").
check:value("search", "bad pattern reported",
    "/[ab\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("search", "empty repeats",
    "/a\r/\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbet\ngamma\n").
check:value("search", "n without a search",
    "nx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("search", "search then edit",
    "/gamma\riX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\nXgamma\n").
check:value("search", "wrap forward",
    "G/alpha\rx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").

; ---------------------------------------------------------------------------
; Substituting

check:value("subst", "line, first match",
    ":s/a/X/\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "Xlpha beta\nbeta gamma\ngamma alpha\n").
check:value("subst", "line, all matches",
    ":s/a/X/g\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "XlphX betX\nbeta gamma\ngamma alpha\n").
check:value("subst", "whole file",
    ":%s/a/X/\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "Xlpha beta\nbetX gamma\ngXmma alpha\n").
check:value("subst", "whole file, global",
    ":%s/beta/B/g\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "alpha B\nB gamma\ngamma alpha\n").
check:value("subst", "ampersand",
    ":s/beta/[&]/\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "alpha [beta]\nbeta gamma\ngamma alpha\n").
check:value("subst", "delete a word",
    ":s/alpha //\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "beta\nbeta gamma\ngamma alpha\n").
check:value("subst", "another delimiter",
    ":s#a#X#g\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "XlphX betX\nbeta gamma\ngamma alpha\n").
check:value("subst", "a pattern with class",
    ":%s/[ag]/-/g\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "-lph- bet-\nbet- --mm-\n--mm- -lph-\n").
check:value("subst", "escaped delimiter",
    ":s/\\/x/-/\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "alpha beta\nbeta gamma\ngamma alpha\n").
check:value("subst", "no match",
    ":s/zz/X/\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "alpha beta\nbeta gamma\ngamma alpha\n").
check:value("subst", "bad pattern",
    ":s/[ab/X/\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "alpha beta\nbeta gamma\ngamma alpha\n").
check:value("subst", "empty reuses search",
    "/gamma\r:s//G/\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "alpha beta\nbeta G\ngamma alpha\n").
check:value("subst", "cursor to last line",
    ":%s/a/X/\rx:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "Xlpha beta\nbetX gamma\nXmma alpha\n").
check:value("subst", "anchored",
    ":%s/^/> /\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "> alpha beta\n> beta gamma\n> gamma alpha\n").
check:value("subst", "end anchor",
    ":%s/$/./\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "alpha beta.\nbeta gamma.\ngamma alpha.\n").
check:value("subst", "zero width global",
    ":s/x*/-/g\r:w\r:q\r",
    "alpha beta\nbeta gamma\ngamma alpha\n",
    "-a-l-p-h-a- -b-e-t-a-\nbeta gamma\ngamma alpha\n").

; ---------------------------------------------------------------------------
; Counts, operators, registers and marks

check:value("vi", "3j then x",
    "3jx:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nbeta\ngamma\nelta\n").
check:value("vi", "2x",
    "2x:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "pha\nbeta\ngamma\ndelta\n").
check:value("vi", "3G",
    "3Gx:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nbeta\namma\ndelta\n").
check:value("vi", "10G clamps",
    "10Gx:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nbeta\ngamma\nelta\n").
check:value("vi", "2w",
    "2wx:w\r:q\r",
    "alpha beta gamma\n",
    "alpha beta amma\n").
check:value("vi", "0 is a motion",
    "wl0x:w\r:q\r",
    "alpha beta gamma\n",
    "lpha beta gamma\n").
check:value("vi", "dw",
    "dw:w\r:q\r",
    "alpha beta gamma\n",
    "beta gamma\n").
check:value("vi", "2dw",
    "2dw:w\r:q\r",
    "alpha beta gamma\n",
    "gamma\n").
check:value("vi", "d2w",
    "d2w:w\r:q\r",
    "alpha beta gamma\n",
    "gamma\n").
check:value("vi", "d dollar",
    "wd$:w\r:q\r",
    "alpha beta gamma\n",
    "alpha \n").
check:value("vi", "d0",
    "wwd0:w\r:q\r",
    "alpha beta gamma\n",
    "gamma\n").
check:value("vi", "dd",
    "dd:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "beta\ngamma\ndelta\n").
check:value("vi", "2dd",
    "2dd:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "gamma\ndelta\n").
check:value("vi", "dj takes two",
    "dj:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "gamma\ndelta\n").
check:value("vi", "dk from below",
    "jdk:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "gamma\ndelta\n").
check:value("vi", "dG",
    "jdG:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\n").
check:value("vi", "dw at line end",
    "wwdw:w\r:q\r",
    "alpha beta gamma\n",
    "alpha beta \n").
check:value("vi", "yyp duplicates",
    "yyp:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nalpha\nbeta\ngamma\ndelta\n").
check:value("vi", "yyP",
    "jyyP:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nbeta\nbeta\ngamma\ndelta\n").
check:value("vi", "2yy then G p",
    "2yyGp:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nbeta\ngamma\ndelta\nalpha\nbeta\n").
check:value("vi", "ddp swaps lines",
    "ddp:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "beta\nalpha\ngamma\ndelta\n").
check:value("vi", "xp swaps letters",
    "xp:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "lapha\nbeta\ngamma\ndelta\n").
check:value("vi", "yw then p",
    "ywwP:w\r:q\r",
    "alpha beta gamma\n",
    "alpha alpha beta gamma\n").
check:value("vi", "y dollar then p",
    "y$$p:w\r:q\r",
    "alpha beta gamma\n",
    "alpha beta gammaalpha beta gamma\n").
check:value("vi", "3p",
    "yy3p:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nalpha\nalpha\nalpha\nbeta\ngamma\ndelta\n").
check:value("vi", "put with nothing",
    "p:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nbeta\ngamma\ndelta\n").
check:value("vi", "mark and return",
    "majj'ax:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "lpha\nbeta\ngamma\ndelta\n").
check:value("vi", "exact mark",
    "llmaj`ax:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alha\nbeta\ngamma\ndelta\n").
check:value("vi", "d to a mark",
    "jjmagg d'a:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "delta\n").
check:value("vi", "mark moves down",
    "jjmaggdd'ax:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "beta\namma\ndelta\n").
check:value("vi", "mark is dropped",
    "maddj'ax:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "beta\namma\ndelta\n").
check:value("vi", "back to where",
    "G''x:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "lpha\nbeta\ngamma\ndelta\n").
check:value("vi", "yank to a mark",
    "jjmagg y'aGp:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nbeta\ngamma\ndelta\nalpha\nbeta\ngamma\n").

; ---------------------------------------------------------------------------
; Edges

check:value("edge", "dd every line",
    "5dd:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "\n").
check:value("edge", "dj at the end",
    "jjdj:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\n").
check:value("edge", "100dd clamps",
    "j100dd:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\n").
check:value("edge", "d on an empty line",
    "ox\\ekdd:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "x\nbeta\ngamma\n").
check:value("edge", "charwise across lines",
    "jlmagg y`aGp:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngalpha\nbamma\n").
check:value("edge", "P at column one",
    "ywP:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alphaalpha\nbeta\ngamma\n").
check:value("edge", "y then move then p",
    "ywjp:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbalphaeta\ngamma\n").
check:value("edge", "operator cancelled",
    "dqx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("edge", "count then escape",
    "3\\ex:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("edge", "mark then edit",
    "majodd\\e'aix\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "xalpha\nbeta\ndd\ngamma\n").

; ---------------------------------------------------------------------------
; Undo and redo

check:value("undo", "undo x",
    "xu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo dd",
    "ddu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo 2dd",
    "2ddu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo dw",
    "dwu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo p",
    "yyGpu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo a whole insert",
    "ihello world\\eu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo o",
    "oxyz\\eu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo J",
    "Ju:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo a substitution",
    ":%s/a/X/g\ru:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo twice",
    "xxuu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo three deletes",
    "dddddduuu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo then redo",
    "ddu\\c:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "beta\ngamma\n").
check:value("undo", "redo twice",
    "xxuu\\c\\c:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "pha\nbeta\ngamma\n").
check:value("undo", "nothing to undo",
    "uu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "nothing to redo",
    "\\cx:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("undo", "a change drops redo",
    "ddu x\\c:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("undo", "undo restores the cursor",
    "jjddux:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\namma\n").
check:value("undo", "insert then more",
    "iab\\eicd\\euu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nbeta\ngamma\n").
check:value("undo", "undo one insert",
    "iab\\eicd\\eu:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "abalpha\nbeta\ngamma\n").
check:value("undo", "undo a mark delete",
    "majjddu'ax:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("undo", "undo brings a mark back",
    "maddu'ax:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "lpha\nbeta\ngamma\n").
check:value("undo", "without undo it is gone",
    "madd'ax:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "eta\ngamma\n").

; ---------------------------------------------------------------------------
; Repeating a change

check:value("dot", "repeat x",
    "x.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "pha\nbeta\ngamma\ndelta\n").
check:value("dot", "repeat x three times",
    "x...:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "a\nbeta\ngamma\ndelta\n").
check:value("dot", "repeat dd",
    "dd.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "gamma\ndelta\n").
check:value("dot", "repeat dw",
    "dw.:w\r:q\r",
    "one two three four five\n",
    "three four five\n").
check:value("dot", "repeat an insert",
    "iX\\e.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "XXalpha\nbeta\ngamma\ndelta\n").
check:value("dot", "repeat o and its text",
    "oxy\\e.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nxy\nxy\nbeta\ngamma\ndelta\n").
check:value("dot", "repeat p",
    "yyjp.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alpha\nbeta\nalpha\nalpha\ngamma\ndelta\n").
check:value("dot", "repeat J",
    "J.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "alphabetagamma\ndelta\n").
check:value("dot", "repeat with a count",
    "x3.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "a\nbeta\ngamma\ndelta\n").
check:value("dot", "count replaces count",
    "2x3.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "\nbeta\ngamma\ndelta\n").
check:value("dot", "repeat after moving",
    "dwjj.:w\r:q\r",
    "one two three four five\n",
    "three four five\n").
check:value("dot", "yank is not a change",
    "yyx.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "pha\nbeta\ngamma\ndelta\n").
check:value("dot", "a motion is not one",
    "xj.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "lpha\neta\ngamma\ndelta\n").
check:value("dot", "nothing to repeat",
    ".x:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "lpha\nbeta\ngamma\ndelta\n").
check:value("dot", "colon is not repeated",
    "x:%s/beta/B/\r.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "lpha\n\ngamma\ndelta\n").
check:value("dot", "undo undoes a repeat",
    "x.u:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "lpha\nbeta\ngamma\ndelta\n").
check:value("dot", "repeat after undo",
    "dwu.:w\r:q\r",
    "one two three four five\n",
    "two three four five\n").
check:value("dot", "search is not a change",
    "x/gamma\r.:w\r:q\r",
    "alpha\nbeta\ngamma\ndelta\n",
    "lpha\nbeta\namma\ndelta\n").

; ---------------------------------------------------------------------------
; Changing, finding a character, replacing and swapping case

check:value("more", "cw keeps the space",
    "cwX\\e:w\r:q\r",
    "one two three\n",
    "X two three\n").
check:value("more", "ce is the same",
    "ceX\\e:w\r:q\r",
    "one two three\n",
    "X two three\n").
check:value("more", "cw inside a line",
    "wcwX\\e:w\r:q\r",
    "one two three\n",
    "one X three\n").
check:value("more", "c dollar",
    "wc$X\\e:w\r:q\r",
    "one two three\n",
    "one X\n").
check:value("more", "cc empties the line",
    "ccX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "X\nbeta\ngamma\n").
check:value("more", "2cc joins two",
    "2ccX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "X\ngamma\n").
check:value("more", "cc keeps the count",
    "jccX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nX\ngamma\n").
check:value("more", "c with a find",
    "cf X\\e:w\r:q\r",
    "one two three\n",
    "Xtwo three\n").
check:value("more", "e moves to word end",
    "ex:w\r:q\r",
    "one two three\n",
    "on two three\n").
check:value("more", "de takes the word",
    "de:w\r:q\r",
    "one two three\n",
    " two three\n").
check:value("more", "2e",
    "2ex:w\r:q\r",
    "one two three\n",
    "one tw three\n").
check:value("more", "f finds",
    "ftx:w\r:q\r",
    "one two three\n",
    "one wo three\n").
check:value("more", "dft",
    "dft:w\r:q\r",
    "one two three\n",
    "wo three\n").
check:value("more", "t stops before",
    "dtt:w\r:q\r",
    "one two three\n",
    "two three\n").
check:value("more", "3f",
    "3f,x:w\r:q\r",
    "a,b,c,d\n",
    "a,b,cd\n").
check:value("more", "F goes back",
    "$Fbx:w\r:q\r",
    "a,b,c,d\n",
    "a,,c,d\n").
check:value("more", "T goes back to after",
    "$dTc:w\r:q\r",
    "a,b,c,d\n",
    "a,b,cd\n").
check:value("more", "f not found",
    "fzx:w\r:q\r",
    "one two three\n",
    "ne two three\n").
check:value("more", "r replaces",
    "rZ:w\r:q\r",
    "one two three\n",
    "Zne two three\n").
check:value("more", "3r",
    "3rZ:w\r:q\r",
    "one two three\n",
    "ZZZ two three\n").
check:value("more", "r refuses past end",
    "$3rZ:w\r:q\r",
    "one two three\n",
    "one two three\n").
check:value("more", "tilde swaps case",
    "~:w\r:q\r",
    "Hello World\n",
    "hello World\n").
check:value("more", "5 tilde",
    "5~:w\r:q\r",
    "Hello World\n",
    "hELLO World\n").
check:value("more", "tilde at line end",
    "$5~:w\r:q\r",
    "Hello World\n",
    "Hello WorlD\n").
check:value("more", "repeat a change",
    "cwX\\ew.:w\r:q\r",
    "one two three\n",
    "X X three\n").
check:value("more", "repeat r",
    "rZw.:w\r:q\r",
    "one two three\n",
    "Zne Zwo three\n").
check:value("more", "repeat tilde",
    "~.:w\r:q\r",
    "Hello World\n",
    "hEllo World\n").
check:value("more", "undo a change",
    "cwX\\eu:w\r:q\r",
    "one two three\n",
    "one two three\n").
check:value("more", "yank then change",
    "yyjccX\\e:w\r:q\r",
    "alpha\nbeta\ngamma\n",
    "alpha\nX\ngamma\n").

; ---------------------------------------------------------------------------
; What they said

"":display.
"{} sessions checked, {} failed":fill([checked, failures:size]):display.

failures:do({ each |
    "":display.
    "  {} -- {}":fill([each:at(#1), each:at(#2)]):display.
    "    wanted {}":fill([each:at(#3)]):print.
    "    got    {}":fill([each:at(#4)]):print }).

failures:size:equals(#0):ifElse(
    { "every session holds":display },
    { system:exit(#1) }).
