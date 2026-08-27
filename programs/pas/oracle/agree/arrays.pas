program Arrays(output);
{ Arrays: any ordinal index, any lower bound, and more than one dimension.
  Solum counts from one and Pascal from wherever it was told, so the difference
  is folded in while compiling and costs nothing at run time. }
type Colour = (Red, Green, Blue);
     Row    = array [1..4] of integer;
     Offset = array [5..8] of integer;
     Grid   = array [1..3, 1..4] of integer;
     Tally  = array [Colour] of integer;
     Chars  = array ['a'..'e'] of char;
     Flags  = array [boolean] of integer;
var i, j : integer;
    r : Row;
    o : Offset;
    g : Grid;
    t : Tally;
    c : Chars;
    f : Flags;
    ch : char;
begin
  for i := 1 to 4 do r[i] := i * i;
  for i := 1 to 4 do write(r[i]:4);
  writeln;

  for i := 5 to 8 do o[i] := i * 10;
  for i := 5 to 8 do write(o[i]:5);
  writeln;

  for i := 1 to 3 do
    for j := 1 to 4 do g[i, j] := i * 10 + j;
  for i := 1 to 3 do
    begin
      for j := 1 to 4 do write(g[i][j]:5);
      writeln
    end;

  t[Red] := 1; t[Green] := 2; t[Blue] := 3;
  writeln(t[Red]:4, t[Green]:4, t[Blue]:4);

  for ch := 'a' to 'e' do c[ch] := ch;
  for ch := 'e' downto 'a' do write(c[ch]);
  writeln;

  f[false] := 10; f[true] := 20;
  writeln(f[false]:4, f[true]:4);

  { A whole array assigned is a copy, not a second name. }
  o[5] := 0;
  writeln(o[5]:4)
end.
