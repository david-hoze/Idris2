module Main
%default total
safeAdd x y = x + y
main : IO ()
main = printLn (safeAdd (the Integer 3) 4)
