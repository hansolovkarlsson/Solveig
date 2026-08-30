n = 2000000
parts = []
i = 1
while i <= n:
    parts.append(str(i))
    i = i + 1
s = ",".join(parts)
back = s.split(",")
print(len(s))
print(len(back))
