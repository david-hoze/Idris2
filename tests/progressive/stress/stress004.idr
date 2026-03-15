-- Stress test: monotonicity at scale — 20 unannotated functions
-- This is the v0 (unannotated) version.
-- v1 and v2 (with annotations) must produce identical output.
module Main

inc x = x + 1
dbl x = x + x
square x = x * x
add x y = x + y
sub x y = x - y
mul x y = x * y
myNeg x = 0 - x
clamp x = if x < 0 then 0 else x
pipeline x = dbl (inc (square x))
chain x = add (mul x 2) (inc x)
tripleInc x = inc (inc (inc x))
addSquares x y = add (square x) (square y)
subAbs x y = clamp (sub x y)
dblChain x = dbl (chain x)
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
