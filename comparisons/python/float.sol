; float arithmetic in a loop -- sqrt, divide, add
n := #8000000.
i := #1.
sum := 0.
{ i:lessOrEqual(n) }:whileTrue({
  x := i:asFloat.
  sum := sum:add(x:sqrt:div(x:add(1.0))).
  i := i:inc }).
sum:asString("0.9"):display.
