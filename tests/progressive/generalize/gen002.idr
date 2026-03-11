module Main
const' x y = x
main : IO ()
main = do printLn (const' 42 "hello")
          printLn (const' "world" 99)
