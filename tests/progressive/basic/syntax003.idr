module Main
def myNot True = False
def myNot False = True
main : IO ()
main = printLn (myNot True)
