module Main
def double x = x + x
quadruple : Integer -> Integer
quadruple x = double (double x)
main : IO ()
main = printLn (quadruple 5)
