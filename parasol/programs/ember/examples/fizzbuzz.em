# fizzbuzz -- the first program written in Ember.
let n = 1
while n <= 20 do
  if n % 15 == 0 then
    print "FizzBuzz"
  else
    if n % 3 == 0 then
      print "Fizz"
    else
      if n % 5 == 0 then
        print "Buzz"
      else
        print n
      end
    end
  end
  let n = n + 1
end
