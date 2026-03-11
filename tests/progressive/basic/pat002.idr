module Main
isEmpty [] = True
isEmpty (_ :: _) = False
main : IO ()
main = printLn (isEmpty (the (List Nat) []))
