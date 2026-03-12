module Main
-- Monotonicity test 6: where clause with arithmetic (outer annotated)
sumSq : Integer -> Integer -> Integer
sumSq a b = sq a + sq b
  where sq x = x * x
main : IO ()
main = printLn (sumSq 3 4)
