; plugins.sol -- running code this file never named.
; Run with:  make          (which compiles every example to bytecode)
;            ./bin/solvm examples/plugins.sob
;
; Run it from the top of the repository.

; `@include` needs a literal string. The file is found while the includer is
; being compiled, so a name holding the file's name has no value yet -- there is
; nothing to read it out of. That is not a restriction anybody chose; it follows
; from the directive happening before the program exists.
;
; `system:load` is a message. Its argument is an expression like any other, so a
; program can load a file whose name it worked out while running -- one it read
; from a configuration, took from `system:arguments`, or, as here, found by
; looking. That is the thing the two mechanisms do not share.

; Find the modules beside this file. Nothing here knows their names.
endsWith := { text, tail |
    text:size:greaterOrEqual(tail:size):and({
        text:copyFrom(text:size:sub(tail:size):add(#1), text:size):equals(tail) }) }.

found := system:filesIn("examples"):select({ f |
    f:indexOf("render-"):equals(#1):and({ endsWith:value(f, ".sob") }) }):sorted.

found:size:print.                       ; #2

; Load each one and use it straight away. Every module binds `renderer`, so the
; next load replaces the last -- which is the flat namespace doing exactly what
; it does for `@include`, and the reason to use each before moving on.
found:do({ name |
    system:load("examples/":concat(name)).
    renderer:name:concat(": "):concat(renderer:show("hello")):display }).
                                        ; loud: HELLO!
                                        ; plain: hello

; Loading is once-only, keyed by where the file lands on disk, so asking again
; runs nothing and says so. Two parts of a program may each load what they need
; without arranging between themselves who loads what.
system:load("examples/render-plain.sob"):print.     ; false

; And the modules drew export boundaries, so what they publish is all that is
; reachable -- a module loaded from a name nobody wrote down is exactly the case
; where you would rather not be able to reach into it.
renderer:slots:print.                   ; ['name, 'show]
