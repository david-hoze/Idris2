module Main
sumSq a b = sq a + sq b
  where sq x = x * x
main : IO ()
main = printLn (sumSq 3 4)
