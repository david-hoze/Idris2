module Main

-- Python-style enum
class Color:
  Red
  Green
  Blue

Show Color where
  show Red = "Red"
  show Green = "Green"
  show Blue = "Blue"

main : IO ()
main = do printLn Red
          printLn Green
          printLn Blue
