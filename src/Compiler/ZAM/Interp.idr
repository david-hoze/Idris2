module Compiler.ZAM.Interp

import Compiler.ZAM.Instruction

import Core.Core
import Core.TT
import Core.TT.Primitive

import Data.IOArray
import Data.List
import Data.Vect
import Data.SortedMap

%default covering

------------------------------------------------------------------------
-- Runtime values
------------------------------------------------------------------------

||| ZAM runtime values.
public export
data ZValue : Type where
  VInt     : Int -> ZValue
  VInt64   : Int64 -> ZValue
  VBits64  : Bits64 -> ZValue
  VBigInt  : Integer -> ZValue
  VDouble  : Double -> ZValue
  VString  : String -> ZValue
  VChar    : Char -> ZValue
  VCon     : (tag : Either Int Name) -> (fields : List ZValue) -> ZValue
  VClosure : (pc : Label) -> (env : List ZValue) -> (pendingArgs : List ZValue) -> ZValue
  VNull    : ZValue
  VWorld   : ZValue

export
Show ZValue where
  show (VInt i) = show i
  show (VInt64 i) = show i
  show (VBits64 i) = show i
  show (VBigInt i) = show i
  show (VDouble d) = show d
  show (VString s) = show s
  show (VChar c) = show c
  show (VCon tag fields) = "Con(" ++ show tag ++ ", " ++ show (length fields) ++ " fields)"
  show (VClosure pc env pending) = "Closure(@" ++ show pc ++ ")"
  show VNull = "null"
  show VWorld = "%World"

------------------------------------------------------------------------
-- Machine state
------------------------------------------------------------------------

||| Stack frame for return continuations.
data Frame
  = RetFrame Label (List ZValue)    -- return address + saved environment
  | MarkFrame                       -- partial application sentinel

||| The ZAM machine state.
export
record ZState where
  constructor MkZState
  accu     : ZValue                 -- accumulator register
  env      : List ZValue            -- environment (closure vars + locals)
  argStack : List ZValue            -- argument stack
  retStack : List Frame             -- return/mark stack
  pc       : Label                  -- program counter
  code     : IOArray ZInst          -- bytecode array
  codeLen  : Int                    -- length of bytecode
  globals  : SortedMap Name Label   -- function name → entry label
  fuel     : Nat                    -- step limit (prevents infinite loops)

||| Read instruction at current PC.
fetchInst : ZState -> IO (Maybe ZInst)
fetchInst st =
  if st.pc >= 0 && st.pc < st.codeLen
    then readArray st.code st.pc
    else pure Nothing

------------------------------------------------------------------------
-- Primitive operations
------------------------------------------------------------------------

||| Convert a Constant to a ZValue.
constToVal : Constant -> ZValue
constToVal (I i) = VInt i
constToVal (I8 i) = VInt (cast i)
constToVal (I16 i) = VInt (cast i)
constToVal (I32 i) = VInt (cast i)
constToVal (I64 i) = VInt64 i
constToVal (BI i) = VBigInt i
constToVal (B8 i) = VInt (cast i)
constToVal (B16 i) = VInt (cast i)
constToVal (B32 i) = VInt (cast i)
constToVal (B64 i) = VBits64 i
constToVal (Str s) = VString s
constToVal (Ch c) = VChar c
constToVal (Db d) = VDouble d
constToVal WorldVal = VWorld
constToVal _ = VNull

||| Extract integer value for comparisons and arithmetic.
valToInteger : ZValue -> Integer
valToInteger (VInt i) = cast i
valToInteger (VInt64 i) = cast i
valToInteger (VBits64 i) = cast i
valToInteger (VBigInt i) = i
valToInteger _ = 0

||| Apply a binary integer operation.
intBinOp : (Integer -> Integer -> Integer) -> ZValue -> ZValue -> ZValue
intBinOp f a b = VBigInt (f (valToInteger a) (valToInteger b))

||| Apply a binary comparison.
intCmpOp : (Integer -> Integer -> Bool) -> ZValue -> ZValue -> ZValue
intCmpOp f a b = VInt (if f (valToInteger a) (valToInteger b) then 1 else 0)

