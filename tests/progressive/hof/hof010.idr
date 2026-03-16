module Main
-- Monotonicity: compose with explicit type annotation
compose : (b -> c) -> (a -> b) -> a -> c
compose f g x = f (g x)
main : IO ()
main = printLn (compose (* 2) (+ 1) (the Integer 20))
