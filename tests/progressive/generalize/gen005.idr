module Main
-- Ord constraint inference with nested if-then-else (case blocks)
clamp lo hi x = if x < lo then lo
                else if x > hi then hi
                else x
main : IO ()
main = do printLn (clamp 0 100 150)
          printLn (clamp 0 100 (-5))
          printLn (clamp 0 100 50)
