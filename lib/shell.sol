; shell.sol -- running a command through /bin/sh, when the shell is the point.
;
;     @include "shell.sol".
;
;     shell:run("ls *.sol | wc -l").
;     shell:capture("git rev-parse --short HEAD"):at("output").
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; **`system:run` takes an array on purpose, and this gives that up.** An array
; is a list of arguments and nothing in it is ever read as syntax: a file called
; `; rm -rf ~` is a name, because it is one string. A command line is text the
; shell parses, so the same name is a sentence -- and the difference is a
; deleted home directory rather than a lint warning.
;
; What the shell buys is pipes, globs, redirection and `&&`, which are real and
; are why this exists. The bargain is: **build the command out of things you
; wrote, not out of things a file or a user gave you.** If any part of it came
; from outside the program, use `system:run` with an array instead and let the
; strings stay strings.
;
; This file binds one name, `shell`, which is a common enough word that a
; program using it for something else will be warned about the collision when it
; compiles -- see ROADMAP 6.21.

shell := object:new.

; The command, run with its output going wherever this program's does. Answers
; the exit status: #0 for success, the command's own code for failure, #127 when
; there is nothing to run, and 128 plus the signal for one that was killed.
shell:run := { command | system:run(["/bin/sh", "-c", command]) }.

; The same, keeping what it wrote. Answers a dictionary of `"output"` and
; `"status"`, because a command's output is worth little without knowing whether
; it worked -- `grep` finding nothing is not `grep` failing.
shell:capture := { command | system:capture(["/bin/sh", "-c", command]) }.

; The output alone, for the common case of a command that cannot fail in any
; way the program means to notice. It raises when the command does fail, which
; is the difference between this and `capture`: one asks, the other insists.
shell:read := { command | | result |
    result := self:capture(command).
    result:at("status"):equals(#0):ifFalse({
        error:raise("`{}` failed with status {}"
            :fill([command, result:at("status")])) }).
    result:at("output") }.

; Trailing newlines removed, which is what a command's one-line answer wants:
; `git rev-parse HEAD` answers a hash and a newline, and the newline is the
; shell's way of ending a line rather than part of the hash.
shell:line := { command | | text |
    text := self:read(command).
    { text:size:greaterThan(#0)
        :and({ "\n":equals(text:copyFrom(text:size, text:size)) }) }
        :whileTrue({ text := text:copyFrom(#1, text:size:sub(#1)) }).
    text }.
