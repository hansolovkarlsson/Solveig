; sexpr.pro -- nested lists, as three rules.
;
; A different grammar on the same toolkit: recursion through the table, and a
; repetition that is a loop because a grammar written as data has nowhere to put
; an EBNF `{ }`.
@use "../peg.pro".

@include "scan.sol".

letters := "abcdefghijklmnopqrstuvwxyz".
blank   := " \t\n\r".

rules := dictionary:new.
src := nil.

rule 'list is { | out |
    skip(blank).
    eat("(").
    out := array:new.
    { skip(blank). ~done /\ ~at(")") }:whileTrue({ out:add(apply('item)) }).
    skip(blank).
    eat(")").
    out }.

rule 'item is {
    skip(blank).
    if at("(") then apply('list) else apply('atom) }.

rule 'atom is {
    skip(blank).
    take(letters) }.

run := { text | src := scan:on(text). apply('list) }.

run:value("(a b c)"):print.
run:value("(a (b c) d)"):print.
run:value("((a) ((b)))"):print.
