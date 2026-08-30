; join and split -- work that lives in the primitives
n := #2000000.
parts := array:new.
i := #1.
{ i:lessOrEqual(n) }:whileTrue({ parts:add(i:asString). i := i:inc }).
s := parts:join(",").
back := s:split(",").
s:size:print.
back:size:print.