||| Execute a primitive operation.
execPrim : {arity : Nat} -> PrimFn arity -> Vect arity ZValue -> IO ZValue
-- Arithmetic
execPrim (Add ty) [a, b] = pure $ intBinOp (+) a b
execPrim (Sub ty) [a, b] = pure $ intBinOp (-) a b
execPrim (Mul ty) [a, b] = pure $ intBinOp (*) a b
execPrim (Div ty) [a, b] = pure $ intBinOp div a b
execPrim (Mod ty) [a, b] = pure $ intBinOp mod a b
execPrim (Neg ty) [a] = pure $ VBigInt (negate (valToInteger a))
-- Comparison
execPrim (LT ty) [a, b] = pure $ intCmpOp (<) a b
execPrim (LTE ty) [a, b] = pure $ intCmpOp (<=) a b
execPrim (EQ ty) [a, b] = pure $ intCmpOp (==) a b
execPrim (GTE ty) [a, b] = pure $ intCmpOp (>=) a b
execPrim (GT ty) [a, b] = pure $ intCmpOp (>) a b
-- String operations
execPrim StrLength [VString s] = pure $ VInt (cast (length s))
execPrim StrHead [VString s] = pure $ case strUncons s of
  Just (c, _) => VChar c
  Nothing => VChar '\0'
execPrim StrTail [VString s] = pure $ case strUncons s of
  Just (_, rest) => VString rest
  Nothing => VString ""
execPrim StrAppend [VString a, VString b] = pure $ VString (a ++ b)
execPrim StrReverse [VString s] = pure $ VString (reverse s)
execPrim StrCons [VChar c, VString s] = pure $ VString (strCons c s)
execPrim StrSubstr [VInt start, VInt len, VString s] =
  pure $ VString (substr (cast start) (cast len) s)
-- Double operations
execPrim (Add DoubleType) [VDouble a, VDouble b] = pure $ VDouble (a + b)
execPrim (Sub DoubleType) [VDouble a, VDouble b] = pure $ VDouble (a - b)
execPrim (Mul DoubleType) [VDouble a, VDouble b] = pure $ VDouble (a * b)
execPrim (Div DoubleType) [VDouble a, VDouble b] = pure $ VDouble (a / b)
-- Casts
execPrim (Cast IntegerType StringType) [v] = pure $ VString (show (valToInteger v))
execPrim (Cast StringType IntegerType) [VString s] = pure $ VBigInt (cast s)
execPrim (Cast IntegerType IntType) [v] = pure $ VInt (cast (valToInteger v))
execPrim (Cast IntType IntegerType) [VInt i] = pure $ VBigInt (cast i)
execPrim (Cast CharType IntType) [VChar c] = pure $ VInt (cast (ord c))
execPrim (Cast IntType CharType) [VInt i] = pure $ VChar (chr (cast i))
execPrim (Cast ty StringType) [v] = pure $ VString (showVal v)
  where
    showVal : ZValue -> String
    showVal (VInt i) = show i
    showVal (VInt64 i) = show i
    showVal (VBigInt i) = show i
    showVal (VDouble d) = show d
    showVal (VChar c) = cast c
    showVal v = show v
-- BelieveMe
execPrim BelieveMe [_, _, v] = pure v
-- Crash
execPrim Crash [_, VString msg] = do
  putStrLn ("CRASH: " ++ msg)
  pure VNull
-- Default: return null for unimplemented
execPrim _ _ = pure VNull

------------------------------------------------------------------------
-- External primitives (IO operations)
------------------------------------------------------------------------

execExtPrim : Name -> List ZValue -> IO ZValue
-- putStr
execExtPrim n [VString s, _]
  = if show n == "Prelude.IO.prim__putStr"
       || show n == "prelude.prim__putStr"
    then do putStr s; pure VNull
    else pure VNull
-- putChar
execExtPrim n [VChar c, _]
  = if show n == "Prelude.IO.prim__putChar"
    then do putChar c; pure VNull
    else pure VNull
