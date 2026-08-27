program MissingSemicolon(output);

{ The commonest Pascal mistake there is: a statement before `else` that
  should not have a semicolon, or -- here -- one after `then` that should. }

var
  n : integer;

begin
  n := 1;
  if n > 0 then
    writeln('positive')
  n := n + 1;
  writeln(n)
end.
