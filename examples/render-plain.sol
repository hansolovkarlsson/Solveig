; render-plain.sol -- a module, loaded by plugins.sol rather than included.
;
; It binds one name and prints nothing, so it is worth nothing on its own and
; runs cleanly anyway. Compiled like any other file; what makes it a module is
; only that something else loads it.
renderer := object:new.
renderer:name := "plain".
renderer:show := { text | text }.
renderer:exports(['name, 'show]).
