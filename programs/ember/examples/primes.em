# Primes below fifty, by trial division. Nested loops, and every operator.
let n = 2
while n < 50 do
  let d = 2
  let prime = 1
  while d * d <= n do
    if n % d == 0 then
      let prime = 0
    end
    let d = d + 1
  end
  if prime == 1 then
    print n
  end
  let n = n + 1
end
print "done"
