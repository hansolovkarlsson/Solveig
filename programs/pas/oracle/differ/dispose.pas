program Disposed(output);
{ DIVERGENCE: dispose frees nothing, SolVM being garbage-collected. The
  standard calls the value of a disposed pointer undefined, so fpc is entitled
  to whatever it does and this is entitled to hand the object back. It is the
  safe direction, and it is a difference. }
type Link = ^Node;
     Node = record value : integer end;
var p : Link;
begin
  new(p);
  p^.value := 42;
  dispose(p);
  writeln(p^.value)
end.
