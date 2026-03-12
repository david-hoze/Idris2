module Main

-- ============================================================
-- Stage 3: Dependent types and totality
-- ============================================================
-- The final stage uses Idris's full type system: explicit
-- quantifiers, totality annotations, and dependent types.
-- This is where Idris goes beyond what Python (or Haskell) can do.

total
double : Num a => a -> a
double x = x * 2

total
greet : String -> String
greet name = "Hello, " ++ name ++ "!"

total
isEmpty : List a -> Bool
isEmpty [] = True
isEmpty (_ :: _) = False

total
safeHead : a -> List a -> a
safeHead def [] = def
safeHead _ (x :: _) = x

-- Not total: recursion on Integer has no structural decrease proof
factorial : Integer -> Integer
factorial 0 = 1
factorial n = n * factorial (n - 1)

-- Dependent type: the return type carries proof of non-emptiness
headOrDefault : {0 a : Type} -> (def : a) -> (xs : List a) -> a
headOrDefault def [] = def
headOrDefault _ (x :: _) = x

total
sumList : Num a => List a -> a
sumList [] = 0
sumList (x :: xs) = x + sumList xs

main : IO ()
main = do putStrLn (greet "Python developer")
          printLn (double 21)
          printLn (isEmpty (the (List Integer) []))
          printLn (isEmpty [1, 2, 3])
          printLn (headOrDefault 0 [42, 1, 2])
          printLn (factorial 10)
          printLn (sumList [1, 2, 3, 4, 5])
