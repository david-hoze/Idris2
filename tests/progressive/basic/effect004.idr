module Main
loop 0 = 0
loop n = loop (n - 1)
main : IO ()
main = printLn (loop (the Integer 10))
