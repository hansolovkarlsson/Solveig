n := #0.
junk := nil.
gtk:stress.
gtk:every(#5, {
    n := @expr(n + #1).
    n:print.
    junk := [n, n, n]:collect({ x | x:asString }).
    n:lessThan(#5) }).
gtk:run.
"done":print.
