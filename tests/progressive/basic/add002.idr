module Main
greet name = "Hello, " ++ name
main : IO ()
main = putStrLn (greet "World")
