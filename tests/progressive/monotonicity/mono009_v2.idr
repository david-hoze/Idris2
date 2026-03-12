module Main
-- Monotonicity test 9: const (fully annotated with explicit forall)
const' : {0 a : Type} -> {0 b : Type} -> a -> b -> a
const' x y = x
main : IO ()
main = do printLn (const' 42 "hello")
          printLn (const' "world" 99)