-- getStr
execExtPrim n [_]
  = if show n == "Prelude.IO.prim__getStr"
       || show n == "prelude.prim__getStr"
    then do s <- getLine; pure (VString s)
    else pure VNull
-- Default
execExtPrim _ _ = pure VNull

------------------------------------------------------------------------
-- Execution engine
------------------------------------------------------------------------

||| Pop n values from a list (used for arg stack).
popN : Nat -> List a -> Maybe (List a, List a)
popN Z xs = Just ([], xs)
popN (S n) [] = Nothing
popN (S n) (x :: xs) = do
  (taken, rest) <- popN n xs
  Just (x :: taken, rest)

||| Get constructor tag from a value.
getTag : ZValue -> Maybe (Either Int Name)
getTag (VCon tag _) = Just tag
getTag _ = Nothing

matchConst : ZValue -> Constant -> Bool
matchConst (VInt i) (I j) = i == j
matchConst (VInt i) (BI j) = cast i == j
matchConst (VBigInt i) (BI j) = i == j
matchConst (VBigInt i) (I j) = i == cast j
matchConst (VString s) (Str t) = s == t
matchConst (VChar c) (Ch d) = c == d
matchConst (VDouble d) (Db e) = d == e
matchConst (VInt i) (B8 j) = i == cast j
matchConst (VInt i) (B16 j) = i == cast j
matchConst (VInt i) (B32 j) = i == cast j
matchConst _ _ = False

arityOfPrim : {ar : Nat} -> PrimFn ar -> Nat
arityOfPrim {ar} _ = ar

fromListN : (n : Nat) -> List ZValue -> Vect n ZValue
fromListN Z _ = []
fromListN (S k) (x :: xs) = x :: fromListN k xs
fromListN (S k) [] = VNull :: fromListN k []

findConstMatch : ZValue -> List (Constant, Label) -> Maybe Label
findConstMatch v [] = Nothing
findConstMatch v ((c, lab) :: rest) =
  if matchConst v c then Just lab else findConstMatch v rest

doPrim1 : (ZValue -> IO ZValue) -> ZState -> ZState -> IO (Either String ZState)
doPrim1 f st next =
  case st.argStack of
    (a :: rest) => do
      result <- f a
      pure (Right ({ accu := result, argStack := rest } next))
    _ => pure (Left "PRIM: not enough args (need 1)")

doPrim2 : (ZValue -> ZValue -> IO ZValue) -> ZState -> ZState -> IO (Either String ZState)
doPrim2 f st next =
  case st.argStack of
    (a :: b :: rest) => do
      result <- f a b
      pure (Right ({ accu := result, argStack := rest } next))
    _ => pure (Left "PRIM: not enough args (need 2)")

doPrim3 : (ZValue -> ZValue -> ZValue -> IO ZValue) -> ZState -> ZState -> IO (Either String ZState)
doPrim3 f st next =
  case st.argStack of
    (a :: b :: c :: rest) => do
      result <- f a b c
      pure (Right ({ accu := result, argStack := rest } next))
    _ => pure (Left "PRIM: not enough args (need 3)")

