program Reals(output);
{ Every real is written with an explicit width and place count, which the
  standard pins exactly. The default width is implementation-defined and is
  in differ/. }
var r, s : real;
    i : integer;
begin
  r := 7 / 2;
  s := 1.5;
  i := 3;
  writeln(r:10:4);
  writeln(s:10:4);
  writeln(r + s:10:4);
  writeln(r * s:10:4);
  writeln(i + s:10:4);
  writeln(i / 4:10:4);
  writeln(-s:10:4);
  writeln(r - s:10:4)
end.
