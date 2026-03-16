module Main
mutual
  isEven 0 = True
  isEven n = isOdd (n - 1)
  isOdd 0 = False
  isOdd n = isEven (n - 1)
main : IO ()
main = do printLn (isEven 10)
          printLn (isOdd 7)
