module Main
-- flip: swap function arguments (2-arity HOF)
myFlip f x y = f y x
main : IO ()
main = printLn (myFlip (-) (the Integer 3) 10)
