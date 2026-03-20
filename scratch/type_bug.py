def double(x):
    return x * 2

# Accidentally pass a string
print(double("5"))   # Prints "55" instead of 10 — silent wrong answer
print(double(5))     # Prints 10 — correct
