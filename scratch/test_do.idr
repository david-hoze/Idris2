module Main

main : IO ()
main = do
  ab <- pure [1, 2, 3]
  let total = length ab
  putStrLn (show total)
