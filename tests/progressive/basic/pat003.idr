module Main
fromMaybe def Nothing = def
fromMaybe _ (Just x) = x
main : IO ()
main = printLn (fromMaybe 0 (Just 42))
