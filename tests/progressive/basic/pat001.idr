module Main
isZero Z = True
isZero (S _) = False
main : IO ()
main = printLn (isZero Z)
