; tools.sol -- doing a job by running other programs.
;
; Run with:  ./bin/solas programs/tools.sol && ./bin/solvm programs/tools.sob
;
; The sixth program here, and the first that does most of the job by asking
; something else to do it -- which is what a scripting
; language is for and what this one could not do until now.
;
; It reports on a directory: how many files, how big, what kind, and what the
; version control has to say if there is any. Every one of those is a program
; that already exists and is better than anything worth writing here.

@include "shell.sol".

where := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1) }, { "." }).

system:isDirectory(where):ifFalse({
    "no such directory: {}":fill([where]):display.
    system:exit(#1) }).

"":display.
"{}":fill([where]):display.
"":display.

; ---------------------------------------------------------------------------
; Asking, and believing the answer only when the status says to
;
; `capture` answers the status beside the output, and this is why: a command
; that is not installed answers #127 with nothing to say, and a command that
; failed answers its own code. Reading the output without looking at the status
; is how a script reports "0 files" when what happened is that `find` is missing.

count := { pattern | | result |
    result := shell:capture("find ":concat(where):concat(" -name '")
                                   :concat(pattern):concat("' -type f | wc -l")).
    result:at("status"):equals(#0):ifElse(
        ; `wc` pads its number with spaces, and `asInteger` is strict about the
        ; whole string being one -- rightly, since "12abc" is a mistake. `trim`
        ; is what stands between them, and this program is why it exists.
        { result:at("output"):trim:asInteger }, { #0 }) }.

; `system:run` with an array wherever a name from outside the program is
; involved, so that a directory called `; rm -rf ~` is a directory rather than a
; sentence. The shell above is given a pattern this file wrote.
sizes := system:capture(["du", "-sh", where]).
sizes:at("status"):equals(#0):ifElse(
    { "  size    {}":fill([sizes:at("output"):split("\t"):at(#1):trim]):display },
    { "  size    (du said {})":fill([sizes:at("status")]):display }).

"  .sol    {} files":fill([count:value("*.sol")]):display.
"  .c      {} files":fill([count:value("*.c")]):display.
"  .md     {} files":fill([count:value("*.md")]):display.

; ---------------------------------------------------------------------------
; Something that may not be there at all
;
; A tool a program would like but cannot count on. #127 is the shell's answer
; for "no such command", and treating it as an ordinary answer rather than an
; error is what lets a script degrade instead of falling over.

"":display.
version := system:capture(["git", "-C", where, "rev-parse", "--short", "HEAD"]).
version:at("status"):equals(#0):ifElse(
    { "  git     {}":fill([version:at("output"):trim]):display },
    { version:at("status"):equals(#127):ifElse(
        { "  git     (not installed)":display },
        { "  git     (not a repository)":display }) }).

; And the shell where the shell is the point: a pipeline, written here rather
; than assembled out of anything a caller supplied.
changed := shell:capture("git -C ":concat(where):concat(" status --porcelain 2>/dev/null | wc -l")).
changed:at("status"):equals(#0):ifTrue({
    "  changed {} files":fill([changed:at("output"):trim:asInteger]):display }).

; ---------------------------------------------------------------------------
; What this wanted
;
; **`trim`**, and it was wanted immediately. `wc -l` answers `"     100\n"` and
; `asInteger` refuses anything but a number, which is the right strictness and
; leaves every script that reads a tool's output with padding to take off first.
; Every command-line tool pads a number; every script that reads one trims it.
;
; What it did settle is which of the two to reach for. **An array wherever a
; name comes from outside the program** -- an argument, a file, a directory
; listing -- because an array is arguments and a command line is text somebody
; else's parser reads. **A string when the shell is the point**, and when the
; whole command was written by hand, as the pipeline above is.
