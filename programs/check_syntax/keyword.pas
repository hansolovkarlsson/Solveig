program Keyword(output);

{ `end` is a reserved word -- not because this file says so, and not because
  check_syntax has a list of Pascal's keywords, but because pascal.bnf mentions
  "end" in a syntactic rule and every word-shaped literal in that half of a
  grammar is reserved against the token rule it would tokenise as. }

var
  n : integer;

begin
  end := 1;
  writeln(end)
end.
