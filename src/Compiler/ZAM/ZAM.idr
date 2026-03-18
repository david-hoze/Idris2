module Compiler.ZAM.ZAM

import Compiler.Common
import Compiler.ANF
import Compiler.ZAM.Compile
import Compiler.ZAM.Instruction
import Compiler.ZAM.Interp

import Core.Context
import Core.Core
import Core.Options
import Core.TT

import Idris.Syntax

import Data.SortedMap
import Libraries.Utils.Path

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
      result <- coreLift $ run 100000000 st
      case result of
        Left err => coreLift $ putStrLn ("ZAM error: " ++ err)
        Right val => pure ()  -- main should have produced IO side effects

||| The ZAM code generator interface.
export
codegenZAM : Codegen
codegenZAM = MkCG compileZAM executeZAM Nothing Nothing
  where
    compileZAM : Ref Ctxt Defs -> Ref Syn SyntaxInfo
              -> (tmpDir : String) -> (outputDir : String)
              -> ClosedTerm -> (outfile : String) -> Core (Maybe String)
    compileZAM c s tmpDir outputDir tm outfile = do
      coreLift $ putStrLn "ZAM backend: compile not yet supported (use --exec or :exec)"
      pure Nothing
