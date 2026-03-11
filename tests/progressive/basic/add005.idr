module Main
myNot True = False
myNot False = True
main : IO ()
main = printLn (myNot True)
