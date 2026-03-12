module Main
-- Monotonicity test 7: case expression (unannotated)
test x = case not x of
  True => "yes"
  False => "no"
main : IO ()
main = putStrLn (test False)
