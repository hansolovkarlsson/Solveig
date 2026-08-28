; `@expr(...)` writes an expression the way it is written on paper, and lowers
; it to the sends it reads as. Nothing else in the language has operators.
; Run with:  ./bin/solas examples/operators.sol && ./bin/solvm examples/operators.sob

; The problem it is for. A send chain reads strictly left to right, and
; arithmetic precedence does not -- so the outermost operation of a nested
; formula ends up in the middle of the line, and checking it against the page it
; was copied from is the hard part.
a := 5.0.
b := 9.0.

a:pow(2.0):add(3:mul(a:div(2.0):sin:add(b:sqrt))):print.
;                                                          ; 35.79541643231187
@expr( a^2 + 3 * (sin(a/2) + sqrt(b)) ):print.             ; 35.79541643231187

; Those two lines are the same program. Not the same answer -- the same
; *bytecode*: every operator lowers to the send it reads as, and a test compares
; the bytes rather than the results.
;
;     +  add        *  mul        ^  pow        =   equals    &  and
;     -  sub        /  div        ~  not        <>  notEquals |  or
;                                 -  negated    <  <=  >  >=
;
; And `sin(x)` is `x:sin` -- prefix application is a send to its argument, which
; is the whole rule. It takes exactly one, so `float:atan2(y, x)` is written out.

; ---------------------------------------------------------------------------
; Precedence, which is the whole reason it exists

@expr( 1 + 2 * 3 ):print.        ; 7
@expr( (1 + 2) * 3 ):print.      ; 9

; `-` and `/` group to the left, the way they read.
@expr( 10 - 3 - 2 ):print.       ; 5
@expr( 100 / 10 / 2 ):print.     ; 5

; `^` groups to the right, and binds tighter than a minus in front of it.
@expr( 2^3^2 ):print.            ; 512   -- 2^(3^2), not (2^3)^2
@expr( -2^2 ):print.             ; -4    -- -(2^2)
@expr( 2^-2 ):print.             ; 0.25

; ---------------------------------------------------------------------------
; A term is an ordinary Solum expression

; Anything that is an expression outside a region is one inside it, sends and
; all -- so the prefix form is a convenience and never the only way in.
@expr( sqrt(b) + 1 ):print.              ; 4
@expr( b:sqrt + 1 ):print.               ; 4   -- the same bytes
@expr( (a/5):floor + #1 ):print.         ; #2
@expr( [1.0, 2.0]:at(#2) + 1 ):print.    ; 3

; The region covers what is nested inside it too -- an argument, an array, a
; group, a block body -- so a minus means the same thing everywhere within.
@expr( [1.0, -3.0, 2.5]:inject(0.0, { t, e | t + e }) ):print.    ; 0.5

; `sin(x)` is a *send*, not a block call. A global holding a block is called
; with `value`, and getting that wrong says so rather than doing the other
; thing.
;   f := { x | x:mul(x) }.
;   @expr( f(3) ).               ; solvm: float does not understand 'f'

; ---------------------------------------------------------------------------
; It hides nothing about the two numeric types

; The notation is the send, so it is the same refusal. There is still no
; coercion, and `pow` is still float-only.
@expr( #2 + #3 * #4 ):print.     ; #14
;   @expr( #1 + 1.0 ).           ; solvm: 'add' expects integer, got float
;   @expr( #4^#2 ).              ; solvm: integer does not understand 'pow'

; ---------------------------------------------------------------------------
; Comparison, and it does not chain

@expr( a < b ):print.            ; true
@expr( a >= b ):print.           ; false
@expr( a <> b ):print.           ; true
@expr( a + 1 < b * 2 ):print.    ; true

; `a < b < c` would compare a boolean to `c`, so it is refused while compiling
; rather than left to fail while running:
;   @expr( 1 < 2 < 3 ).          ; solas: comparisons do not chain

; ---------------------------------------------------------------------------
; And the logic, which stops early

; `&` and `|` are `and` and `or`, which take a block so they can stop early --
; so these are the two operators whose right-hand side is compiled behind the
; jump rather than beside them. The bytes are still the block form's bytes.
@expr( a < b & b < 10.0 ):print. ; true
@expr( a > b | b > 1.0 ):print.  ; true

; `~` is `not`, and it is looser than a comparison: this is `~(a = b)`, which
; is what the words say. C would have bound it tightest and read the other.
@expr( ~a = b ):print.           ; true

; `|` is the one operator the language already used, for a block's parameters.
; They are taken before a body is, so a block inside a region still reads the
; way it does outside one.
@expr( [1.0, 2.0]:inject(0.0, { t, e | t + e }) ):print.    ; 3

; ---------------------------------------------------------------------------
; And outside a region there are no operators at all, which is the language's
; own rule rather than an omission:
;   b := a + 2.                  ; solas: this is written as a send here
