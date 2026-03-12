module Main
-- Monotonicity test 6: where clause with arithmetic (unannotated)
sumSq a b = sq a + sq b
  where sq x = x * x
main : IO ()
main = printLn (sumSq 3 4)
