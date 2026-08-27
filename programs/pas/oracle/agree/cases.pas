program Cases(output);
{ The selector is evaluated once, a constant list may have several entries, and
  an unmatched value falls through -- which fpc does and the standard calls an
  error. docs/PASCAL.md records it. }
type Colour = (Red, Green, Blue);
var i : integer;
    c : Colour;
    ch : char;
begin
  for i := 1 to 6 do
    case i of
      1, 2 : write('low ');
      3    : write('three ');
      4, 5 : write('mid ');
      6    : write('six ')
    end;
  writeln;

  c := Green;
  case c of
    Red   : writeln('red');
    Green : writeln('green');
    Blue  : writeln('blue')
  end;

  ch := 'b';
  case ch of
    'a' : writeln('an a');
    'b' : writeln('a b');
    'c' : writeln('a c')
  end;

  i := 99;
  case i of
    1 : writeln('one')
  end;
  writeln('fell through')
end.
