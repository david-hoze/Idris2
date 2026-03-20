module Main

double : Integer -> Integer
double x = x * 2

-- Accidentally pass a string — caught at compile time
main : IO ()
main = putStrLn (show (double "5"))
