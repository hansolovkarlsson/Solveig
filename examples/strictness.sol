; strictness.sol -- what the language refuses, and why.
; Run with:  ./bin/solas examples/strictness.sol && ./bin/solvm examples/strictness.sob
;
; Solum would rather refuse than guess. Every refusal below is a real error
; message, shown as a comment because a program that made one would stop -- and
; beside each is what to write instead.
;
; This example ends by failing on purpose. The last section is there to show
; what a stack trace looks like, which nothing else can show you.

; ---------------------------------------------------------------------------
; Numbers do not coerce
;
; The literal says which type it is: '#' tags an integer, a bare number is a
; float. They never mix, in either direction.
;
;   #1:add(1.0)     ->  'add' expects integer, got float (no implicit coercion)
;   1.0:add(#1)     ->  'add' expects float, got integer (no implicit coercion)
;
; Crossing is something you write down.
#1:asFloat:add(1.0):print.               ; 2

; Going the other way there is no `asInteger` at all, deliberately: narrowing
; loses something, so it names which way it went and there is no default to
; misremember.
1.9:truncated:print.                     ; #1  -- towards zero
1.9:floor:print.                         ; #1  -- towards minus infinity
1.9:rounded:print.                       ; #2  -- half away from zero
1.9:ceiling:print.                       ; #2
1.5:truncated:add(#1):print.             ; #2

; ---------------------------------------------------------------------------
; Integer arithmetic traps rather than wrapping
;
;   #9223372036854775807:add(#1)  ->  integer overflow in 'add'
;   #1:div(#0)                    ->  division by zero in 'div'
;
; A float has somewhere to go instead, so it goes there.
1.0:div(0.0):print.                      ; infinity
0.0:div(0.0):print.                      ; nan

; ---------------------------------------------------------------------------
; Text does not join to numbers
;
;   "total: ":concat(#5)   ->  'concat' expects a string, got integer
;
; Rendering a value is a message, and there are two of them.
"total: ":concat(#5:asString):display.   ; total: 5
"total: {}":fill([#5]):display.          ; total: 5

; ---------------------------------------------------------------------------
; An index out of range is an error, not nil
;
;   [#1, #2]:at(#0)   ->  index #0 is out of bounds for an array of size 2
;   [#1, #2]:at(#3)   ->  index #3 is out of bounds for an array of size 2
;
; Indices are one-based, so #0 is caught rather than being the first element.
[#1, #2]:at(#1):print.                   ; #1
[#1, #2]:size:print.                     ; #2

; Absence is different from emptiness, and both are ordinary values.
[]:size:print.                           ; #0
"":size:print.                           ; #0
nil:equals(nil):print.                   ; true

; ---------------------------------------------------------------------------
; A condition has to be a boolean
;
; There is no truthiness. Nothing is "false enough".
;
;   #1:ifTrue({ #2 })            ->  integer does not understand 'ifTrue'
;   { #1 }:whileTrue({ nil })    ->  whileTrue expects the condition block to
;                                    answer a boolean, got integer
;
; The complaint is the same whether the compiler inlined the message or sent
; it, which is a rule the inlining is not allowed to break.
#1:lessThan(#2):ifTrue({ "yes":display }).            ; yes
#1:lessOrEqual(#1):ifTrue({ "and yes":display }).     ; and yes

; ---------------------------------------------------------------------------
; What a stack looks like
;
; Innermost first, and every frame names the line it was on. The program stops
; here: this is the last thing it does.

outer := { middle:value }.
middle := { inner:value }.
inner := { nil:frobnicate }.

"about to fail, on purpose:":display.
outer:value.
