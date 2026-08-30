class F:
    def of(self, n):
        return n if n < 2 else self.of(n - 1) + self.of(n - 2)
print(F().of(34))
