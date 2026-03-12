module Main

-- ============================================================
-- Stage 2: Full annotations with polymorphism
-- ============================================================
-- Every function has a type signature. Polymorphic functions
-- use implicit type parameters. This is idiomatic Idris.

double : Num a => a -> a
double x = x * 2

greet : String -> String
greet name = "Hello, " ++ name ++ "!"

isEmpty : List a -> Bool
isEmpty [] = True
isEmpty (_ :: _) = False

safeHead : a -> List a -> a
safeHead def [] = def
safeHead _ (x :: _) = x

factorial : Integer -> Integer
factorial 0 = 1
factorial n = n * factorial (n - 1)

-- Now with a polymorphic type using Num constraint
sumList : Num a => List a -> a
sumList [] = 0
sumList (x :: xs) = x + sumList xs

main : IO ()
main = do putStrLn (greet "Python developer")
          printLn (double 21)
          printLn (isEmpty (the (List Integer) []))
          printLn (isEmpty [1, 2, 3])
          printLn (safeHead 0 [42, 1, 2])
          printLn (factorial 10)
          printLn (sumList [1, 2, 3, 4, 5])
