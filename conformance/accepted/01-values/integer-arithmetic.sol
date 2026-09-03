; conformance: integer division floors, so the remainder takes the divisor's sign
; varies: machine
;
; `#-7:div(#2)` is `#-4` rather than `#-3`, and `#-7:mod(#2)` is therefore `#1`:
; the remainder stays in [0, n) for a positive n. A machine that truncates
; towards zero answers `#-3` and `#-1` and disagrees with its own shifts.

#7:div(#2):print.
#7:mod(#2):print.
#-7:div(#2):print.
#-7:mod(#2):print.
#7:div(#-2):print.
#7:mod(#-2):print.
#-7:div(#-2):print.
#-7:mod(#-2):print.

; inc and dec are add(#1) and sub(#1), and answer a new integer rather than
; changing the receiver.
n := #5.
n:inc:print.
n:dec:print.
n:print.

#-5:abs:print.
#5:negated:print.
