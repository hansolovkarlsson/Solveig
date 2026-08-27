program Unclosed(output);

{ A `begin` with no `end`. The report is at the end of the file, because that
  is where the file stopped being a program -- there is nothing wrong with any
  line before it. }

var
  i : integer;

begin
  for i := 1 to 10 do
    begin
      writeln(i);
      writeln(i * i)
end.
