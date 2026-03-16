module Main
-- Ambiguous constructor (pair) resolved via constSolvable
myFst (x, _) = x
main : IO ()
main = printLn (myFst (42, "hello"))
