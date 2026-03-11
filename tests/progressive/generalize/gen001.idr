module Main
id' x = x
main : IO ()
main = do printLn (id' 42)
          printLn (id' "hello")
