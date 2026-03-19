module Main

def greet(name):
  putStrLn ("Hello, " ++ name ++ "!")

main : IO ()
main = greet "World"
