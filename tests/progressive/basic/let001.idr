module Main
addDouble x y = let s = x + y in s + s
main : IO ()
main = printLn (addDouble 10 11)
