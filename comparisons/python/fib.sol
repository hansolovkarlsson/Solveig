; recursive fib -- method dispatch and frame cost
f := object:new.
f:of := { n | n:lessThan(#2):ifElse({ n }, { self:of(n:sub(#1)):add(self:of(n:sub(#2))) }) }.
f:of(#34):print.
