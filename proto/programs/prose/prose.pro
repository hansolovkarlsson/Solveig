; prose.pro -- a document, as a dialect.
;
; Every form here is a *step*: it appends to `doc` and answers nothing anybody
; uses, which is [docs/GRAMMAR.md]'s own test for the pattern shape. That is why
; none of them is a call, and why the trailing hole that caught programs/ember
; and programs/grammar cannot bite here -- each one ends in a literal.
;
; `doc` is free in every template, so it means the global of that name in
; whatever module used this file. Hygiene renames what a template *binds*, and
; these bind nothing.

@use "../../lib/control.pro".

@syntax title <t>       => doc:add(['title, t]).
@syntax section <t>     => doc:add(['section, t]).
@syntax para <t>        => doc:add(['para, t]).
@syntax item <t>        => doc:add(['item, t]).
@syntax quote <t>       => doc:add(['quote, t]).
@syntax rule            => doc:add(['rule, ""]).

; The one form that contains other content rather than text. A form is one
; expression and cannot hold a document, but it can hold a *block*, and the
; block's statements are content forms that append in order between the two
; markers. So structure arrives through Solveig's braces rather than through
; anything Proto declares.
@syntax indent <b: block>
    => (doc:add(['in, ""]). b:value. doc:add(['out, ""])).
