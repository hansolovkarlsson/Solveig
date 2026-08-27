program Consts(output);
{ Constants are worked out while compiling and never stored anywhere, and a
  type name is an alias for whatever it was given. }
const Size    = 10;
      Half    = 5;
      Pi      = 3.14159;
      Letter  = 'Q';
      Yes     = true;
type  Count   = integer;
      Tiny    = 1 .. 3;
var   n : Count;
      t : Tiny;
begin
  writeln(Size:4, Half:4, Size - Half:4);
  writeln(Pi:8:4);
  writeln(Letter);
  writeln(Yes:6);
  n := Size * Half;
  writeln(n:6);
  t := 2;
  writeln(t:3, succ(t):3);
  writeln(-Size:5)
end.
