program Biggest(output);
{ Not called MaxInt: a program's own name is an identifier in scope, so
  `program MaxInt` makes `maxint` mean the program and fpc asks for a `.`
  where the `)` is. The oracle found that on its first run. }
{ DIVERGENCE: integer is 64-bit here and 32-bit in fpc.
  PASCAL.md lists it; the standard leaves maxint to the implementation. }
begin
  writeln(maxint)
end.
