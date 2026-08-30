from math import sqrt
n = 8000000
i = 1
sum = 0.0
while i <= n:
    x = float(i)
    sum = sum + sqrt(x) / (x + 1.0)
    i = i + 1
print("%.9f" % sum)
