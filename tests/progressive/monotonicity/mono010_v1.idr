module Main
-- Monotonicity test 10: typeclass constraint (explicitly constrained)
compute : Num a => Neg a => a -> a -> a
compute x y = (x + y) * (x - y)
main : IO ()
main = printLn (compute 5 3)
