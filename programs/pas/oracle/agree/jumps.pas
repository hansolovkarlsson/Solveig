program Jumps(output);
{ label and goto, forwards and backwards. A backward jump is OP_LOOP and a
  forward one is OP_JUMP with its offset filled in when the label arrives. }
label 1, 99;
var i : integer;
begin
  i := 0;
1:
  i := i + 1;
  write(i:3);
  if i < 4 then goto 1;
  writeln;

  i := 1;
  goto 99;
  i := 999;
99:
  writeln(i:4);
  writeln('done')
end.
