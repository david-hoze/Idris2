module Main
-- Error test 2: return type conflicts with numeric literal
-- Annotated return as String but RHS is numeric
myLength : List a -> String
myLength [] = 0
myLength (_ :: xs) = 1 + myLength xs
main : IO ()
main = printLn (myLength [1,2,3])
