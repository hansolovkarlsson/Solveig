program RealDefault(output);
{ DIVERGENCE: the default field width for a real.
  ISO leaves it to the implementation. fpc writes it in scientific notation;
  this writes the shortest text that reads back as the same number. Every
  program in agree/ writes its reals with an explicit width, which the
  standard does pin. }
var r : real;
begin
  r := 0.5;
  writeln(r)
end.
