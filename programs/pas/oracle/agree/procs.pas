program Procs(output);
{ Procedures and functions: value parameters, recursion, and a function that
  answers by assigning to its own name. }
var n : integer;

procedure Banner(c : char; count : integer);
var i : integer;
begin
  for i := 1 to count do write(c);
  writeln
end;

function Square(x : integer) : integer;
begin
  Square := x * x
end;

function Fact(k : integer) : integer;
begin
  if k <= 1 then Fact := 1
  else Fact := k * Fact(k - 1)
end;

function Gcd(a, b : integer) : integer;
begin
  if b = 0 then Gcd := a
  else Gcd := Gcd(b, a mod b)
end;

function Average(a, b : integer) : real;
begin
  Average := (a + b) / 2
end;

begin
  Banner('-', 12);
  writeln(Square(9):6);
  for n := 1 to 6 do write(Fact(n):8);
  writeln;
  writeln(Gcd(1071, 462):6);
  writeln(Average(3, 8):9:3);
  Banner('=', 12)
end.
