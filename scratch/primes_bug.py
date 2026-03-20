import sys

# Deliberately buggy: isPrime returns string instead of bool
def is_prime(n):
    if n < 2:
        return "no"
    j = 2
    while j * j <= n:
        if n % j == 0:
            return "no"
        j += 1
    return "yes"

def count_primes(n):
    count = 0
    for i in range(2, n + 1):
        if is_prime(i):  # Bug: "no" is truthy!
            count += 1
    return count

result = count_primes(100)
print(f"Primes up to 100: {result}")
print("Expected: 25")
