module Main
-- Where clause with multi-clause pattern matching, unannotated parent
process xs = go xs 0
  where
    go [] acc = acc
    go (x :: rest) acc = go rest (acc + x)
main : IO ()
main = printLn (process [1, 2, 3, 4, 5])
