module Main
duplicate x = (x, x)
main : IO ()
main = printLn (duplicate (the Integer 42))
