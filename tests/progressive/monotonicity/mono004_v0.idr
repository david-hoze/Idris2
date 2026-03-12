module Main
-- Monotonicity test 4: recursive numeric (unannotated)
-- fib uses literal patterns → defaults to Integer
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)
main : IO ()
main = printLn (fib 10)
