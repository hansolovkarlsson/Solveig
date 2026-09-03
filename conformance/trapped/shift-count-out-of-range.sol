; conformance: a shift count outside #0 to #63 is refused rather than answering what the hardware does
; varies: machine
; status: nonzero
;
; And a shift left refuses to lose the number, the way mul refuses to overflow,
; rather than dropping the bits that go off the end.

#1:shiftLeft(#62):print.
#1:shiftLeft(#64):print.
