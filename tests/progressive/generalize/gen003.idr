module Main
myLength [] = 0
myLength (_ :: xs) = 1 + myLength xs
main : IO ()
main = do printLn (myLength [1, 2, 3])
          printLn (myLength ["a", "b"])
