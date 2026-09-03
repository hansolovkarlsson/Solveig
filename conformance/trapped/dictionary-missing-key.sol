; conformance: a dictionary key that is not there is an error, unless a default is given
; varies: machine
; status: nonzero
;
d := #["a" = #1].
d:at("a"):print.
d:at("z", #0):print.
d:includes("z"):print.
d:at("z"):print.
