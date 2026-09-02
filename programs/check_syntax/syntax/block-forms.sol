{ #1 }:value:print.
{ x | x }:value(#2):print.
{ x, y | x:add(y) }:value(#1, #2):print.
{ x | | t | t := x. t }:value(#3):print.
{ }:value:print.
