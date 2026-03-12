module Main
-- Monotonicity test 6: where clause with arithmetic (all annotated)
sumSq : Integer -> Integer -> Integer
sumSq a b = sq a + sq b
  where
    sq : Integer -> Integer
    sq x = x * x
main : IO ()
main = printLn (sumSq 3 4)
