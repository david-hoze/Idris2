module Main

import Data.IORef
import Data.List
import Data.String

-- Python-style record
class Task:
  desc : String
  done : Bool

-- Show tasks with indices
showTasks : List Task -> Nat -> IO ()
showTasks [] _ = pure ()
showTasks (t :: rest) n = do
  let s = if done t then "x" else " "
  putStrLn ("  [" ++ s ++ "] " ++ show n ++ ": " ++ desc t)
  showTasks rest (S n)

-- Replace element at position in list
setAt : Nat -> a -> List a -> List a
setAt _ _ [] = []
setAt Z v (_ :: rest) = v :: rest
setAt (S k) v (x :: rest) = x :: setAt k v rest

-- Get element at position in list
getElem : Nat -> List a -> Maybe a
getElem _ [] = Nothing
getElem Z (x :: _) = Just x
getElem (S k) (_ :: rest) = getElem k rest

-- Process a command, return True to continue
process : IORef (List Task) -> String -> IO Bool
process ref cmd =
  if cmd == "quit" then pure False
  else if cmd == "list" then doList
  else if cmd == "stats" then doStats
  else if isPrefixOf "done " cmd then doDone
  else if cmd /= "" then doAdd
  else doHelp
  where
    doList : IO Bool
    doList = do
      ts <- readIORef ref
      if isNil ts
        then putStrLn "No tasks"
        else showTasks ts 0
      pure True

    doStats : IO Bool
    doStats = do
      ts <- readIORef ref
      n <- pure (length ts)
      d <- pure (length (filter done ts))
      putStrLn ("Total: " ++ show n ++ ", Done: " ++ show d ++ ", Pending: " ++ show (minus n d))
      pure True

    doDone : IO Bool
    doDone = do
      s <- pure (trim (substr 5 (length cmd) cmd))
      case the (Maybe Integer) (parsePositive s) of
        Nothing => do putStrLn "Usage: done <number>"
                      pure True
        Just n => do
          ts <- readIORef ref
          let i = the Nat (cast n)
          case getElem i ts of
            Nothing => do putStrLn ("Invalid task number: " ++ show i)
                          pure True
            Just t => do writeIORef ref (setAt i ({ done := True } t) ts)
                         putStrLn ("Completed: " ++ desc t)
                         pure True

    doAdd : IO Bool
    doAdd = do
      modifyIORef ref (++ [MkTask cmd False])
      putStrLn ("Added: " ++ cmd)
      pure True

    doHelp : IO Bool
    doHelp = do
      putStrLn "Commands: <text>, list, done <n>, stats, quit"
      pure True

-- Main REPL loop
loop : IORef (List Task) -> IO ()
loop ref = do
  putStr "> "
  cmd <- trim <$> getLine
  go <- process ref cmd
  when go (loop ref)

main : IO ()
main = do
  putStrLn "TODO App v1.0"
  ref <- newIORef (the (List Task) [])
  loop ref
