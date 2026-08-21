; A symbol is an interned name. Two symbols spelling the same thing are the same
; symbol, so comparing them is a pointer comparison rather than a walk over
; characters -- which is the whole reason to have them apart from strings.
; Run with:  ./bin/solas examples/symbols.sol && ./bin/solvm examples/symbols.sob

a := 'foo.
a:print.                     ; 'foo   -- the literal form
a:display.                   ; foo    -- the name
a:size:print.                ; #3

; Interning is not an optimisation you have to think about: a symbol built from
; a string at run time is the very same symbol as the one written in the source.
"foo":asSymbol:equals('foo):print.     ; true

; A symbol is a name, not text, so the two never compare equal.
'foo:equals("foo"):print.              ; false
'foo:asString:equals("foo"):print.     ; true

; Which makes them good tags.
state := 'running.
state:equals('running):ifElse({ "go" }, { "stop" }):display.    ; go

; They render inside collections like anything else.
['ready, 'running, 'halted]:print.
"the state is {}":fill([state]):display.

; ---------------------------------------------------------------------------
; Symbols have an order
;
; Interning makes `equals` on two symbols a pointer comparison, and it is
; exactly what makes their addresses say nothing about their order. So
; `lessThan` compares the text -- the one symbol operation that has to look at
; the characters.

'apple:lessThan('banana):print.          ; true
'a:lessOrEqual('a):print.                ; true

; Which is what a report needs: `sorted` with no block sends `lessThan`, so an
; array of symbols now sorts, and a tally kept under symbol keys has a stable
; order to print in.
['pear, 'apple, 'fig]:sorted:print.      ; ['apple, 'fig, 'pear]

; Strict about the other side, like every other comparison here.
;   'a:lessThan("a")   ->  'lessThan' expects symbol, got string (no implicit coercion)
