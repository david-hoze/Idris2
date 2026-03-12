module Main
-- Monotonicity test 5: polymorphic identity used at specific types (unannotated)
id' x = x
main : IO ()
main = do printLn (id' 42)
          printLn (id' "hello")
