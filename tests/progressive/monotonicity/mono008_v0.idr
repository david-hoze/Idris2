module Main
-- Monotonicity test 8: fromMaybe with Maybe pattern (unannotated)
fromMaybe' def Nothing = def
fromMaybe' _ (Just x) = x
main : IO ()
main = do printLn (fromMaybe' 0 (Just 42))
          printLn (fromMaybe' 99 Nothing)
