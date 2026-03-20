import sys, time

def count_primes(n):
    count = 0
    for i in range(2, n + 1):
        is_prime = True
        j = 2
        while j * j <= i:
            if i % j == 0:
                is_prime = False
                break
            j += 1
        if is_prime:
            count += 1
    return count

start = time.time()
n = int(sys.argv[1]) if len(sys.argv) > 1 else 100000
result = count_primes(n)
elapsed = time.time() - start
print(f"Primes up to {n}: {result}")
print(f"Time: {elapsed:.3f}s")
