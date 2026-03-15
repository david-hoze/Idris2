-- Stress test: 20 unannotated functions calling each other
module Main

f1 x = x + 1
f2 x = f1 x + f1 x
f3 x = f2 x + f1 x
f4 x = f3 x + f2 x
f5 x = f4 x + f3 x
f6 x = f5 x + f4 x
f7 x = f6 x + f5 x
f8 x = f7 x + f6 x
f9 x = f8 x + f7 x
f10 x = f9 x + f8 x
f11 x = f10 x + f9 x
f12 x = f11 x + f10 x
f13 x = f12 x + f11 x
f14 x = f13 x + f12 x
f15 x = f14 x + f13 x
f16 x = f15 x + f14 x
f17 x = f16 x + f15 x
f18 x = f17 x + f16 x
f19 x = f18 x + f17 x
f20 x = f19 x + f18 x

main : IO ()
main = printLn (f5 0)
