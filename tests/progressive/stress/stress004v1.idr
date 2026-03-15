-- Stress test: monotonicity at scale — 20 functions, half annotated
-- v1 (partial annotations) must produce identical output to v0.
module Main

inc : Integer -> Integer
inc x = x + 1

dbl x = x + x

square : Integer -> Integer
square x = x * x

add x y = x + y

sub : Integer -> Integer -> Integer
sub x y = x - y

mul x y = x * y

myNeg : Integer -> Integer
myNeg x = 0 - x

clamp x = if x < 0 then 0 else x

pipeline : Integer -> Integer
pipeline x = dbl (inc (square x))

chain x = add (mul x 2) (inc x)

tripleInc : Integer -> Integer
tripleInc x = inc (inc (inc x))

addSquares x y = add (square x) (square y)

subAbs : Integer -> Integer -> Integer
subAbs x y = clamp (sub x y)

dblChain x = dbl (chain x)

megaPipeline : Integer -> Integer
megaPipeline x = pipeline (tripleInc (clamp x))

main : IO ()
main = do
  printLn (inc 5)
  printLn (dbl 7)
  printLn (square 4)
  printLn (add 10 20)
  printLn (sub 50 8)
  printLn (mul 6 7)
  printLn (myNeg 42)
  printLn (clamp (-5))
  printLn (pipeline 3)
  printLn (chain 4)
  printLn (tripleInc 10)
  printLn (addSquares 3 4)
  printLn (subAbs 5 12)
  printLn (dblChain 3)
  printLn (megaPipeline (-2))
