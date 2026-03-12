module Main
-- Error test 3: annotation conflicts with operation type
-- Integer annotation but uses string concatenation
add : Integer -> Integer -> Integer
add x y = x ++ y
main : IO ()
main = printLn (add 3 4)
