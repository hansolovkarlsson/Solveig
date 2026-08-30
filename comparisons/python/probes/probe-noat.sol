; the strloop loop with the s:at(i) taken out -- what the loop alone costs
n := #9043899.
c := "x".
count := #0.
i := #1.
{ i:lessOrEqual(n) }:whileTrue({ c:equals("o"):ifTrue({ count := count:inc }). i := i:inc }).
count:print.
