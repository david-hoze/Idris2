module Main
-- Monotonicity test 2: boolean patterns (return type annotated)
flipBool : Bool -> Bool
flipBool True = False
flipBool False = True
main : IO ()
main = printLn (flipBool True)
