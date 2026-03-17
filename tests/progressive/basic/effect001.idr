module Main
greet name = putStrLn ("Hello, " ++ name)
main : IO ()
main = greet "world"
