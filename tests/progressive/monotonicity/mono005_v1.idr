module Main
-- Monotonicity test 5: polymorphic identity (partially annotated — implicit type param)
id' : a -> a
id' x = x
main : IO ()
main = do printLn (id' 42)
          printLn (id' "hello")
