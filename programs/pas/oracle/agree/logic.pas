program Logic(output);
{ Booleans, the six comparisons, and the operators that are jumps rather than
  sends because the machine's own take blocks. }
var a, b : integer;
    p, q : boolean;
begin
  a := 3; b := 7;
  writeln(a < b:7, a > b:7, a = b:7, a <> b:7, a <= b:7, a >= b:7);
  p := a < b;
  q := a > b;
  writeln(p and q:7, p or q:7);
  writeln(not p:7, not q:7);
  writeln((a < b) and (b < 10):7);
  writeln((a > b) or (b > 10):7);
  if p and not q then writeln('as expected')
end.
