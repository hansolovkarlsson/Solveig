; the same method five objects up the proto chain, behind four slots each
base := object:new.
base:of := { n | n:lessThan(#2):ifElse({ n }, { self:of(n:sub(#1)):add(self:of(n:sub(#2))) }) }.
a := base:new. a:p := #1. a:q := #2. a:r := #3. a:s := #4.
b := a:new.    b:p := #1. b:q := #2. b:r := #3. b:s := #4.
c := b:new.    c:p := #1. c:q := #2. c:r := #3. c:s := #4.
d := c:new.    d:p := #1. d:q := #2. d:r := #3. d:s := #4.
d:of(#32):print.
