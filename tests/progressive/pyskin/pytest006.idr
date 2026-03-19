module Main

-- Python-style for loop
def showAll(xs: List Integer) -> IO ():
  for x in xs:
    printLn x

main : IO ()
main = showAll [1, 2, 3]
