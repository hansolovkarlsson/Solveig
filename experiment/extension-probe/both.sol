"-- two independent bundles, one machine --":print.
hash:fnv1a("solveig"):print.
gtk:probeDisplay:print.
n := #0.
gtk:every(#5, { n := @expr(n + #1). hash:fnv1a(n:asString):print. n:lessThan(#3) }).
gtk:run.
