module Main
-- Monotonicity: myApply with explicit type annotation
myApply : (a -> b) -> a -> b
myApply f x = f x
main : IO ()
main = printLn (myApply (+ 1) (the Integer 41))
