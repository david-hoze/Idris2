module Main
fst (x, _) = x
main : IO ()
main = printLn (fst (42, "hello"))
