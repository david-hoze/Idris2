module Main

def add(x: Integer, y: Integer) -> Integer:
  x + y

main : IO ()
main = printLn (add 3 4)
