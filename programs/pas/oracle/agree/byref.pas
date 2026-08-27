program ByRef(output);
{ var parameters. Assigning to one assigns to the caller's variable, and it
  works through a chain -- the box goes over, and there is nothing to copy
  back. }
var g, h : integer;
    r : real;
    c : char;

procedure Double(var v : integer);
begin
  v := v * 2
end;

procedure Swap(var a, b : integer);
var t : integer;
begin
  t := a; a := b; b := t
end;

procedure Bump;
begin
  Double(g)
end;

{ A var parameter handed on to another var parameter: all three name one
  variable, and only the last one writes. }
procedure Outer(var x : integer);
begin
  Double(x)
end;

procedure Zero(var x : real; var y : char);
begin
  x := 0.0;
  y := 'z'
end;

function Total(a, b : integer) : integer;
begin
  Total := a + b
end;

begin
  g := 21;
  Double(g);
  writeln(g:6);

  Bump;
  writeln(g:6);

  g := 3; h := 8;
  Swap(g, h);
  writeln(g:4, h:4);

  g := 5;
  Outer(g);
  writeln(g:4);

  r := 1.5; c := 'a';
  Zero(r, c);
  writeln(r:8:2, ' ', c);

  { A value parameter is a copy: the caller's variable is untouched. }
  g := 7;
  writeln(Total(g, g):5, g:4)
end.
