module Main
-- Where clause with multiple helpers, unannotated parent
sumSq xs = helper xs 0
  where
    sq x = x * x
    helper [] acc = acc
    helper (x :: rest) acc = helper rest (acc + sq x)
main : IO ()
main = printLn (sumSq [1, 2, 3])
