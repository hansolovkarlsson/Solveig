; control.pro -- the shapes a program keeps writing out, as forms that read
; like statements rather than like calls.
;
; Uses arith.pro, because the conditions want their comparisons -- `unless`
; itself needs nothing from it, its template sending `:not` rather than
; spelling it. A dialect using another is ordinary, and a diamond is harmless:
; two dialects that both use arith meet it once.

@use "arith.pro".

; `if <c> then <a>` and `if <c> then <a> else <b>` are two forms under one word.
; Nothing has to say which is meant: after the second hole the short one has
; ended and the long one wants `else`, so the next token settles it.
@syntax if <c> then <a>             => c:ifTrue({ a }).
@syntax if <c> then <a> else <b>    => c:ifElse({ a }, { b }).

@syntax unless <c> then <a>         => c:not:ifTrue({ a }).

; `while` puts the braces on itself, so its holes take ordinary expressions and
; must not ask for a block -- `while i < n do (total := total + i)` is right, and
; a `<b: block>` here would refuse it. `repeat` below hands its hole straight to
; `repeat` without wrapping, so that one has to ask.
;
; Which is the whole rule: **a hole asks for what the template does not supply.**
@syntax while <t> do <b>            => { t }:whileTrue({ b }).
@syntax repeat <n> times <b: block> => n:repeat(b).

; A form needing somewhere to put a value, and needing both holes to be places
; -- which it can now say, so `swap #1 and u` is refused at the use rather than
; after expansion with a trail leading into this line.
;
; The `t` is renamed at every expansion, so `swap t and u` swaps them rather
; than losing them.
@syntax swap <a: place> and <b: place>
                                    => { | t | t := a. a := b. b := t }:value.
