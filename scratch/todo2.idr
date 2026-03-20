module Main

import PythonPrelude

class Task:
  desc : String
  done : Bool

showTask : Integer -> Task -> String
showTask i t =
  let s = if done t then "x" else " "
  in "  [" ++ s ++ "] " ++ str i ++ ": " ++ desc t

showAll : List (Integer, Task) -> IO ()
showAll [] = pure ()
showAll ((i, t) :: rest) = do
  putStrLn (showTask i t)
  showAll rest

loop : IORef (List Task) -> IO ()
loop ref = do
  cmd <- input "> "
  if cmd == "quit" then pure ()
    else if cmd == "list" then do
      ts <- readIORef ref
      showAll (enumerate ts)
      loop ref
    else if cmd == "stats" then do
      ts <- readIORef ref
      n <- pure (len ts)
      d <- pure (len (filter done ts))
      putStrLn ("Total: " ++ str n ++ ", Done: " ++ str d ++ ", Pending: " ++ str (n - d))
      loop ref
    else if isPrefixOf "done " cmd then do
      ts <- readIORef ref
      let i = the Nat (cast (cast {to=Integer} (substr 5 (length cmd) cmd)))
      case getItem i ts of
        Nothing => do putStrLn ("Invalid task: " ++ str i)
                      loop ref
        Just t => do writeIORef ref (setAt i ({ done := True } t) ts)
                     putStrLn ("Completed: " ++ desc t)
                     loop ref
    else if cmd /= "" then do
      append ref (MkTask (strip cmd) False)
      putStrLn ("Added: " ++ strip cmd)
      loop ref
    else do
      putStrLn "Commands: <text>, list, done <n>, stats, quit"
      loop ref

main : IO ()
main = do
  putStrLn "TODO App v2.0"
  ref <- newIORef (the (List Task) [])
  loop ref
