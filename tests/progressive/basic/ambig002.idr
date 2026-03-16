module Main
-- Ambiguous constructor (::) resolved via constSolvable
myHead (x :: _) = Just x
myHead [] = Nothing
main : IO ()
main = printLn (myHead [1, 2, 3])
