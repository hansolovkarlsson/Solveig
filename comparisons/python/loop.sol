; sum 1..N with a while loop -- integer arithmetic and loop overhead
n := #10000000.
i := #1.
sum := #0.
{ i:lessOrEqual(n) }:whileTrue({ sum := sum:add(i). i := i:inc }).
sum:print.
