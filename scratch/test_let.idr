module Main

import Data.IORef

test : IORef (List String) -> IO ()
test ref = do
  tasks <- readIORef ref
  let total = length tasks
  putStrLn (show total)

main : IO ()
main = do
  ref <- newIORef (the (List String) [])
  test ref
