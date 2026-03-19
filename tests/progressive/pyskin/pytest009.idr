module Main

-- Python-style ADT
class Shape:
  Circle(radius: Double)
  Rectangle(width: Double, height: Double)

def area(s: Shape) -> Double:
  case s of
    Circle r => 3.14159 * r * r
    Rectangle w h => w * h

main : IO ()
main = printLn (area (Circle 5.0))
