module Main
myMap f [] = []
myMap f (x :: xs) = f x :: myMap f xs
main : IO ()
main = printLn (myMap (+ 10) [the Integer 1, 2, 3])
