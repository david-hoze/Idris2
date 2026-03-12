module Main
-- Monotonicity test 1: simple arithmetic (unannotated)
-- add infers Num a => a -> a -> a; used at Integer
add x y = x + y
main : IO ()
main = printLn (add 3 4)
