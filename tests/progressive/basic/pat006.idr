module Main
-- Pair destructuring: both myFst and mySnd, polymorphic usage
myFst (x, _) = x
mySnd (_, y) = y
main : IO ()
main = do printLn (myFst (42, "hello"))
          printLn (myFst ("world", True))
          printLn (mySnd (42, "hello"))
          printLn (mySnd (True, 99))
