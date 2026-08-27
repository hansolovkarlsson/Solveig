program Sets(output);
{ A set is an array of booleans, one per member of its base type -- not an
  array of bit-words, because 1 shiftLeft 63 overflows on a machine whose
  integers are signed. Membership is one index, which is what a program does
  most; everything else is a loop over the whole span. }
type Colour  = (Red, Green, Blue);
     Palette = set of Colour;
     Digits  = set of 0..9;
     Letters = set of 'a'..'e';
var p, q, r : Palette;
    d, e : Digits;
    l : Letters;
    c : Colour;
    i : integer;
    ch : char;
begin
  p := [Red, Blue];
  q := [Green];
  writeln(Red in p, Green in p, Green in q);

  r := p + q;
  for c := Red to Blue do write(c in r:7);
  writeln;

  r := p * [Blue, Green];
  for c := Red to Blue do write(c in r:7);
  writeln;

  r := p - [Red];
  for c := Red to Blue do write(c in r:7);
  writeln;

  writeln(p = [Red, Blue], p = q, p <> q);
  writeln([Red] <= p, p <= [Red], p >= [Blue], p >= [Green]);

  d := [1, 3, 5..7];
  for i := 0 to 9 do write(i in d:7);
  writeln;

  e := d + [0, 9] - [5];
  for i := 0 to 9 do write(i in e:7);
  writeln;

  d := [];
  writeln(1 in d, d = []);

  l := ['a', 'c'..'e'];
  for ch := 'a' to 'e' do write(ch in l:7);
  writeln;

  { A whole set assigned is a copy. }
  q := p;
  q := q - [Red];
  writeln(Red in p, Red in q)
end.
