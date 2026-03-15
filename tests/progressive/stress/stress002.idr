-- Stress test: 20 functions, every third annotated, rest unannotated
module Main

g1 : Integer -> Integer
g1 x = x * 2

g2 x = g1 x + 1

g3 x = g2 x + g1 x

g4 : Integer -> Integer
g4 x = g3 x - g2 x

g5 x = g4 x + g3 x

g6 x = g5 x + g4 x

g7 : Integer -> Integer
g7 x = g6 x - g5 x

g8 x = g7 x + g6 x

g9 x = g8 x + g7 x

g10 : Integer -> Integer
g10 x = g9 x - g8 x

g11 x = g10 x + g9 x

g12 x = g11 x + g10 x

g13 : Integer -> Integer
g13 x = g12 x - g11 x

g14 x = g13 x + g12 x

g15 x = g14 x + g13 x

g16 : Integer -> Integer
g16 x = g15 x - g14 x

g17 x = g16 x + g15 x

g18 x = g17 x + g16 x

g19 : Integer -> Integer
g19 x = g18 x - g17 x

g20 x = g19 x + g18 x

main : IO ()
main = printLn (g10 1)
