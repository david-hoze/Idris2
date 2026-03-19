module Main

-- Python-style if/elif/else
def classify(x: Integer) -> String:
  if x > 0: "positive"
  elif x == 0: "zero"
  else: "negative"

-- Standard Idris if-then-else still works alongside
check : Integer -> String
check n = if n > 100 then "big"
          else "small"

main : IO ()
main = do printLn (classify 5)
          printLn (classify 0)
          printLn (classify (-3))
          printLn (check 200)
          printLn (check 42)
