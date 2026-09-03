; interp.pro -- the moves an interpreter makes, as forms.
;
; A dialect, so directives and nothing else. Three groups, and the grouping is
; the finding: a **character class** and a **token question** are applications,
; whose answers get used, so they take the call shape. A **move** -- storing a
; variable, advancing the counter, jumping -- reads as a step in a procedure,
; so it takes a pattern. `programs/ember`'s asm.pro drew that line first and
; said it divides by what the form *is* and not by taste; this file is the
; second draw and it fell the same way without the question being reopened.
;
; **Every form here but `fail` names a global that basic.pro declares** --
; `digits`, `letters`, `toks`, `tp`, `env`, `pc`, `running`. That is what
; asm.pro does with `out` and it is the same bargain: the dialect is not
; reusable, and it is not meant to be. A dialect is a file, and this one is
; this program's.

@use "../../lib/arith.pro".

; ------------------------------------------------------------ what a character is
;
; Written out three times in `programs/ember` as `isDigit:value(c)`, a block
; called through `value` because Solveig has no free functions. A form is the
; spelling the call always wanted -- and it costs the double evaluation that
; `programs/digest` found, `c` being named twice in each template. Harmless for
; a scan cursor's `peek` and recorded because it is now the third program to
; meet it.
@syntax isDigit(c)          => (c:notNil && digits:indexOf(c):notNil).
@syntax isLetter(c)         => (c:notNil && letters:indexOf(c):notNil).
@syntax isSpace(c)          => (c:notNil && " \t\r\n":indexOf(c):notNil).

; ------------------------------------------------------------ the token cursor
;
; `peek` and `take` differ by whether the cursor moves, which is the whole of
; what a parser asks of a position. `take` needs somewhere to put the token
; while it advances past it, so its template is a block sent `value` -- and the
; temporary is renamed at every expansion, so a `t` at the call site survives.
@syntax peek                => toks:at(tp).
@syntax take                => { | t | t := toks:at(tp). tp := tp + #1. t }:value.
@syntax step                => tp := tp + #1.

@syntax kindIs(k)           => (toks:at(tp):kind == k).
@syntax wordIs(w)           => (toks:at(tp):kind == 'name && toks:at(tp):text == w).
@syntax opIs(o)             => (toks:at(tp):kind == 'op && toks:at(tp):text == o).

; ------------------------------------------------------------ the environment
;
; A variable that was never assigned is `#0`, which is BASIC's rule and not
; Solveig's -- `at(key, default)` is what makes it one message rather than a
; question and a branch.
@syntax fetch(n)            => env:at(n, #0).
@syntax store <n> as <v>    => env:atPut(n, v).

; ------------------------------------------------------------ the counter
;
; The three things a statement can do to the program counter, and the reason
; this program exists: nothing before it had a counter that could go backwards.
@syntax fallThrough         => pc := pc + #1.
@syntax jump to <n>         => pc := n.
@syntax halt                => running := false.

; ------------------------------------------------------------ saying so
@syntax fail <why>          => (("basic: {}":fill([why])):display. system:exit(#65)).
