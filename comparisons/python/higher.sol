; collect, select, inject -- a block called once per element
n := #4000000.
xs := array:new.
i := #1.
{ i:lessOrEqual(n) }:whileTrue({ xs:add(i). i := i:inc }).
ys := xs:collect({ x | x:mul(#3) }).
zs := ys:select({ x | x:mod(#7):equals(#0) }).
zs:inject(#0, { a, b | a:add(b) }):print.
