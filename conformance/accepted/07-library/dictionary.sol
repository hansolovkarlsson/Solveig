; conformance: a dictionary is found by hashing, and its keys come back in no order worth relying on
; varies: machine
;
; Which is why every case here sorts them before printing. A corpus that printed
; `keys` as it found them would be scoring one implementation's hash function,
; and the reference says in as many words that there is no order to score.

d := dictionary:new.
d:atPut("b", #2):print.
d:atPut("a", #1).
d:atPut("c", #3).
d:size:print.

d:at("a"):print.
d:at("z", #0):print.
d:includes("a"):print.
d:includes("z"):print.

d:keys:sorted:print.
d:values:sorted:print.

d:remove("b"):print.
d:size:print.
d:includes("b"):print.

; A literal is sugar for dictionary:of, key then value.
e := #["x" = #1, "y" = #2].
e:keys:sorted:print.
dictionary:of("x", #1, "y", #2):keys:sorted:print.

; do runs once per value, keysAndValuesDo takes both. Sorted keys make the walk
; an answer rather than an accident.
total := #0.
e:do({ v | total := total:add(v) }).
total:print.

e:keys:sorted:do({ k | "{}={}":fill([k, e:at(k)]):display }).
