program Reading(input, output);
{ Standard input, read whole and then walked -- the machine has readLine and
  nothing that reads a character, so a program that reads at all draws the file
  in once at the start. A program that reads nothing is unchanged by any of it. }
var i, j, total : integer;
    r : real;
    c : char;
    lines : integer;
begin
  read(i, j);
  writeln(i:6, j:6, i + j:6);

  read(r);
  writeln(r:10:3);
  readln;

  read(c);
  writeln(c, eoln:7);
  readln;

  { A whole line of numbers, counted until the line marker. }
  total := 0;
  while not eoln do
    begin
      read(i);
      total := total + i
    end;
  writeln(total:6);
  readln;

  lines := 0;
  while not eof do
    begin
      readln;
      lines := lines + 1
    end;
  writeln(lines:6, eof:7)
end.
