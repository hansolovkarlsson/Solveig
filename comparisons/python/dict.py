n = 1500000
d = {}
i = 1
while i <= n:
    d[str(i)] = i
    i = i + 1
sum = 0
i = 1
while i <= n:
    sum = sum + d[str(i)]
    i = i + 1
print(len(d))
print(sum)
