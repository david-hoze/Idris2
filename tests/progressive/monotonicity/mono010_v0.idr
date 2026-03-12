module Main
-- Monotonicity test 10: typeclass constraint with multiple ops (unannotated)
-- Tests that inferred Num constraint produces same runtime as explicit
compute x y = (x + y) * (x - y)
main : IO ()
main = printLn (compute 5 3)
