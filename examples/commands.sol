; commands.sol -- running a command through the shell, when the shell is the
; point.
;
; Called `commands.sol` and not `shell.sol` because a file that includes a
; library of its own name finds itself and the include does nothing --
; [6.22](../docs/COMPLETED.md#622-a-file-that-includes-a-library-of-its-own-name-silently-does-nothing--done),
; the same reason [manifest.sol](../programs/manifest.sol) is not `json.sol`.
;
; **`system:run` takes an array and this gives that up.** An array is a list of
; arguments and nothing in it is ever read as syntax; a command line is text the
; shell parses. What that buys is pipes, globs and `&&`, and the bargain is to
; build the command out of things you wrote rather than things a file or a user
; gave you. The library's own header makes the argument in full.
;
; Everything below uses `echo`, `wc` and `true`, which say the same thing on
; every system this is built on -- which is what makes them claims and not
; guesses.

@include "shell.sol".

; ---------------------------------------------------------------------------
; The output, when the command cannot sensibly fail

shell:read("echo hello"):print.            ; "hello\n"

; `line` is the same with the trailing newline off, which is what a command's
; one-line answer wants.
shell:line("echo hello"):print.            ; "hello"
shell:line("printf 'a\nb\n'"):print.       ; "a\nb"

; ---------------------------------------------------------------------------
; A pipe, which is the whole reason this library exists

shell:line("echo one two three | wc -w"):trim:print.       ; "3"

; ---------------------------------------------------------------------------
; The status, when a command failing is an answer rather than a fault
;
; `grep` finding nothing is not `grep` failing, so `capture` hands back both and
; lets the caller decide which it meant.

ok := shell:capture("true").
ok:at("status"):print.                     ; #0
ok:at("output"):print.                     ; ""

no := shell:capture("echo out; exit 3").
no:at("status"):print.                     ; #3
no:at("output"):print.                     ; "out\n"

; ---------------------------------------------------------------------------
; `read` insists where `capture` asks

complaint := { shell:read("exit 4") }:onError({ e | e:message }).
complaint:display.               ; `exit 4` failed with status 4

; ---------------------------------------------------------------------------
; `run` answers the status and lets the output go where it was going

shell:run("true"):print.                   ; #0
shell:run("exit 7"):print.                 ; #7
