; N inserts then N lookups, string keys
n := #1500000.
d := dictionary:new.
i := #1.
{ i:lessOrEqual(n) }:whileTrue({ d:atPut(i:asString, i). i := i:inc }).
sum := #0.
i := #1.
{ i:lessOrEqual(n) }:whileTrue({ sum := sum:add(d:at(i:asString)). i := i:inc }).
d:size:print.
sum:print.
