module Main
-- Error test 5: annotation too restrictive for call site
-- Annotated as Integer but called with String
myId : Integer -> Integer
myId x = x
main : IO ()
main = putStrLn (myId "hello")
