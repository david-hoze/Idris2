module Main

import Data.String
import System

isPrime : Integer -> Bool
isPrime n =
  if n < 2 then False
  else loop 2
  where
    loop : Integer -> Bool
    loop j =
      if j * j > n then True
      else if mod n j == 0 then False
      else loop (j + 1)

countPrimes : Integer -> Integer
countPrimes n = go 2 0
  where
    go : Integer -> Integer -> Integer
    go i acc =
      if i > n then acc
      else go (i + 1) (if isPrime i then acc + 1 else acc)

getN : List String -> Integer
getN (_ :: s :: _) = maybe 100000 id (parsePositive s)
getN _ = 100000

main : IO ()
main = do
  args <- getArgs
  n <- pure (getN args)
  putStrLn ("Primes up to " ++ show n ++ ": " ++ show (countPrimes n))
