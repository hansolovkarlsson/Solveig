; conformance: a block argument is checked when the message is sent, whatever the receiver
; varies: machine
; status: nonzero
;
; Checking on the way into the block instead would make the complaint depend on
; the data: `false:and(#45)` never reaches its argument, so a machine that looked
; later would accept this and answer false. That is the case, exactly: the
; receiver here settles the answer without the argument being wanted.

true:and({ true }):print.
false:and(#45):print.
