module Main
-- Monotonicity test 1: simple arithmetic (fully annotated)
add : Integer -> Integer -> Integer
add x y = x + y
main : IO ()
main = printLn (add 3 4)
