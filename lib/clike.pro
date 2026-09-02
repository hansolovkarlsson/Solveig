; clike.pro -- C's operators and C's control flow, as far as they go.
;
;     @use "../lib/clike.pro".
;
;     n = #1.
;     while (n < #20) {
;         if (n % #3 == #0 && n != #9) { total = total + n }
;         else { total = total - #1 }.
;         n = n + #1
;     }.
;
; Standalone rather than built on arith.pro. It wanted a different set of
; logical operators once and, since 0.10.0, does not -- both files spell them
; `&&`, `||` and `!`. What is left is still a different set: `=` for assignment,
; `!=`, `<=` and `>=`, and control flow written with C's parentheses and braces
; rather than as words. A dialect need not stand on another, and this is the
; first one here that does not.
;
; ---------------------------------------------------------------------------
; What C has that this cannot, and why
;
; **`;` between statements.** `;` opens a comment, and the lexer is not
; something a dialect may change -- see docs/GRAMMAR.md. So statements end in
; `.`, and `for (i = #0; i < #9; i = i + #1)` cannot be written at all. That is
; the one loop C has and this does not.
;
; **`42` without the `#`.** A bare number is a *float* in Solveig and literal
; syntax belongs to the lexer too. `#42` is an integer here as it is everywhere.
;
; **`x++`, `a[i]`, `p->f`.** Proto has prefix and infix operators and no
; postfix ones, so none of these has a spelling. `->` alone would work as an
; ordinary infix if there were anything for it to mean.
;
; **`|` alone, for bitwise or.** `|` separates a block's parameters from its
; body and cannot be an operator character. `||` is two bars rather than a bar
; and is available, which is why `||` below is spelled the way C spells it;
; single `|` is not, and a dialect wanting the bitwise one writes `\` -- the
; bar that leans -- as `examples/utf8.pro` does.

@infix  =   10 => left := right.
@infix  ||  25 => left:or({ right }).
@infix  &&  30 => left:and({ right }).

@infix  ==  40 equals.
@infix  !=  40 => left:equals(right):not.
@infix  <   40 lessThan.
@infix  >   40 greaterThan.
@infix  <=  40 => left:greaterThan(right):not.
@infix  >=  40 => left:lessThan(right):not.

@infix  +   60 add.
@infix  -   60 sub.
@infix  *   70 mul.
@infix  /   70 div.
@infix  %   70 mod.

@prefix !      => operand:not.

; The condition is an ordinary expression and the parentheses around it are an
; ordinary group -- neither is part of the pattern, and neither has to be. What
; **is** part of the pattern is that the body is a `block`, which is what lets
; the two holes sit next to each other with no word between them: an expression
; stops at a `{`, so the split is exactly where a reader would put it.
@syntax if <c> <t: block>            => c:ifTrue(t).
@syntax while <c> <b: block>         => { c }:whileTrue(b).
@syntax do <b: block> while <c>      => (b:value. { c }:whileTrue(b)).

; The else branch is typed, and C's `else if` chain is the price.
;
; The first draft left it untyped so that `else if (...) { ... }` -- a use of
; this same form, and therefore an expression -- would chain the way C's does.
; That needs the template to wrap it, `ifElse` taking blocks, and `{ e }` around
; a branch that is *already* a block gives `{ { ... } }`: the outer block answers
; the inner one instead of running it, so the whole else branch silently does
; nothing. It compiles, it runs, and it gets the wrong answer -- examples/clike
; printed #54 where #40 was right.
;
; The two cases cannot both be served, because **a hole's kind is one choice and
; there is no alternation**: no way to say *a block, or another use of me*. So
; the branch is a block, `else { if (...) { ... } }` is how a chain is written,
; and a wrong `else` is refused rather than ignored.
@syntax if <c> <t: block> else <e: block> => c:ifElse(t, e).
