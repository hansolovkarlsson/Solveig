program Records(output);
{ Records: a field is an index worked out while compiling, and assigning a
  whole record copies it as deep as the type goes. }
type Colour = (Red, Green, Blue);
     Point  = record x, y : integer; tint : Colour end;
     Line   = record a, b : Point; label_ : char end;
     Bag    = record items : array [1..3] of integer; count : integer end;
var p, q : Point;
    l : Line;
    u, v : Bag;
    i : integer;
begin
  p.x := 3; p.y := 4; p.tint := Blue;
  writeln(p.x:4, p.y:4, ord(p.tint):4);

  q := p;
  q.x := 99;
  writeln(p.x:4, q.x:4);

  l.a := p;
  l.b.x := 11; l.b.y := 12; l.b.tint := Green;
  l.label_ := 'L';
  writeln(l.a.x:4, l.b.x:4, l.b.y:4, ord(l.b.tint):4, ' ', l.label_);

  for i := 1 to 3 do u.items[i] := i * 7;
  u.count := 3;
  v := u;
  v.items[2] := 0;
  writeln(u.items[2]:4, v.items[2]:4, u.count:4);

  with p do
    begin
      writeln(x:4, y:4);
      x := 7;
      y := 8
    end;
  writeln(p.x:4, p.y:4);

  with l.b do
    writeln(x:4, y:4)
end.
