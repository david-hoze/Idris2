module Main
-- Variable used once but in unrestricted position (List cons).
-- Must remain unrestricted, not linear.
unwords : List String -> String
unwords [] = ""
unwords [x] = x
unwords (x::xs) = x ++ " " ++ unwords xs
cat x y = unwords [x, show {ty = Nat} y]
main : IO ()
main = putStrLn (cat "hello" 42)
