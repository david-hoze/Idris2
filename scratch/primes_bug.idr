module Main

import Data.String
import System

-- Deliberately buggy: isPrime returns String instead of Bool
isPrime : Integer -> String
isPrime n =
  if n < 2 then "no"
  else loop 2
  where
    loop : Integer -> String
    loop j =
      if j * j > n then "yes"
      else if mod n j == 0 then "no"
      else loop (j + 1)

-- This should fail at compile time: isPrime returns String, not Bool
countPrimes : Integer -> Integer
countPrimes n = go 2 0
  where
    go : Integer -> Integer -> Integer
    go i acc =
      if i > n then acc
      else go (i + 1) (if isPrime i then acc + 1 else acc)

main : IO ()
main = putStrLn (show (countPrimes 100))
