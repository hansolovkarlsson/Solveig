program Arith(output);
{ Integer arithmetic, and the two operators the machine does not have.
  ISO's div truncates toward nought where SolVM's floors, and its mod is
  non-negative for a positive divisor, which is SolVM's already. }
var a, b, c : integer;
begin
  a := 17; b := 5; c := -17;
  writeln(a + b:6, a - b:6, a * b:6);
  writeln(a div b:6, a mod b:6);
  writeln(c div b:6, c mod b:6);
  writeln(-(a div b):6, -(a mod b):6);
  writeln((a + b) * (a - b):8);
  writeln(a - b - 2:6);
  writeln(2 * 3 + 4 * 5:6)
end.
