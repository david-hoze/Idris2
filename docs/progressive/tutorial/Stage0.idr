module Main

-- ============================================================
-- Stage 0: Zero type annotations
-- ============================================================
-- Write code like Python. No type signatures at all.
-- The compiler infers everything.

double x = x * 2

greet name = "Hello, " ++ name ++ "!"

isEmpty [] = True
isEmpty (_ :: _) = False

safeHead def [] = def
safeHead _ (x :: _) = x

factorial 0 = 1
factorial n = n * factorial (n - 1)

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
