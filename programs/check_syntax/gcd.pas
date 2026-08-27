program GCD(input, output);

{ Greatest common divisor, and a few things besides -- this file exists to
  use as much of pascal.bnf as one readable program can: a record, an array,
  a subrange, an enumeration, a nested procedure, a function, a case, a for,
  a while, a repeat, a with, and a set. }

const
  Limit = 20;
  Title = 'greatest common divisor';

type
  Colour   = (Red, Green, Blue);
  Small    = 1 .. Limit;
  Vector   = array [Small] of integer;
  Point    = record
               x, y : integer;
               tint : Colour
             end;

var
  a, b   : integer;
  i      : Small;
  table  : Vector;
  origin : Point;
  seen   : set of Colour;

function GreatestCommonDivisor(u, v : integer) : integer;
var
  t : integer;
begin
  while v <> 0 do
    begin
      t := u mod v;
      u := v;
      v := t
    end;
  GreatestCommonDivisor := u
end;

procedure Describe(c : Colour);
begin
  case c of
    Red   : writeln('red');
    Green : writeln('green');
    Blue  : writeln('blue')
  end
end;

procedure Fill(var v : Vector);
var
  k : Small;
begin
  for k := 1 to Limit do
    v[k] := k * k
end;

begin
  writeln(Title);
  Fill(table);

  origin.x := 3;
  origin.y := 4;
  origin.tint := Blue;

  with origin do
    writeln(x:4, y:4);

  seen := [Red, Blue];
  if Green in seen then
    writeln('green was seen')
  else
    writeln('green was not seen');

  Describe(origin.tint);

  a := 1071;
  b := 462;
  writeln(GreatestCommonDivisor(a, b):6);

  i := 1;
  repeat
    write(table[i]:4);
    i := i + 1
  until i > 10;
  writeln;

  if (a > 0) and (b > 0) then
    writeln('both positive':20)
end.
