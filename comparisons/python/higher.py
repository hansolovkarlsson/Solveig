from functools import reduce
n = 4000000
xs = []
i = 1
while i <= n:
    xs.append(i)
    i = i + 1
ys = list(map(lambda x: x * 3, xs))
zs = list(filter(lambda x: x % 7 == 0, ys))
print(reduce(lambda a, b: a + b, zs, 0))
