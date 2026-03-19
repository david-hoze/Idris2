module Compiler.ZAM.Instruction

import Core.CompileExpr
import Core.TT
import Core.TT.Primitive
import Data.Maybe

%default total

||| Label = offset into flat bytecode array
public export
Label : Type
Label = Int

||| ZAM instructions for Idris 2.
|||
||| Adapted from Leroy's Zinc Abstract Machine for ANF input.
||| Key difference from the existing VMCode: flat bytecode array with
||| an accumulator register and push-enter calling convention.
|||
||| Calling convention (push-enter):
|||   Caller pushes arguments right-to-left, then enters the function.
|||   GRAB consumes one argument from the stack into the environment.
|||   If GRAB finds a PUSHMARK instead of an argument, the function is
|||   partially applied — a closure is returned with the current env.
|||
||| Compilation from ANF:
|||   T[e] = tail-position compilation (may emit TAILAPPLY/RETURN)
|||   C[e] = non-tail compilation (result in accumulator)
public export
data ZInst : Type where
  -- Environment & registers
  ACCESS    : (slot : Int) -> ZInst     -- accu := env[slot]
  ASSIGN    : (slot : Int) -> ZInst     -- env[slot] := accu
  LET       : ZInst                     -- push accu onto env (new slot)
  ENDLET    : (n : Nat) -> ZInst        -- pop n entries from env

  -- Closures & application (push-enter)
  GRAB      : ZInst                     -- consume arg from stack into env;
                                        -- if stack has PUSHMARK, return partial closure
  CLOSURE   : (lab : Label) -> (envSize : Nat) -> ZInst
                                        -- accu := closure(lab, env[0..envSize-1])
  APPLY     : ZInst                     -- enter closure in accu (push-enter)
  TAILAPPLY : ZInst                     -- tail-call enter closure in accu
  PUSHRETADDR : (lab : Label) -> ZInst  -- push return continuation
  RETURN    : ZInst                     -- pop continuation, jump back
  PUSHMARK  : ZInst                     -- mark stack for partial application detection

  -- Function calls (known targets — direct jump, no closure overhead)
  CALL      : (lab : Label) -> (nargs : Nat) -> ZInst  -- call known function
  TAILCALL  : (lab : Label) -> (nargs : Nat) -> ZInst  -- tail-call known function

  -- Constructors & pattern matching
  MAKEBLOCK : (tag : Int) -> (arity : Nat) -> ZInst
                                        -- pop arity values from stack, build constructor
  MAKEBLOCKNAME : Name -> (arity : Nat) -> ZInst
                                        -- same but with name-based tag (for untagged ctors)
  GETFIELD  : (pos : Nat) -> ZInst      -- accu := accu.fields[pos]
  SWITCH    : (alts : List (Int, Label)) -> (def : Maybe Label) -> ZInst
                                        -- branch on constructor tag in accu
  SWITCHNAME : (alts : List (Name, Label)) -> (def : Maybe Label) -> ZInst
                                        -- branch on constructor name in accu
  CONSTSWITCH : (alts : List (Constant, Label)) -> (def : Maybe Label) -> ZInst
                                        -- branch on constant value in accu

  -- Constants & primitives
  CONST     : Constant -> ZInst         -- accu := constant value
  NULL      : ZInst                     -- accu := erased/unit
  PRIM      : {0 arity : Nat} -> PrimFn arity -> ZInst
                                        -- pop arity args from stack, apply primop
  EXTPRIM   : Name -> (nargs : Nat) -> ZInst
                                        -- pop nargs from stack, call external primitive

  -- Stack manipulation (for argument passing)
  PUSH      : ZInst                     -- push accu onto arg stack
  POP       : ZInst                     -- accu := pop from arg stack

  -- Control
  JUMP      : (lab : Label) -> ZInst    -- unconditional jump
  STOP      : ZInst                     -- halt execution
  ERROR     : String -> ZInst           -- runtime error

  -- Superinstructions (emitted by peephole optimizer)
  ACCESS_PUSH   : (slot : Int) -> ZInst     -- ACCESS slot; PUSH
  CONST_INT_LET : Integer -> ZInst          -- CONST_INT v; LET
  ACCESS0       : ZInst                     -- ACCESS 0
  ACCESS1       : ZInst                     -- ACCESS 1
  ACCESS0_PUSH  : ZInst                     -- ACCESS 0; PUSH
  ACCESS1_PUSH  : ZInst                     -- ACCESS 1; PUSH

||| A compiled function: entry label and the number of arguments it expects.
public export
record ZFun where
  constructor MkZFun
  arity : Nat
  code  : List ZInst

||| Top-level definition in ZAM bytecode.
public export
data ZDef : Type where
  MkZDef    : ZFun -> ZDef
  MkZForeign : (ccs : List String) -> (fargs : List CFType) -> CFType -> ZDef
  MkZError  : (code : List ZInst) -> ZDef

export
Show ZInst where
  show (ACCESS n) = "ACCESS " ++ show n
  show (ASSIGN n) = "ASSIGN " ++ show n
  show LET = "LET"
  show (ENDLET n) = "ENDLET " ++ show n
  show GRAB = "GRAB"
  show (CLOSURE lab sz) = "CLOSURE @" ++ show lab ++ " [" ++ show sz ++ "]"
  show APPLY = "APPLY"
  show TAILAPPLY = "TAILAPPLY"
  show (PUSHRETADDR lab) = "PUSHRETADDR @" ++ show lab
  show RETURN = "RETURN"
  show PUSHMARK = "PUSHMARK"
  show (CALL lab n) = "CALL @" ++ show lab ++ " (" ++ show n ++ ")"
  show (TAILCALL lab n) = "TAILCALL @" ++ show lab ++ " (" ++ show n ++ ")"
  show (MAKEBLOCK tag ar) = "MAKEBLOCK " ++ show tag ++ " " ++ show ar
  show (MAKEBLOCKNAME n ar) = "MAKEBLOCKNAME " ++ show n ++ " " ++ show ar
  show (GETFIELD pos) = "GETFIELD " ++ show pos
  show (SWITCH alts def) = "SWITCH " ++ show (map fst alts) ++ " def:" ++ show (isJust def)
  show (SWITCHNAME alts def) = "SWITCHNAME " ++ show (map fst alts) ++ " def:" ++ show (isJust def)
  show (CONSTSWITCH alts def) = "CONSTSWITCH def:" ++ show (isJust def)
  show (CONST c) = "CONST " ++ show c
  show NULL = "NULL"
  show (PRIM op) = "PRIM " ++ show op
  show (EXTPRIM n nargs) = "EXTPRIM " ++ show n ++ " (" ++ show nargs ++ ")"
  show PUSH = "PUSH"
  show POP = "POP"
  show (JUMP lab) = "JUMP @" ++ show lab
  show STOP = "STOP"
  show (ERROR msg) = "ERROR " ++ show msg
  show (ACCESS_PUSH n) = "ACCESS_PUSH " ++ show n
  show (CONST_INT_LET i) = "CONST_INT_LET " ++ show i
  show ACCESS0 = "ACCESS0"
  show ACCESS1 = "ACCESS1"
  show ACCESS0_PUSH = "ACCESS0_PUSH"
  show ACCESS1_PUSH = "ACCESS1_PUSH"
