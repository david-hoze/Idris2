module Main
consume : (1 _ : String) -> String
consume x = x
useOnce x = consume x
main : IO ()
main = putStrLn (useOnce "hello")
