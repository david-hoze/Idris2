module Main
-- Monotonicity test 9: const (polymorphic, used at multiple types) (unannotated)
const' x y = x
main : IO ()
main = do printLn (const' 42 "hello")
          printLn (const' "world" 99)
