program Sieve(output);
{ Eratosthenes with a set, which is the program sets were put in the language
  for -- and the one that shows what a set of booleans costs and buys: the
  membership test in the inner loop is one index, and the sieve is a loop over
  the whole span either way. }
const N = 200;
type Small = 1 .. N;
     Numbers = set of Small;
var candidates, primes : Numbers;
    i, j, count, biggest : integer;
    sum : integer;
begin
  candidates := [2 .. N];
  primes := [];
  count := 0;
  biggest := 0;

  for i := 2 to N do
    if i in candidates then
      begin
        primes := primes + [i];
        count := count + 1;
        biggest := i;
        j := i;
        while j <= N do
          begin
            candidates := candidates - [j];
            j := j + i
          end
      end;

  writeln(count:6, biggest:6);

  sum := 0;
  for i := 1 to N do
    if i in primes then sum := sum + i;
  writeln(sum:8);

  { The first twenty, ten to a line. }
  j := 0;
  for i := 1 to N do
    if i in primes then
      if j < 20 then
        begin
          write(i:5);
          j := j + 1;
          if j mod 10 = 0 then writeln
        end;

  writeln(2 in primes, 4 in primes, 199 in primes);
  writeln(primes <= candidates + primes, [2, 3] <= primes)
end.
