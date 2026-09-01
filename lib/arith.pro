; arith.pro -- Solveig's arithmetic, spelled the way arithmetic is spelled.
;
; A dialect file: directives and nothing else. Reached with
;
;     @use "arith.pro".
;
; and looked for beside the file using it, then in each -I directory, then in
; PROTO_PATH. Code does not live here -- a dialect provides syntax, and
; Solveig's own @include provides messages, so a dialect that wants both ships
; a .sol beside itself and says so.
;
; The precedences are the ones every language with these operators has agreed
; on, which is the only reason to prefer them: a file that declares 70 for `*`
; and 60 for `+` is not clever, it is unsurprising, and unsurprising is the
; whole job of a shared dialect.

@infix  *   70 mul.
@infix  /   70 div.
@infix  %   70 mod.
@infix  +   60 add.
@infix  -   60 sub.
@infix  <   40 lessThan.
@infix  >   40 greaterThan.
@infix  ==  40 equals.
@prefix ~      not.

; `and` and `or` take a *block* in Solveig, so that the right-hand side is not
; evaluated unless it is needed. An operator naming a message cannot say that --
; `@infix /\ 30 and` compiles to `a:and(b)` and is refused at run time -- so
; these name a template instead, and the template puts the block on.
;
; This is here because programs/ember wanted it and could not have it: six
; expressions in that compiler are written `(a == b):and({ ... })` by hand, and
; every one of them was a run-time failure first, `and` being a message a symbol
; does not understand.
;
; **`/\` and `\/` rather than `&&` and `||`**, which is a spelling and not a
; limitation -- both of C's lex perfectly well and a module that prefers them
; may declare them, as `lib/clike.pro` does. Half of the reason these were the
; pair has since expired: `||` could not be declared at all until the lexer took
; two bars as one token, so `&&` would have stood beside `\/` as two unrelated
; decisions. That is fixed, and the choice stayed, because what is left of the
; argument is the half that was never about the lexer -- this file is arithmetic
; and logic rather than C, and `/\` with `\/` is the notation that goes with
; saying so. C's pair lives in the file that is trying to look like C.
@infix  /\  30 => left:and({ right }).
@infix  \/  25 => left:or({ right }).
