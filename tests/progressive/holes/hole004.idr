-- Hole that is reached at runtime.
-- Compiles with warning "compiling hole Main.todo".
-- Crashes at runtime with "Encountered unimplemented hole Main.todo".
module Main
add : Integer -> Integer -> Integer
add x y = ?todo
main : IO ()
main = printLn (add 1 2)
