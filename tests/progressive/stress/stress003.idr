-- Stress test: deeply nested let bindings (10 levels)
module Main

deepNest x =
  let a = x + 1
      b = a + a
  in let c = b + a
         d = c + b
     in let e = d + c
            f = e + d
        in let g = f + e
               h = g + f
           in let i = h + g
                  j = i + h
              in j

main : IO ()
main = printLn (deepNest 1)
