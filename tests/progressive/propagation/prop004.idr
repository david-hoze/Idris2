module Main
-- Propagation test 4: unannotated function uses typed data constructor
wrap x = Just x
unwrap (Just x) = x
unwrap Nothing = 0
main : IO ()
main = printLn (unwrap (wrap 42))
