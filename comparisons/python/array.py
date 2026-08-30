n = 5000000
xs = []
i = 1
while i <= n:
    xs.append(i)
    i = i + 1
sum = 0
for x in xs:
    sum = sum + x
print(len(xs))
print(sum)
