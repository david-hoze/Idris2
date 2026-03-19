module Main

-- Python-style record
class Point:
  x: Double
  y: Double

main : IO ()
main = do let p = MkPoint 3.0 4.0
          printLn (x p)
          printLn (y p)
