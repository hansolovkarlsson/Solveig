; the method one step away: receiver's own slot, first in the list
f := object:new.
f:of := { n | n:lessThan(#2):ifElse({ n }, { self:of(n:sub(#1)):add(self:of(n:sub(#2))) }) }.
f:of(#32):print.
