module PythonPrelude

import public Data.IORef
import public Data.List
import public Data.List1
import public Data.String
import public System.File

-- List indexing (Python: xs[i]) — re-export Prelude.getAt
export
getItem : Nat -> List a -> Maybe a
getItem _ [] = Nothing
getItem Z (x :: _) = Just x
getItem (S k) (_ :: xs) = getItem k xs

-- List update (Python: xs[i] = v)
export
setAt : Nat -> a -> List a -> List a
setAt _ _ [] = []
setAt Z v (_ :: xs) = v :: xs
setAt (S k) v (x :: xs) = x :: setAt k v xs

-- List remove (Python: del xs[i])
export
removeAt : Nat -> List a -> List a
removeAt _ [] = []
removeAt Z (_ :: xs) = xs
removeAt (S k) (x :: xs) = x :: removeAt k xs

-- len (Python: len(xs))
export
len : List a -> Integer
len = cast . length

-- str (Python: str(x))
export
str : Show a => a -> String
str = show

-- range (Python: range(n))
export
range : Integer -> List Integer
range n = go 0 n []
  where
    go : Integer -> Integer -> List Integer -> List Integer
    go i m acc =
      if i >= m then reverse acc
      else go (i + 1) m (i :: acc)

-- enumerate (Python: enumerate(xs))
export
enumerate : List a -> List (Integer, a)
enumerate = go 0
  where
    go : Integer -> List a -> List (Integer, a)
    go _ [] = []
    go i (x :: xs) = (i, x) :: go (i + 1) xs

-- hasPrefix (Python: s.startswith(prefix))
export
hasPrefix : String -> String -> Bool
hasPrefix pfx s = isPrefixOf pfx s

-- strip/trim (Python: s.strip())
export
strip : String -> String
strip = trim

-- split (Python: s.split(sep))
export
split : Char -> String -> List String
split c s = forget (Data.String.split (== c) s)

-- join (Python: sep.join(xs))
export
join : String -> List String -> String
join = joinBy

-- printMany (Python: print(a, b, c))
export
printMany : List String -> IO ()
printMany xs = putStrLn (joinBy " " xs)

-- input (Python: input(prompt))
export
input : String -> IO String
input prompt = do
  putStr prompt
  fflush stdout
  getLine

-- IORef convenience: modify
export
modifyRef : IORef a -> (a -> a) -> IO ()
modifyRef ref f = do
  v <- readIORef ref
  writeIORef ref (f v)

-- append to IORef List (Python: xs.append(x))
export
append : IORef (List a) -> a -> IO ()
append ref x = modifyRef ref (++ [x])

-- readAt from IORef List (Python: xs[i])
export
readAt : IORef (List a) -> Nat -> IO (Maybe a)
readAt ref i = do
  xs <- readIORef ref
  pure (getItem i xs)
