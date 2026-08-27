program Writes(output);
{ The field widths, which are the implementation's to choose and are fpc's
  here so that agreement is checkable at all. }
var i : integer;
    c : char;
    b : boolean;
begin
  i := 42; c := 'Z'; b := true;
  writeln(i);
  writeln(i:1, i:5, i:12);
  writeln(c);
  writeln(c:4);
  writeln(b);
  writeln(b:9);
  writeln('plain');
  writeln('padded':10);
  writeln('a', 'b', 'c');
  write('no'); write(' newline'); writeln(' until here');
  writeln
end.
