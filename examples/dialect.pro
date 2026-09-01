; dialect.pro -- a module that declares nothing and reads like a language.
;
; The header is two lines. Every operator, every precedence, and every one of
; the four statement forms below comes out of lib/, and lib/control.pro in turn
; uses lib/arith.pro -- two deep, and the diamond costs nothing because arith is
; read once.
;
; Nothing in the body is Proto's. `if`, `then`, `else`, `while`, `do` are
; words this program's dialect happens to use, and they are words anywhere else:
; a file that does not use control.pro may call a variable `then`, and so may
; this one.

@language solveig.
@use "../lib/control.pro".

n := #7.

if n > #10 then "over ten":print else "not over ten":print.

unless n % #2 == #0 then "and it is odd":print.

i := #1.
total := #0.
while i < n do (total := total + i. i := i + #1).
total:print.                     ; #21, being 1+2+3+4+5+6

; `repeat` hands the block straight to Solveig's own `repeat`, so the braces
; here are the caller's job -- and the form says so, with <b: block>.
repeat #3 times { "tick":display }.    ; tick, three times, a line each

a := "left".
b := "right".
swap a and b.
a:print.                         ; "right"
b:print.                         ; "left"

; `swap` says both its holes are places, so `swap #1 and b` is refused where it
; is written rather than after expansion, and the message names the form and the
; dialect file the hole was declared in:
;
;   error: 'swap' wants a place here, and this is an integer
;   note: 'a' is declared to want a place
