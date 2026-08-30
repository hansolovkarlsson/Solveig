; build an array of N and fold it -- allocation, growth, element access
n := #5000000.
xs := array:new.
i := #1.
{ i:lessOrEqual(n) }:whileTrue({ xs:add(i). i := i:inc }).
sum := #0.
xs:do({ x | sum := sum:add(x) }).
xs:size:print.
sum:print.
