; mirror.sol -- copy one directory tree into another, and report what changed.
;
; Run with:  ./bin/solas examples/mirror.sol && ./bin/solvm examples/mirror.sob
; Over trees of your own:  ./bin/solvm examples/mirror.sob source destination
; To see what it would do without doing it:  ...:sob source destination dry
;
; The fifth program here written to do a job rather than to show a feature, and
; the first that *writes* to the filesystem rather than reading it. walk.sol
; lists a tree; files.sol reads and writes one file. Mirroring is the ordinary
; job that needs the whole set at once -- list, test, measure, make, copy -- and
; it is the one every backup script is.
;
; It does not delete. A destination file with no counterpart in the source is
; reported and left alone, because a mirror that deletes is a different and much
; more dangerous tool, and an example is a bad place to hide one.
;
; What it found is at the bottom, under "what this wanted".

@include "control.sol".

; ---------------------------------------------------------------------------
; Where the trees are

arguments := system:arguments.
source := arguments:size:greaterThan(#0):ifElse(
    { arguments:at(#1) }, { "build/mirror-from" }).
destination := arguments:size:greaterThan(#1):ifElse(
    { arguments:at(#2) }, { "build/mirror-to" }).
dryRun := arguments:size:greaterThan(#2):and({ arguments:at(#3):equals("dry") }).

; With no arguments there is nothing to mirror, so it makes something to mirror.
; A program that needs a tree before it can run is a poor demonstration.
; `makeDirectory` is an error when the directory is already there, so "make sure
; this exists" -- which is what a script wants nine times in ten -- is two
; messages rather than one. See ROADMAP 6.25.
ensure := { path | system:isDirectory(path):ifFalse({ system:makeDirectory(path) }) }.

arguments:size:equals(#0):ifTrue({
    ensure:value("build/mirror-from").
    ensure:value("build/mirror-from/docs").
    system:writeFile("build/mirror-from/README", "the top of the tree\n").
    system:writeFile("build/mirror-from/docs/one.txt", "first\n").
    system:writeFile("build/mirror-from/docs/two.txt", "second\n").
    system:writeFile("build/mirror-from/notes", "loose notes\n") }).

system:isDirectory(source):ifFalse({
    "no such directory: {}":fill([source]):display.
    system:exit(#1) }).

; ---------------------------------------------------------------------------
; Walking the source
;
; With a stack rather than by recursion, which lib/html.sol learned the hard way:
; the frame limit is not a property of the tree, it is a property of how you
; walk it. A directory tree is nowhere near 62 deep in practice, and writing it
; the other way once was enough.

relatives := array:new.        ; every file, as a path relative to the source
folders := array:new.          ; every directory, likewise, parents first

pending := array:new.
pending:add("").

{ pending:size:greaterThan(#0) }:whileTrue({ | here, full |
    here := pending:removeLast.
    full := here:equals(""):ifElse({ source }, { source:concat("/"):concat(here) }).

    system:filesIn(full):sorted:do({ name | | child |
        child := here:equals(""):ifElse({ name }, { here:concat("/"):concat(name) }).
        system:isDirectory(full:concat("/"):concat(name)):ifElse(
            { folders:add(child). pending:add(child) },
            { relatives:add(child) }) }) }).

; ---------------------------------------------------------------------------
; What has to happen

made := array:new.
copied := array:new.
skipped := array:new.
extra := array:new.

folders:do({ folder | | there |
    there := destination:concat("/"):concat(folder).
    system:isDirectory(there):ifFalse({ made:add(folder) }) }).

relatives:do({ relative | | from, to |
    from := source:concat("/"):concat(relative).
    to := destination:concat("/"):concat(relative).
    system:fileExists(to):ifElse(
        { system:fileSize(from):equals(system:fileSize(to))
            :and({ system:modifiedAt(from):lessOrEqual(system:modifiedAt(to)) })
            :ifElse(
                { skipped:add(relative) },
                { copied:add(relative) }) },
        { copied:add(relative) }) }).

; The other direction, one level, to say what is there that should not be.
system:isDirectory(destination):ifTrue({
    system:filesIn(destination):sorted:do({ name | | path |
        path := destination:concat("/"):concat(name).
        system:isDirectory(path):ifFalse({
            relatives:indexOf(name):isNil:ifTrue({ extra:add(name) }) }) }) }).

; ---------------------------------------------------------------------------
; Doing it

dryRun:ifFalse({
    ensure:value(destination).
    made:do({ folder |
        ensure:value(destination:concat("/"):concat(folder)) }).
    copied:do({ relative |
        system:writeFile(destination:concat("/"):concat(relative),
                         system:readFile(source:concat("/"):concat(relative))) }) }).

; ---------------------------------------------------------------------------
; The report

"":display.
"{} -> {}{}":fill([source, destination,
    dryRun:ifElse({ "  (dry run)" }, { "" })]):display.
"{} files in {} directories":fill([relatives:size, folders:size:add(#1)]):display.
"":display.

report := { label, list |
    list:size:greaterThan(#0):ifTrue({
        "{} {}":fill([list:size:asString("4"), label]):display.
        list:first(#8):do({ name | "       ":concat(name):display }).
        list:size:greaterThan(#8):ifTrue({
            "       ... and {} more":fill([list:size:sub(#8)]):display }) }) }.

report:value("directories to make", made).
report:value("files to copy", copied).
report:value("already there", skipped).
report:value("in the destination and not the source", extra).

made:size:add(copied:size):equals(#0):ifTrue({
    "nothing to do":display }).

; ---------------------------------------------------------------------------
; What this wanted
;
; Four things, in the order they bit. The second is a defect this found; the
; others are gaps, and two of them are on the roadmap now.
;
;   1. **`makeDirectory` refuses a directory that is already there.** What a
;      script wants nine times in ten is "make sure this exists", and that is
;      two messages rather than one -- the `ensure` block at the top of this
;      file. See ROADMAP 6.25.
;
;   2. **`modifiedAt` answered whole seconds**, and this program could not do
;      its job with that. The test is "is the source newer than the copy?", and
;      within one second the answer was always no -- so a file edited just after
;      a run was never copied. The filesystem records nanoseconds and `time`
;      holds nanoseconds; only this message was rounding, in the middle of them.
;      Fixed. It is the reason a same-size edit is now noticed:
;
;          #1:print.        ; before: "nothing to do"
;          #1:print.        ; after:  1 file to copy
;
;   3. **A copy does not keep the original's time**, so the comparison here has
;      to be *newer than* rather than *the same as*. That works and is what
;      every mirroring tool does, and it has a corner: a source file replaced
;      with an **older** copy of itself is not noticed, because it is not newer.
;      A content comparison would catch it, at the price of reading both files.
;
;   4. **The executable bit is lost.** `-rwxr-xr-x` in the source is
;      `-rw-r--r--` in the destination, because a copy here is `readFile` then
;      `writeFile` and neither carries a mode. A backup of anything containing
;      scripts is not runnable, which for a language aimed at scripting an OS is
;      the sharpest of these. See ROADMAP 6.26.
;
; And one thing that is not a gap: **a whole-file copy is fine at this size and
; not at every size.** `readFile` answers the file as one string, so a mirror of
; something large holds it in memory twice. Nothing here needs streaming, and it
; is worth knowing where the edge is rather than discovering it.
