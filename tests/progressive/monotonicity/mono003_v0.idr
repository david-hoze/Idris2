module Main
-- Monotonicity test 3: list operations (unannotated)
myLength [] = 0
myLength (_ :: xs) = 1 + myLength xs
main : IO ()
main = printLn (myLength [1, 2, 3])
