module Main
-- Monotonicity test 9: const (partially annotated — polymorphic sig)
const' : a -> b -> a
const' x y = x
main : IO ()
main = do printLn (const' 42 "hello")
          printLn (const' "world" 99)
