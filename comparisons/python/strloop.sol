; walk a big string one character at a time -- work that stays in the language
line := "the quick brown fox jumps over the lazy dog, and then does it again. ".
s := "".
#17:repeat({ s := s:concat(s:concat(line)) }).
n := s:size.
count := #0.
i := #1.
{ i:lessOrEqual(n) }:whileTrue({ s:at(i):equals("o"):ifTrue({ count := count:inc }). i := i:inc }).
n:print.
count:print.
