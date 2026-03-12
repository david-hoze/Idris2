module Main
-- Propagation test 5: unannotated function with typed helper in where
process xs = helper xs 0
  where
    helper : List Integer -> Integer -> Integer
    helper [] acc = acc
    helper (x :: rest) acc = helper rest (acc + x)
main : IO ()
main = printLn (process [1, 2, 3, 4, 5])
