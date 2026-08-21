; Numbers are values, not objects on the heap: `a := #45` binds the name `a` to
; the integer 45, and nothing can mutate 45 itself.
; Run with:  ./bin/solas examples/numbers.sol && ./bin/solvm examples/numbers.sob

; There are two numeric types and the literal says which. '#' is a type tag, so
; `#45` is an integer and a bare `45` is a float.
#45:print.                       ; #45
45:print.                        ; 45
1.5:print.                       ; 1.5

; `print` shows the literal form -- the form that would read back as the same
; value -- which is why an integer prints with its '#'.
#45:display.                     ; 45   -- display writes the text instead

; Floats take exponents. '#' means exact, so an integer takes none.
1e3:print.                       ; 1000
1.5e-3:print.                    ; 0.0015

; ---------------------------------------------------------------------------
; Strictness: the two never mix on their own

#2:add(#3):print.                ; #5
2.5:add(0.5):print.              ; 3
;   #2:add(1.5).                 ; solvm: 'add' expects integer, got float

; There is no implicit coercion anywhere, so widening is something you write.
#7:asFloat:div(#2:asFloat):print.        ; 3.5

; Integer arithmetic traps rather than wrapping. The largest integer is
; 9223372036854775807, and asking for one more is an error, not a negative
; number:
;   #9223372036854775807:add(#1).        ; solvm: integer overflow in 'add'

; ---------------------------------------------------------------------------
; Division

; Integer division answers an integer -- a fractional result would let two
; integers leave their type silently, which is the coercion refused above.
#7:div(#2):print.                ; #3
#7:mod(#2):print.                ; #1

; It floors rather than truncates, so the two differ only on negatives. Floor is
; chosen for what it does to `mod`: a floored remainder always lands in [0, n)
; for positive n, which is what indexing and cyclic arithmetic want.
#-7:div(#2):print.               ; #-4
#-7:mod(#2):print.               ; #1    -- the divisor's sign, not the dividend's

; Division by zero splits along a line the language already had. There is no
; integer infinity, so integers trap:
;   #7:div(#0).                  ; solvm: division by zero in 'div'
; Floats have one, and float multiplication already overflows to it:
1.0:div(0.0):print.              ; infinity

; `infinity` and `nan` are globals, so those two print in a form that reads back.
infinity:print.                  ; infinity
0.0:div(0.0):print.              ; nan

; ---------------------------------------------------------------------------
; Narrowing says which way it goes

; There is no `asInteger` on a float, because most floats have no integer
; counterpart and there is no default worth remembering. Each of these says
; what it does:
2.7:floor:print.                 ; #2
2.7:ceiling:print.               ; #3
2.7:rounded:print.               ; #3
2.7:truncated:print.             ; #2
-2.7:floor:print.                ; #-3   -- floor goes down, truncate goes to zero
-2.7:truncated:print.            ; #-2

; Text goes both ways, and parsing is strict at both ends: the whole string must
; be a number and nothing else, so "12abc" and " 45" are errors.
"45":asInteger:print.            ; #45
"2.5":asFloat:print.             ; 2.5
#45:asString:print.              ; "45"  -- the text, with no '#'

; ---------------------------------------------------------------------------
; The rest of the arithmetic

#5:negated:print.                ; #-5
#-5:abs:print.                   ; #5
#3:mul(#4):sub(#2):print.        ; #10

; Comparison answers a boolean, and the ordering messages are spelled out.
#3:lessThan(#4):print.           ; true
#3:greaterOrEqual(#3):print.     ; true
#3:equals(#3):print.             ; true
#3:notEquals(#4):print.          ; true

; An integer and a float are never equal, since they are different types --
; there is no coercion here either.
#3:equals(3.0):print.            ; false

; ---------------------------------------------------------------------------
; A float prints as the shortest text that reads back as the same bits

1234567.0:print.                 ; 1234567
1.0:div(3.0):print.              ; 0.3333333333333333

; Any base from 2 to 36, and back again.
#255:asBase(#16):print.          ; "ff"
#255:asBase(#2):print.           ; "11111111"
"ff":asInteger(#16):print.       ; #255

; ---------------------------------------------------------------------------
; One more, one less
;
; `add(#1)` and `sub(#1)` are three in every ten arithmetic sends in this
; repository, which is what a language with no binary operators does to the
; commonest arithmetic there is. `inc` and `dec` are those two, shorter.

#5:inc:print.                    ; #6
#5:dec:print.                    ; #4

; They answer a new integer rather than changing the receiver, an integer being
; a value -- so the idiom is the assignment, and `count:inc` alone does nothing.
count := #10.
count := count:dec.
count:print.                     ; #9

; ---------------------------------------------------------------------------
; Bits
;
; An integer is a signed 64-bit two's-complement number, and these work on it as
; one. What they are for is the places a number is really a row of flags: a file
; mode, a UTF-8 byte, a set packed into a word.

#12:bitAnd(#10):print.           ; #8   -- 1100 and 1010
#12:bitOr(#10):print.            ; #14  -- 1100 or 1010
#12:bitXor(#10):print.           ; #6
#0:bitNot:print.                 ; #-1  -- every bit set

#1:shiftLeft(#10):print.         ; #1024
#1024:shiftRight(#3):print.      ; #128

; A shift right keeps the sign, because there is no unsigned integer here and a
; logical shift would turn every negative number into a huge positive one. That
; makes it agree exactly with `div` by a power of two, which is floored:
#0:sub(#7):shiftRight(#2):print. ; #-2
#0:sub(#7):div(#4):print.        ; #-2, the same

; A shift left refuses to lose the number, the way `mul` refuses to overflow.
;   #1:shiftLeft(#63)   ->  integer overflow in 'shiftLeft'
;   #1:shiftLeft(#64)   ->  'shiftLeft' wants #0 to #63, got #64

; Which is how a mode gets its executable bit without arithmetic:
;   system:setMode(path, system:modeOf(path):bitOr("111":asInteger(#8))).
