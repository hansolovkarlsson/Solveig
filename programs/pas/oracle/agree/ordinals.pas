program Ordinals(output);
{ Enumerations, subranges and the ordinal functions. An enumeration cannot be
  written -- the standard's write takes an integer, a real, a char, a boolean
  or a string, and a Colour is none of them -- so ord() does the showing. }
type Colour = (Red, Green, Blue);
     Digit  = 0 .. 9;
var c : Colour;
    d : Digit;
    ch : char;
    b : boolean;
begin
  c := Red;
  writeln(ord(c):4, ord(Green):4, ord(Blue):4);
  writeln(ord(succ(Red)):4, ord(pred(Blue)):4);
  writeln(succ(Red) = Green, pred(Blue) = Green);
  writeln(Red < Green, Blue > Green, Red <= Red);

  d := 7;
  writeln(d:4, succ(d):4, pred(d):4);
  writeln(sqr(d):5, abs(d):4, odd(d):7, odd(d + 1):7);

  ch := 'm';
  writeln(ord(ch):5);
  writeln(chr(65), chr(ord(ch) + 1), succ(ch), pred(ch));
  writeln(ch < 'z', ch > 'a');

  b := true;
  writeln(ord(b):3, ord(false):3);
  writeln(abs(-9):4, sqr(-3):4)
end.
