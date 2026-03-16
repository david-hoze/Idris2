module Main
-- Linear inference propagates: useOnce inferred linear,
-- so it can be called from a linear context.
consume : (1 _ : String) -> String
consume x = x
useOnce x = consume x
linearCtx : (1 _ : String) -> String
linearCtx s = useOnce s
main : IO ()
main = putStrLn (linearCtx "hello")
