module Compiler.ZAM.ZAM

import Compiler.Common
import Compiler.ANF
import Compiler.ZAM.Compile
import Compiler.ZAM.Instruction
import Compiler.ZAM.Interp
import Compiler.ZAM.Serialize

import Core.Context
import Core.Core
import Core.Directory
import Core.Options
import Core.TT

import Idris.Syntax

import Data.SortedMap
import Data.String
import Libraries.Utils.Path
import System
import System.File

%default covering

------------------------------------------------------------------------
-- ZAM Backend
------------------------------------------------------------------------

||| Execute a compiled expression using the ZAM interpreter.
executeZAM : Ref Ctxt Defs -> Ref Syn SyntaxInfo
           -> (tmpDir : String) -> ClosedTerm -> Core ()
executeZAM c s tmpDir tm = do
  cdata <- getCompileData False ANF tm
  let defs = cdata.anf
  -- Compile all ANF definitions to ZAM bytecode
  (code, labels) <- compileAll defs
  -- Find the main expression entry point
  let mainName = MN "__mainExpression" 0
  case lookup mainName labels of
    Nothing => throw $ InternalError "ZAM: no __mainExpression found"
    Just entryLab => do
      -- Initialize and run the ZAM
      st <- coreLift $ initZAM code labels entryLab
      result <- coreLift $ run 2000000000 st  -- 2B steps (Int range)
      case result of
        Left err =>
          -- ERROR: messages are deliberate program crashes (holes, Crash prim)
          -- CRASH: messages are from the Crash primitive
          if isPrefixOf "ERROR: " err
            then coreLift $ putStrLn (substr 7 (length err) err)
            else if isPrefixOf "CRASH: " err
            then coreLift $ putStrLn err
            else coreLift $ putStrLn ("ZAM error: " ++ err)
        Right val => pure ()  -- main should have produced IO side effects

------------------------------------------------------------------------
-- ZAMC Backend (C VM)
------------------------------------------------------------------------

||| Compile to .zamc bytecode and build a C executable.
||| Find the ZAM VM executable. Try findDataFile first, fall back to
||| working dir (for development).
findZamVM : {auto c : Ref Ctxt Defs} -> Core String
findZamVM = do
  catch (do zamDir <- findDataFile "zam"
            pure (zamDir </> "idris2-zam"))
        (\_ => do
            dirs <- getDirs
            pure (working_dir dirs </> "support" </> "zam" </> "idris2-zam"))

compileZAMC : Ref Ctxt Defs -> Ref Syn SyntaxInfo
            -> (tmpDir : String) -> (outputDir : String)
            -> ClosedTerm -> (outfile : String) -> Core (Maybe String)
compileZAMC c s tmpDir outputDir tm outfile = do
  cdata <- getCompileData False ANF tm
  let defs = cdata.anf
  (code, labels) <- compileAll defs
  let mainName = MN "__mainExpression" 0
  case lookup mainName labels of
    Nothing => throw $ InternalError "ZAMC: no __mainExpression found"
    Just entryLab => do
      coreLift_ $ mkdirAll outputDir
      let zamcFile = outputDir </> outfile ++ ".zamc"
      serializeToFile zamcFile code labels entryLab
      vmExec <- findZamVM
      -- Create a wrapper script that invokes the VM with the bytecode
      let wrapperFile = outputDir </> outfile
      coreLift_ $ writeFile wrapperFile
        ("#!/bin/sh\nexec \"" ++ vmExec ++ "\" \"" ++ zamcFile ++ "\" \"$@\"\n")
      coreLift_ $ system ("chmod +x \"" ++ wrapperFile ++ "\"")
      pure (Just wrapperFile)

||| Execute via the C VM.
executeZAMC : Ref Ctxt Defs -> Ref Syn SyntaxInfo
            -> (tmpDir : String) -> ClosedTerm -> Core ()
executeZAMC c s tmpDir tm = do
  cdata <- getCompileData False ANF tm
  let defs = cdata.anf
  (code, labels) <- compileAll defs
  let mainName = MN "__mainExpression" 0
  case lookup mainName labels of
    Nothing => throw $ InternalError "ZAMC: no __mainExpression found"
    Just entryLab => do
      let zamcFile = tmpDir </> "_tmp_zamc.zamc"
      serializeToFile zamcFile code labels entryLab
      vmExec <- findZamVM
      let cmd = vmExec ++ " " ++ zamcFile
      0 <- coreLift $ system cmd
        | rc => throw $ InternalError ("ZAMC: VM failed (rc=" ++ show rc ++ ")")
      pure ()

------------------------------------------------------------------------
-- Codegen interfaces
------------------------------------------------------------------------

||| The ZAM code generator (Idris interpreter).
export
codegenZAM : Codegen
codegenZAM = MkCG compileZAM executeZAM Nothing Nothing
  where
    compileZAM : Ref Ctxt Defs -> Ref Syn SyntaxInfo
              -> (tmpDir : String) -> (outputDir : String)
              -> ClosedTerm -> (outfile : String) -> Core (Maybe String)
    compileZAM c s tmpDir outputDir tm outfile = do
      coreLift $ putStrLn "ZAM interpreter backend: use --exec or :exec"
      pure Nothing

||| The ZAMC code generator (C bytecode VM).
export
codegenZAMC : Codegen
codegenZAMC = MkCG compileZAMC executeZAMC Nothing Nothing
