module Main
factorial 0 = 1
factorial n = n * factorial (n - 1)
main : IO ()
main = printLn (factorial 10)
