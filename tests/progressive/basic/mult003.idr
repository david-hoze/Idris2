module Main
linearId : (1 _ : a) -> a
linearId x = x
wrapLinear x = linearId x
main : IO ()
main = printLn (wrapLinear (the Integer 42))
