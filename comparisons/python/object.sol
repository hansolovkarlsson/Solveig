; make an object per pass and send it a message -- allocation, slots, dispatch
n := #4000000.
point := object:new.
point:x := #0.
point:y := #0.
point:total := { self:x:add(self:y) }.
sum := #0.
i := #1.
{ i:lessOrEqual(n) }:whileTrue({
  p := point:new.
  p:x := i.
  p:y := i:mul(#2).
  sum := sum:add(p:total).
  i := i:inc }).
sum:print.
