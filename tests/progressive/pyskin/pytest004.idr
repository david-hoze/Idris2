module Main

-- Regular Idris-style def (should still work)
def add x y = x + y

-- Python-style def
def double(x: Integer) -> Integer:
  x * 2

-- Regular Idris without def keyword
triple x = x * 3

main : IO ()
main = do printLn (add 3 4)
          printLn (double 5)
          printLn (triple 6)
