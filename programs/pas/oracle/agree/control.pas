program Control(output);
{ if, else, while, and the nesting of both. }
var i, total : integer;
begin
  total := 0;
  i := 1;
  while i <= 10 do
    begin
      if i mod 2 = 0 then
        total := total + i
      else
        total := total - i;
      i := i + 1
    end;
  writeln(total:6);

  i := 0;
  while i < 3 do
    begin
      if i = 0 then writeln('zero')
      else if i = 1 then writeln('one')
      else writeln('more');
      i := i + 1
    end
end.
