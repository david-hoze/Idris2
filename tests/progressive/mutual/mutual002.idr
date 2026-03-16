module Main
mutual
  countDown 0 = "done"
  countDown n = countUp (n - 1)
  countUp 0 = "done"
  countUp n = countDown (n - 1)
main : IO ()
main = putStrLn (countDown 5)
