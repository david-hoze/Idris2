module Main
-- Monotonicity test 7: case expression (fully annotated)
test : Bool -> String
test x = case not x of
  True => "yes"
  False => "no"
main : IO ()
main = putStrLn (test False)
