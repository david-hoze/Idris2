module Main
-- Error test 4: argument type conflicts with pattern
-- Annotated as Integer but patterns match on Bool
test : Integer -> String
test True = "yes"
test False = "no"
main : IO ()
main = putStrLn (test True)
