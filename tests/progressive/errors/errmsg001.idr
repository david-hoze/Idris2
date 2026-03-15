module Main
process x = x + "hello"
main : IO ()
main = putStrLn (process 5)
