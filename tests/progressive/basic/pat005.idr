module Main
myLength [] = 0
myLength (_ :: xs) = 1 + myLength xs
main : IO ()
main = printLn (myLength [1, 2, 3, 4, 5])
