; conformance: perform sends a name decided at run time, and respondsTo agrees with sending
; varies: machine
;
; Names are given as symbols, because a symbol is what a name is and comparing
; one is a pointer comparison. The six reflection messages read either side of
; the class line, which is what makes them the messages a program asks about
; itself with.

#45:perform('asString):display.
#2:perform('add, #3):print.
"ab":perform('concat, "cd"):display.
[#1, #2]:perform('at, #1):print.

#45:respondsTo('add):print.
#45:respondsTo('concat):print.
"ab":respondsTo('concat):print.

; respondsTo agrees with sending, so a class does not answer its instances'
; messages and an instance does not answer its class's.
array:respondsTo('of):print.
array:respondsTo('add):print.

#45:isKindOf(integer):print.
#45:isKindOf(float):print.
45:isKindOf(float):print.
"s":isKindOf(string):print.
[]:isKindOf(array):print.
'a:isKindOf(symbol):print.
nil:isKindOf(object):print.

; The name is a value like any other, so the send can be built.
name := "asString":asSymbol.
#7:perform(name):display.
