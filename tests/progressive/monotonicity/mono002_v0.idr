module Main
-- Monotonicity test 2: boolean patterns (unannotated)
flipBool True = False
flipBool False = True
main : IO ()
main = printLn (flipBool True)
