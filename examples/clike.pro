; clike.pro -- a program that looks like C, in a language that is not.
;
; The header is two lines. Everything below is lib/clike.pro, and the only
; things here that C would not recognise are the `#` on an integer and the `.`
; where a `;` would be -- both of them the lexer's, and neither a dialect's to
; change. See the note at the top of lib/clike.pro.

@use "../lib/clike.pro".

n = #1.
total = #0.

while (n < #20) {
    if (n % #3 == #0 && n != #9) {
        total = total + n
    } else {
        total = total - #1
    }.
    n = n + #1
}.

total:print.                      ; #40

; A chain wants its braces, because the else branch is typed `block` and there
; is no way for a hole to say *a block or another use of me*. See lib/clike.pro.
if (total > #100) { "big":print }
else { if (total > #30) { "middling":print }
       else { "small":print } }.

; do-while runs the body before it asks.
i = #0.
do { i = i + #1 } while (i < #3).
i:print.                          ; #3

if (!(i == #0) && i <= #3) { "checked":print }.

; `||` is spelled the way C spells it. `|` on its own still belongs to a
; block, so the two live side by side in one line.
check = { n | | seen | seen = n > #100 || n == #40. seen }.
if (check:value(total)) { "or":print }.
