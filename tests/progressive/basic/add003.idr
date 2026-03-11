module Main
isPositive x = x > 0
main : IO ()
main = printLn (isPositive 5)
