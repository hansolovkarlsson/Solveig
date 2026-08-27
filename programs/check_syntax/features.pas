program Features(input, output);

{ Not a program that does anything -- a program that uses as much of pascal.bnf
  as will fit on a page, so that a change to the grammar has something to fail
  against. Labels and goto, a packed array, a pointer type, a record, an
  enumeration, a set with a subrange in it, a forward declaration and the
  heading that repeats only the name, a recursive procedure, a case with two
  labels on one arm, and write-parameters with field widths. }
label 1, 99;
const
  Max = 100;
  Pi  = 3.14159;
  Neg = -1;
type
  Str = packed array [1 .. 80] of char;
  Tree = ^Node;
  Node = record
           key  : integer;
           left, right : Tree
         end;
  Grade = (A, B, C);
  Digits = set of 0 .. 9;
var
  s : Str;
  t : Tree;
  d : Digits;
  g : Grade;
  x, y : real;

function Area(r : real) : real; forward;

procedure Walk(t : Tree; var count : integer);
begin
  if t <> nil then
    begin
      Walk(t^.left, count);
      count := count + 1;
      Walk(t^.right, count)
    end
end;

function Area;
begin
  Area := Pi * r * r
end;

begin
  x := 1.5e2;
  y := Area(x);
  d := [0, 2, 4 .. 6];
  g := B;
  goto 1;
1:
  case g of
    A : writeln('a');
    B, C : writeln('b or c')
  end;
  if not (3 in d) then goto 99;
  writeln(x:8:2, y:8:2);
99:
end.
