module Main
test x = case not x of
  True => "yes"
  False => "no"
main : IO ()
main = putStrLn (test False)
