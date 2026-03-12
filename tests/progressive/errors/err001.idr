module Main
-- Error test 1: annotation conflicts with operator usage
-- Annotated as String but uses (+) which needs Num
add : String -> String -> String
add x y = x + y
main : IO ()
main = printLn (add 3 4)