||| Dispatch a PRIM instruction by matching the PrimFn to determine arity.
dispatchPrim : ZState -> ZState -> {0 arity : Nat} -> PrimFn arity -> IO (Either String ZState)
-- Arity 1 ops
dispatchPrim st next (Neg ty)        = doPrim1 (\a => execPrim (Neg ty) [a]) st next
dispatchPrim st next StrLength       = doPrim1 (\a => execPrim StrLength [a]) st next
dispatchPrim st next StrHead         = doPrim1 (\a => execPrim StrHead [a]) st next
dispatchPrim st next StrTail         = doPrim1 (\a => execPrim StrTail [a]) st next
dispatchPrim st next StrReverse      = doPrim1 (\a => execPrim StrReverse [a]) st next
dispatchPrim st next DoubleExp       = doPrim1 (\a => execPrim DoubleExp [a]) st next
dispatchPrim st next DoubleLog       = doPrim1 (\a => execPrim DoubleLog [a]) st next
dispatchPrim st next DoubleSin       = doPrim1 (\a => execPrim DoubleSin [a]) st next
dispatchPrim st next DoubleCos       = doPrim1 (\a => execPrim DoubleCos [a]) st next
dispatchPrim st next DoubleTan       = doPrim1 (\a => execPrim DoubleTan [a]) st next
dispatchPrim st next DoubleASin      = doPrim1 (\a => execPrim DoubleASin [a]) st next
dispatchPrim st next DoubleACos      = doPrim1 (\a => execPrim DoubleACos [a]) st next
dispatchPrim st next DoubleATan      = doPrim1 (\a => execPrim DoubleATan [a]) st next
dispatchPrim st next DoubleSqrt      = doPrim1 (\a => execPrim DoubleSqrt [a]) st next
dispatchPrim st next DoubleFloor     = doPrim1 (\a => execPrim DoubleFloor [a]) st next
dispatchPrim st next DoubleCeiling   = doPrim1 (\a => execPrim DoubleCeiling [a]) st next
dispatchPrim st next (Cast f t)      = doPrim1 (\a => execPrim (Cast f t) [a]) st next
-- Arity 2 ops
dispatchPrim st next (Add ty)        = doPrim2 (\a, b => execPrim (Add ty) [a, b]) st next
dispatchPrim st next (Sub ty)        = doPrim2 (\a, b => execPrim (Sub ty) [a, b]) st next
dispatchPrim st next (Mul ty)        = doPrim2 (\a, b => execPrim (Mul ty) [a, b]) st next
dispatchPrim st next (Div ty)        = doPrim2 (\a, b => execPrim (Div ty) [a, b]) st next
dispatchPrim st next (Mod ty)        = doPrim2 (\a, b => execPrim (Mod ty) [a, b]) st next
dispatchPrim st next (ShiftL ty)     = doPrim2 (\a, b => execPrim (ShiftL ty) [a, b]) st next
dispatchPrim st next (ShiftR ty)     = doPrim2 (\a, b => execPrim (ShiftR ty) [a, b]) st next
dispatchPrim st next (BAnd ty)       = doPrim2 (\a, b => execPrim (BAnd ty) [a, b]) st next
dispatchPrim st next (BOr ty)        = doPrim2 (\a, b => execPrim (BOr ty) [a, b]) st next
dispatchPrim st next (BXOr ty)       = doPrim2 (\a, b => execPrim (BXOr ty) [a, b]) st next
dispatchPrim st next (LT ty)        = doPrim2 (\a, b => execPrim (LT ty) [a, b]) st next
dispatchPrim st next (LTE ty)       = doPrim2 (\a, b => execPrim (LTE ty) [a, b]) st next
dispatchPrim st next (EQ ty)        = doPrim2 (\a, b => execPrim (EQ ty) [a, b]) st next
dispatchPrim st next (GTE ty)       = doPrim2 (\a, b => execPrim (GTE ty) [a, b]) st next
dispatchPrim st next (GT ty)        = doPrim2 (\a, b => execPrim (GT ty) [a, b]) st next
dispatchPrim st next StrIndex        = doPrim2 (\a, b => execPrim StrIndex [a, b]) st next
dispatchPrim st next StrCons         = doPrim2 (\a, b => execPrim StrCons [a, b]) st next
dispatchPrim st next StrAppend       = doPrim2 (\a, b => execPrim StrAppend [a, b]) st next
dispatchPrim st next DoublePow       = doPrim2 (\a, b => execPrim DoublePow [a, b]) st next
dispatchPrim st next Crash           = doPrim2 (\a, b => execPrim Crash [a, b]) st next
-- Arity 3 ops
dispatchPrim st next StrSubstr       = doPrim3 (\a, b, c => execPrim StrSubstr [a, b, c]) st next
dispatchPrim st next BelieveMe       = doPrim3 (\a, b, c => execPrim BelieveMe [a, b, c]) st next

