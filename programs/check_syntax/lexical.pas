program Lexical(output);

{ Two characters Pascal has no use for, on two different lines. Both are
  reported: a scan that stops at the first tells you least about the file you
  know least about. }

var
  n : integer;

begin
  n := 4 # 2;
  n := n $ 1;
  writeln(n)
end.
