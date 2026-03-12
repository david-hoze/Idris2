module Main
-- Propagation test 2: unannotated function uses typed library function (show)
greet name = "Hello, " ++ name ++ "!"
main : IO ()
main = putStrLn (greet "world")
