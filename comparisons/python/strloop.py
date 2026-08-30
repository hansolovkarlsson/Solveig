line = "the quick brown fox jumps over the lazy dog, and then does it again. "
s = ""
for _ in range(17):
    s = s + s + line
n = len(s)
count = 0
i = 0
while i < n:
    if s[i] == "o":
        count = count + 1
    i = i + 1
print(n)
print(count)
