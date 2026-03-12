module Main
-- Propagation test 1: unannotated function calls typed function
double : Integer -> Integer
double x = x * 2
-- quadruple has no annotation; type propagates from double
quadruple x = double (double x)
main : IO ()
main = printLn (quadruple 5)
