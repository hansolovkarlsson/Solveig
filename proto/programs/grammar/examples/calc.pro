; calc.pro -- arithmetic with precedence, as four rules.
@use "../peg.pro".

@include "scan.sol".

digits := "0123456789".
blank  := " \t\n\r".

rules := dictionary:new.
src := nil.

rule 'expr is { | left |
    left := apply('term).
    { skip(blank). at("+") || at("-") }:whileTrue({ | op |
        op := next.
        left := if op == "+" then left + apply('term) else left - apply('term) }).
    left }.

rule 'term is { | left |
    left := apply('atom).
    { skip(blank). at("*") || at("/") }:whileTrue({ | op |
        op := next.
        left := if op == "*" then left * apply('atom) else left / apply('atom) }).
    left }.

rule 'atom is { | v |
    skip(blank).
    if at("(") then (eat("("). v := apply('expr). skip(blank). eat(")"). v)
    else take(digits):asInteger }.

run := { text |
    src := scan:on(text).
    apply('expr) }.

run:value("1 + 2 * 3"):print.
run:value("(1 + 2) * 3"):print.
run:value("100 / 5 - 3 * 4"):print.
run:value("2 * (3 + 4) - 5"):print.
