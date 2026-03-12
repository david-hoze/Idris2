module Main
-- Propagation test 3: chain of unannotated functions, typed at the root
inc : Integer -> Integer
inc x = x + 1
-- Both addTwo and addFour are unannotated
addTwo x = inc (inc x)
addFour x = addTwo (addTwo x)
main : IO ()
main = printLn (addFour 10)
