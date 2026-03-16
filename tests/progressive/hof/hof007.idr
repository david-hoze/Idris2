module Main
-- Two HOF args (like compose but with addition)
myLiftA2 f g h x = f (g x) (h x)
main : IO ()
main = printLn (myLiftA2 (+) (* 2) (+ 1) (the Integer 10))
