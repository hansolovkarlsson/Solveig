; conformance: a condition block that answers something other than a boolean stops the loop
; varies: machine
; status: nonzero
;
; It is whileTrue complaining about the answer rather than a receiver failing to
; understand a message, and it reads the same whether the blocks were written on
; the spot or reached through a name.

i := #0.
{ i:lessThan(#2) }:whileTrue({ i := i:add(#1) }).
i:print.
{ #1 }:whileTrue({ #2 }).
