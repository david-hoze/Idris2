module Main
myApply f x = f x
main : IO ()
main = printLn (myApply (+ 1) (the Integer 41))
