; the same loop, but the counter and the total are block temporaries
; rather than globals -- an array index per access instead of a hash lookup
{ | n, i, sum |
  n := #10000000. i := #1. sum := #0.
  { i:lessOrEqual(n) }:whileTrue({ sum := sum:add(i). i := i:inc }).
  sum:print }:value.
