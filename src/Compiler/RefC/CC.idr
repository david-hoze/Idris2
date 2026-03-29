module Compiler.RefC.CC

import Core.Context.Log
import Core.Options
import Core.Directory

import System
import Idris.Env

import Data.String
import System.Info

%default total

findCC : IO String
findCC
    = do Nothing <- idrisGetEnv "IDRIS2_CC"
           | Just cc => pure cc
         Nothing <- idrisGetEnv "CC"
           | Just cc => pure cc
         pure "cc"

findCFLAGS : IO String
findCFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2_CFLAGS"
         | Just cflags => pure cflags
       Nothing <- idrisGetEnv "CFLAGS"
         | Just cflags => pure cflags
       pure ""

findCPPFLAGS : IO String
findCPPFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2_CPPFLAGS"
         | Just cppflags => pure cppflags
       Nothing <- idrisGetEnv "CPPFLAGS"
         | Just cppflags => pure cppflags
       pure ""

findLDFLAGS : IO String
findLDFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2_LDFLAGS"
         | Just ldflags => pure ldflags
       Nothing <- idrisGetEnv "LDFLAGS"
         | Just ldflags => pure ldflags
       pure ""

findLDLIBS : IO String
findLDLIBS
  = do Nothing <- idrisGetEnv "IDRIS2_LDLIBS"
         | Just ldlibs => pure ldlibs
       Nothing <- idrisGetEnv "LDLIBS"
         | Just ldlibs => pure ldlibs
       pure ""

clibdirs : List String -> List String
clibdirs ds = map (\d => "-L" ++ d) ds

-- cincdirs : List String -> String
-- cincdirs ds = concat (map (\d => "-I" ++ d ++ " ") ds)

export
compileCObjectFile : {auto c : Ref Ctxt Defs}
                  -> {default False asLibrary : Bool}
                  -> (sourceFile : String)
                  -> (objectFile : String)
                  -> Core (Maybe String)
compileCObjectFile {asLibrary} sourceFile objectFile =
  do cc <- coreLift findCC
     cFlags <- coreLift findCFLAGS
     cppFlags <- coreLift findCPPFLAGS

     refcDir <- findDataFile "refc"
     cDir <- findDataFile "c"

     let libraryFlag = if asLibrary then ["-fpic"] else []

     let runccobj = (escapeCmd $
         [cc, "-Werror", "-c"] ++ libraryFlag ++ [sourceFile,
              "-o", objectFile,
              "-I" ++ refcDir,
              "-I" ++ cDir])
              ++ " " ++ cppFlags ++ " " ++ cFlags


     log "compiler.refc.cc" 10 runccobj
     0 <- coreLift $ system runccobj
       | _ => pure Nothing

     pure (Just objectFile)

export
compileCFile : {auto c : Ref Ctxt Defs}
            -> {default False asShared : Bool}
            -> (objectFile : String)
            -> (outFile : String)
            -> Core (Maybe String)
compileCFile {asShared} objectFile outFile =
  do cc <- coreLift findCC
     cFlags <- coreLift findCFLAGS
     ldFlags <- coreLift findLDFLAGS
     ldLibs <- coreLift findLDLIBS

     dirs <- getDirs
     refcDir <- findDataFile "refc"
     supportFile <- findLibraryFile "libidris2_support.a"

     let sharedFlag = if asShared then ["-shared"] else []

     -- On Windows (MinGW/Cygwin), the default PE stack is 2 MB which
     -- is too small for deeply recursive term processing (e.g. the
     -- Idris2 compiler itself processing large list literals).
     -- Reserve 8 MB to match typical Unix defaults.
     let stackFlag = if elem os $ the (List String) ["windows", "mingw32", "cygwin32"]
                        then ["-Wl,--stack,8388608"]
                        else []

     let runcc = (escapeCmd $
         [cc, "-Werror"] ++ sharedFlag ++ stackFlag ++ [objectFile,
              "-o", outFile,
              supportFile,
              "-lidris2_refc",
              "-L" ++ refcDir
              ] ++ clibdirs (lib_dirs dirs) ++ [
              "-lgmp", "-lm"])
              ++ " " ++ (unwords [cFlags, ldFlags, ldLibs])

     log "compiler.refc.cc" 10 runcc
     0 <- coreLift $ system runcc
       | _ => pure Nothing

     pure (Just outFile)
