program Loops(output);
{ for in both directions, repeat, and the guard that stops a for from stepping
  past the last value its type has. }
const N = 6;
var i, j, total : integer;
    ch : char;
begin
  total := 0;
  for i := 1 to N do total := total + i;
  writeln(total:6);

  for i := N downto 1 do write(i:3);
  writeln;

  for i := 1 to 3 do
    begin
      for j := 1 to 3 do write(i * j:4);
      writeln
    end;

  i := 0;
  repeat
    i := i + 1;
    write(i:3)
  until i >= 4;
  writeln;

  { An empty range runs no times: the test is before the body. }
  for i := 5 to 1 do writeln('never');
  writeln('empty range ran no times');

  for ch := 'a' to 'f' do write(ch);
  writeln;
  for ch := 'e' downto 'a' do write(ch);
  writeln
end.
