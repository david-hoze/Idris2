module Main
greet "world" = "Hello, World!"
greet name = "Hello, " ++ name ++ "!"
main : IO ()
main = do putStrLn (greet "world")
          putStrLn (greet "Alice")
