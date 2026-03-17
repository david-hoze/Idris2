module Main
def add x y = x + y
main : IO ()
main = printLn (add (the Integer 3) 4)
