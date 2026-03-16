module Main
-- HOF calling annotated function
double : Integer -> Integer
double x = x * 2
myApply f x = f x
main : IO ()
main = printLn (myApply double 21)
