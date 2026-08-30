n = 4000000
class Point:
    def __init__(self):
        self.x = 0
        self.y = 0
    def total(self):
        return self.x + self.y
sum = 0
i = 1
while i <= n:
    p = Point()
    p.x = i
    p.y = i * 2
    sum = sum + p.total()
    i = i + 1
print(sum)
