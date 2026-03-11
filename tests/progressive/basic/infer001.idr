module Main
add x y = x + y
myNot True = False
myNot False = True
main : IO ()
main = do printLn (add 3 4)
          printLn (myNot True)
