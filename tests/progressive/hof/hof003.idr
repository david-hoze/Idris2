module Main
compose f g x = f (g x)
main : IO ()
main = printLn (compose (* 2) (+ 1) (the Integer 20))
