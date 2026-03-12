module Main
-- Monotonicity test 5: polymorphic identity (fully annotated with explicit forall)
id' : {0 a : Type} -> a -> a
id' x = x
main : IO ()
main = do printLn (id' 42)
          printLn (id' "hello")
