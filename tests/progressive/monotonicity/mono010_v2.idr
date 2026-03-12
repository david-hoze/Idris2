module Main
-- Monotonicity test 10: typeclass constraint (fully monomorphic)
compute : Integer -> Integer -> Integer
compute x y = (x + y) * (x - y)
main : IO ()
main = printLn (compute 5 3)