||| Execute one step of the ZAM.
||| Returns Nothing when execution should stop.
step : ZState -> IO (Either String ZState)
step st = do
  Just inst <- fetchInst st
    | Nothing => pure (Left ("PC out of bounds: " ++ show st.pc))
  let next : ZState = { pc := st.pc + 1 } st
  case inst of
    ACCESS slot =>
      case drop (cast {to=Nat} slot) st.env of
        (v :: _) => pure (Right ({ accu := v } next))
        [] => pure (Left ("ACCESS out of bounds: slot " ++ show slot))

    ASSIGN slot =>
      -- Replace env[slot] with accu
      let (pre, rest) = splitAt (cast {to=Nat} slot) st.env in
      case rest of
        (_ :: post) => pure (Right ({ env := pre ++ (st.accu :: post) } next))
        [] => pure (Left ("ASSIGN out of bounds: slot " ++ show slot))

    LET => pure (Right ({ env := st.env ++ [st.accu] } next))

    ENDLET n =>
      let envLen = length st.env in
      pure (Right ({ env := take (minus envLen n) st.env } next))

    GRAB =>
      case st.argStack of
        (arg :: rest) =>
          pure (Right ({ env := st.env ++ [arg], argStack := rest } next))
        [] =>
          -- Partial application: create closure and return to caller
          let closure = VClosure (st.pc - 1) st.env [] in
          case st.retStack of
            (RetFrame retpc retenv :: MarkFrame :: retRest) =>
              -- APPLY context: RetFrame above MarkFrame
              pure (Right ({ accu := closure, pc := retpc, env := retenv,
                            retStack := retRest } st))
            (MarkFrame :: RetFrame retpc retenv :: retRest) =>
              -- TAILAPPLY context: MarkFrame then RetFrame
              pure (Right ({ accu := closure, pc := retpc, env := retenv,
                            retStack := retRest } st))
            (MarkFrame :: retRest) =>
              -- Mark without RetFrame (top-level apply): just set accu
              pure (Right ({ accu := closure, retStack := retRest } st))
            _ => pure (Left "GRAB: empty arg stack and no mark")

    CLOSURE lab sz =>
      let captured = take sz st.env in
      pure (Right ({ accu := VClosure lab captured [] } next))

    APPLY =>
      case st.accu of
        VClosure cpc cenv pending =>
          -- Enter the closure; args are already on argStack for GRAB to consume
          pure (Right ({ pc := cpc, env := cenv,
                        retStack := RetFrame (st.pc + 1) st.env :: st.retStack } st))
        _ => pure (Left ("APPLY: not a closure: " ++ show st.accu))

    TAILAPPLY =>
      case st.accu of
        VClosure cpc cenv pending =>
          -- Tail-enter the closure; no return frame needed
          pure (Right ({ pc := cpc, env := cenv } st))
        _ => pure (Left ("TAILAPPLY: not a closure: " ++ show st.accu))

    PUSHRETADDR lab =>
      pure (Right ({ retStack := RetFrame lab st.env :: st.retStack } next))

    RETURN =>
      case st.retStack of
        (RetFrame retpc retenv :: rest) =>
          pure (Right ({ pc := retpc, env := retenv,
                        retStack := rest } st))
        (MarkFrame :: rest) =>
          -- Skip leftover MarkFrame from APPLY context, re-execute RETURN
          pure (Right ({ retStack := rest } st))
        [] => pure (Left "RETURN: empty return stack")

    PUSHMARK =>
      pure (Right ({ retStack := MarkFrame :: st.retStack } next))

    CALL lab nargs => do
      pure (Right ({ pc := lab, env := [],
                    retStack := RetFrame (st.pc + 1) st.env :: st.retStack } st))

    TAILCALL lab nargs =>
      pure (Right ({ pc := lab, env := [] } st))

    MAKEBLOCK tag arity => do
      case popN arity st.argStack of
        Just (fields, rest) =>
          pure (Right ({ accu := VCon (Left tag) fields,
                        argStack := rest } next))
        Nothing =>
          pure (Left ("MAKEBLOCK: not enough args on stack for arity " ++ show arity))

    MAKEBLOCKNAME n arity => do
      case popN arity st.argStack of
        Just (fields, rest) =>
          pure (Right ({ accu := VCon (Right n) fields,
                        argStack := rest } next))
        Nothing =>
          pure (Left ("MAKEBLOCKNAME: not enough args on stack for arity " ++ show arity))

    GETFIELD pos =>
      case st.accu of
        VCon _ fields =>
          case drop pos fields of
            (v :: _) => pure (Right ({ accu := v } next))
            [] => pure (Left ("GETFIELD: field " ++ show pos ++ " out of bounds"))
        _ => pure (Left ("GETFIELD: not a constructor: " ++ show st.accu))

    SWITCH alts def => do
      let mtag = getTag st.accu
      case mtag of
        Just (Left tag) =>
          case lookup tag alts of
            Just lab => pure (Right ({ pc := lab } st))
            Nothing =>
              case def of
                Just lab => pure (Right ({ pc := lab } st))
                Nothing => pure (Left ("SWITCH: no match for tag " ++ show tag))
        _ =>
          case def of
            Just lab => pure (Right ({ pc := lab } st))
            Nothing => pure (Left "SWITCH: scrutinee is not a tagged constructor")

    SWITCHNAME alts def => do
      case getTag st.accu of
        Just (Right n) =>
          case lookup n alts of
            Just lab => pure (Right ({ pc := lab } st))
            Nothing =>
              case def of
                Just lab => pure (Right ({ pc := lab } st))
                Nothing => pure (Left ("SWITCHNAME: no match for " ++ show n))
        _ =>
          case def of
            Just lab => pure (Right ({ pc := lab } st))
            Nothing => pure (Left "SWITCHNAME: scrutinee is not a named constructor")

    CONSTSWITCH alts def =>
      case findConstMatch st.accu alts of
        Just lab => pure (Right ({ pc := lab } st))
        Nothing =>
          case def of
            Just lab => pure (Right ({ pc := lab } st))
            Nothing => pure (Left "CONSTSWITCH: no match")

    CONST c => pure (Right ({ accu := constToVal c } next))

    NULL => pure (Right ({ accu := VNull } next))

    PRIM op => dispatchPrim st next op

    EXTPRIM n nargs => do
      case popN nargs st.argStack of
        Just (args, rest) => do
          result <- execExtPrim n args
          pure (Right ({ accu := result, argStack := rest } next))
        Nothing => pure (Left ("EXTPRIM: not enough args for " ++ show n))

    PUSH => pure (Right ({ argStack := st.accu :: st.argStack } next))

    POP =>
      case st.argStack of
        (v :: rest) => pure (Right ({ accu := v, argStack := rest } next))
        [] => pure (Left "POP: empty stack")

    JUMP lab => pure (Right ({ pc := lab } st))

    STOP => pure (Left "STOP")

    ERROR msg => pure (Left ("ERROR: " ++ msg))

