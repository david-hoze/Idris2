module Main
-- Functions using operators should NOT be generalized
-- (types resolved from Num/Ord constraints)
add x y = x + y
main : IO ()
main = printLn (add 3 4)
