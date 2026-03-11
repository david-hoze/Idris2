module Main
myFst (x, _) = x
main : IO ()
main = printLn (myFst (42, "hello"))
