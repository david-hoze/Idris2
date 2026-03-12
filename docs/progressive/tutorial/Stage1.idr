module Main

-- ============================================================
-- Stage 1: Annotate the API boundary
-- ============================================================
-- Add type signatures to the functions you'd document anyway.
-- Internal helpers stay unannotated. The compiler checks that
-- your annotations are consistent with the implementation.

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

sumList : List Integer -> Integer
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
