; conformance: an integer is signed 64-bit two's complement, and a shift right keeps the sign
; varies: machine
;
; There is no unsigned integer here, so a logical shift would turn every
; negative number into a huge positive one. Keeping the sign makes a shift agree
; exactly with div by a power of two, which is floored.

#12:bitAnd(#10):print.
#12:bitOr(#10):print.
#12:bitXor(#10):print.
#0:bitNot:print.

#1:shiftLeft(#10):print.
#1024:shiftRight(#3):print.

#-7:shiftRight(#2):print.
#-7:div(#4):print.

; The count is #0 to #63, and #63 is reachable on a number that fits.
#0:shiftLeft(#63):print.
#-1:shiftRight(#63):print.
