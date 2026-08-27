program Maths(output);
{ The eight required functions the machine already had under other names -- ln
  is log, arctan is atan -- and round, which is half away from nought in both.
  Every real is written with an explicit width, the default being the
  implementation's. }
const Places = 6;
var i, w : integer;
    x, total : real;
begin
  writeln(sqrt(2.0):12:8, exp(1.0):12:8, ln(1.0):12:8, arctan(1.0):12:8);
  writeln(sin(0.0):9:5, cos(0.0):9:5, sin(1.0):9:5, cos(1.0):9:5);
  writeln(sqrt(9):9:4, exp(0):9:4);

  writeln(round(2.5):4, round(-2.5):4, round(3.5):4, round(-3.5):4);
  writeln(trunc(2.7):4, trunc(-2.7):4, trunc(2.2):4, trunc(-2.2):4);
  writeln(abs(-7):4, abs(-7.5):9:2, sqr(6):4, sqr(1.5):9:3);

  { A field width worked out while running, which the standard allows and this
    refused until stage 8. }
  w := 8;
  x := 3.14159265;
  writeln(x:w:3);
  writeln(x:w + 4:Places);
  for i := 1 to 4 do write(i:i + 1);
  writeln;
  writeln('pad':w);

  total := 0.0;
  for i := 1 to 10 do total := total + sqrt(i);
  writeln(total:12:6)
end.