------------------------------------------------------------------------
-- Main execution loop
------------------------------------------------------------------------

||| Run the ZAM until it stops or runs out of fuel.
export
run : (maxSteps : Nat) -> ZState -> IO (Either String ZValue)
run Z st = pure (Left "out of fuel")
run (S n) st = do
  result <- step st
  case result of
    Left "STOP" => pure (Right st.accu)
    Left "RETURN: empty return stack" => pure (Right st.accu)
    Left msg => pure (Left msg)
    Right st' => run n st'

zipWithIndex : List a -> List (Int, a)
zipWithIndex = go 0
  where
    go : Int -> List a -> List (Int, a)
    go _ [] = []
    go i (x :: xs) = (i, x) :: go (i + 1) xs

||| Initialize the ZAM state from compiled bytecode.
export
initZAM : List ZInst -> SortedMap Name Label -> Label -> IO ZState
initZAM insts globals entryPoint = do
  let len = cast {to=Int} (length insts)
  codeArr <- newArray len
  traverse_ (\(i, inst) => writeArray codeArr i inst)
            (zipWithIndex insts)
  pure $ MkZState
    { accu = VNull
    , env = []
    , argStack = []
    , retStack = []
    , pc = entryPoint
    , code = codeArr
    , codeLen = len
    , globals = globals
    , fuel = 100000000  -- 100M steps
    }
