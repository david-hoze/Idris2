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
-- Machine state (for init/export only)
------------------------------------------------------------------------

||| Stack frame for return continuations.
public export
data Frame
  = RetFrame Label (List ZValue)    -- return address + saved environment
  | MarkFrame                       -- partial application sentinel

||| The ZAM machine state (used for initialization).
export
record ZState where
  constructor MkZState
  accu     : ZValue
  env      : List ZValue
  argStack : List ZValue
  retStack : List Frame
  pc       : Label
  code     : IOArray ZInst
  codeLen  : Int
  globals  : SortedMap Name Label

------------------------------------------------------------------------
-- Primitive operations
------------------------------------------------------------------------

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

valToInteger : ZValue -> Integer
valToInteger (VInt i) = cast i
valToInteger (VInt64 i) = cast i
valToInteger (VBits64 i) = cast i
valToInteger (VBigInt i) = i
valToInteger (VChar c) = cast (ord c)
valToInteger _ = 0

intBinOp : (Integer -> Integer -> Integer) -> ZValue -> ZValue -> ZValue
intBinOp f (VBigInt a) (VBigInt b) = VBigInt (f a b)
intBinOp f a b = VBigInt (f (valToInteger a) (valToInteger b))

intCmpOp : (Integer -> Integer -> Bool) -> ZValue -> ZValue -> ZValue
intCmpOp f (VBigInt a) (VBigInt b) = VInt (if f a b then 1 else 0)
intCmpOp f a b = VInt (if f (valToInteger a) (valToInteger b) then 1 else 0)

execPrim : {0 arity : Nat} -> PrimFn arity -> Vect arity ZValue -> IO ZValue
-- Double arithmetic (must come before generic patterns)
execPrim (Add DoubleType) [VDouble a, VDouble b] = pure $ VDouble (a + b)
execPrim (Sub DoubleType) [VDouble a, VDouble b] = pure $ VDouble (a - b)
execPrim (Mul DoubleType) [VDouble a, VDouble b] = pure $ VDouble (a * b)
execPrim (Div DoubleType) [VDouble a, VDouble b] = pure $ VDouble (a / b)
execPrim (Neg DoubleType) [VDouble a] = pure $ VDouble (negate a)
-- Integer/Int arithmetic (generic)
execPrim (Add ty) [a, b] = pure $ intBinOp (+) a b
execPrim (Sub ty) [a, b] = pure $ intBinOp (-) a b
execPrim (Mul ty) [a, b] = pure $ intBinOp (*) a b
execPrim (Div ty) [a, b] = pure $ intBinOp div a b
execPrim (Mod ty) [a, b] = pure $ intBinOp mod a b
execPrim (Neg ty) [a] = pure $ VBigInt (negate (valToInteger a))
-- Comparison (String-specific)
execPrim (LT StringType) [VString a, VString b] = pure $ VInt (if a < b then 1 else 0)
execPrim (LTE StringType) [VString a, VString b] = pure $ VInt (if a <= b then 1 else 0)
execPrim (EQ StringType) [VString a, VString b] = pure $ VInt (if a == b then 1 else 0)
execPrim (GTE StringType) [VString a, VString b] = pure $ VInt (if a >= b then 1 else 0)
execPrim (GT StringType) [VString a, VString b] = pure $ VInt (if a > b then 1 else 0)
-- Comparison (Double-specific)
execPrim (LT DoubleType) [VDouble a, VDouble b] = pure $ VInt (if a < b then 1 else 0)
execPrim (LTE DoubleType) [VDouble a, VDouble b] = pure $ VInt (if a <= b then 1 else 0)
execPrim (EQ DoubleType) [VDouble a, VDouble b] = pure $ VInt (if a == b then 1 else 0)
execPrim (GTE DoubleType) [VDouble a, VDouble b] = pure $ VInt (if a >= b then 1 else 0)
execPrim (GT DoubleType) [VDouble a, VDouble b] = pure $ VInt (if a > b then 1 else 0)
-- Comparison (generic)
execPrim (LT ty) [a, b] = pure $ intCmpOp (<) a b
execPrim (LTE ty) [a, b] = pure $ intCmpOp (<=) a b
execPrim (EQ ty) [a, b] = pure $ intCmpOp (==) a b
execPrim (GTE ty) [a, b] = pure $ intCmpOp (>=) a b
execPrim (GT ty) [a, b] = pure $ intCmpOp (>) a b
-- Bitwise operations
execPrim (ShiftL ty) [a, b] = pure $ VBigInt (prim__shl_Integer (valToInteger a) (valToInteger b))
execPrim (ShiftR ty) [a, b] = pure $ VBigInt (prim__shr_Integer (valToInteger a) (valToInteger b))
execPrim (BAnd ty) [a, b] = pure $ VBigInt (prim__and_Integer (valToInteger a) (valToInteger b))
execPrim (BOr ty) [a, b] = pure $ VBigInt (prim__or_Integer (valToInteger a) (valToInteger b))
execPrim (BXOr ty) [a, b] = pure $ VBigInt (prim__xor_Integer (valToInteger a) (valToInteger b))
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
execPrim StrIndex [VString s, VInt i] = pure $ VChar (assert_total $ prim__strIndex s i)
execPrim StrSubstr [VInt start, VInt len, VString s] =
  pure $ VString (substr (cast start) (cast len) s)
-- Double math
execPrim DoublePow [VDouble a, VDouble b] = pure $ VDouble (pow a b)
execPrim DoubleExp [VDouble a] = pure $ VDouble (exp a)
execPrim DoubleLog [VDouble a] = pure $ VDouble (log a)
execPrim DoubleSin [VDouble a] = pure $ VDouble (sin a)
execPrim DoubleCos [VDouble a] = pure $ VDouble (cos a)
execPrim DoubleTan [VDouble a] = pure $ VDouble (tan a)
execPrim DoubleASin [VDouble a] = pure $ VDouble (asin a)
execPrim DoubleACos [VDouble a] = pure $ VDouble (acos a)
execPrim DoubleATan [VDouble a] = pure $ VDouble (atan a)
execPrim DoubleSqrt [VDouble a] = pure $ VDouble (sqrt a)
execPrim DoubleFloor [VDouble a] = pure $ VDouble (floor a)
execPrim DoubleCeiling [VDouble a] = pure $ VDouble (ceiling a)
-- Casts
execPrim (Cast IntegerType DoubleType) [v] = pure $ VDouble (cast (valToInteger v))
execPrim (Cast DoubleType IntegerType) [VDouble d] = pure $ VBigInt (cast d)
execPrim (Cast IntegerType StringType) [v] = pure $ VString (show (valToInteger v))
execPrim (Cast StringType IntegerType) [VString s] = pure $ VBigInt (cast s)
execPrim (Cast StringType DoubleType) [VString s] = pure $ VDouble (cast s)
execPrim (Cast DoubleType StringType) [VDouble d] = pure $ VString (show d)
execPrim (Cast IntegerType IntType) [v] = pure $ VInt (cast (valToInteger v))
execPrim (Cast IntType IntegerType) [VInt i] = pure $ VBigInt (cast i)
execPrim (Cast IntType DoubleType) [VInt i] = pure $ VDouble (cast i)
execPrim (Cast DoubleType IntType) [VDouble d] = pure $ VInt (cast d)
execPrim (Cast CharType IntType) [VChar c] = pure $ VInt (cast (ord c))
execPrim (Cast IntType CharType) [VInt i] = pure $ VChar (chr (cast i))
execPrim (Cast CharType IntegerType) [VChar c] = pure $ VBigInt (cast (ord c))
execPrim (Cast ty StringType) [v] = pure $ VString (showVal v)
  where
    showVal : ZValue -> String
    showVal (VInt i) = show i
    showVal (VInt64 i) = show i
    showVal (VBigInt i) = show i
    showVal (VDouble d) = show d
    showVal (VChar c) = cast c
    showVal v = show v
execPrim (Cast f t) [v] = pure v
execPrim BelieveMe [_, _, v] = pure v
execPrim Crash [_, VString msg] = do
  putStrLn ("CRASH: " ++ msg)
  pure VNull
execPrim _ _ = pure VNull

------------------------------------------------------------------------
-- External primitives (IO operations)
------------------------------------------------------------------------

execExtPrim : Name -> List ZValue -> IO ZValue
execExtPrim n [VString s, _]
  = if show n == "Prelude.IO.prim__putStr"
       || show n == "prelude.prim__putStr"
    then do putStr s; pure VNull
    else pure VNull
execExtPrim n [VChar c, _]
  = if show n == "Prelude.IO.prim__putChar"
    then do putChar c; pure VNull
    else pure VNull
execExtPrim n [VString s]
  = if show n == "Prelude.Types.fastUnpack"
       || show n == "prelude.fastUnpack"
    then pure (strToList s)
    else pure VNull
  where
    strToList : String -> ZValue
    strToList s = case strUncons s of
      Nothing     => VCon (Left 0) []
      Just (c, t) => VCon (Left 1) [VChar c, strToList t]
execExtPrim n [v]
  = if show n == "Prelude.IO.prim__getStr"
       || show n == "prelude.prim__getStr"
    then do s <- getLine; pure (VString s)
    else if show n == "Prelude.Types.fastPack"
       || show n == "prelude.fastPack"
    then pure (VString (listToStr v))
    else pure VNull
  where
    listToStr : ZValue -> String
    listToStr (VCon (Left 1) [VChar c, rest]) = strCons c (listToStr rest)
    listToStr _ = ""
execExtPrim _ _ = pure VNull

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

popN : Nat -> List a -> Maybe (List a, List a)
popN Z xs = Just ([], xs)
popN (S n) [] = Nothing
popN (S n) (x :: xs) = do
  (taken, rest) <- popN n xs
  Just (x :: taken, rest)

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

findConstMatch : ZValue -> List (Constant, Label) -> Maybe Label
findConstMatch v [] = Nothing
findConstMatch v ((c, lab) :: rest) =
  if matchConst v c then Just lab else findConstMatch v rest

------------------------------------------------------------------------
-- PRIM dispatch
------------------------------------------------------------------------

doPrim : {0 arity : Nat} -> PrimFn arity -> List ZValue -> IO (Either String (ZValue, List ZValue))
doPrim (Neg ty) (a :: rest) = do r <- execPrim (Neg ty) [a]; pure (Right (r, rest))
doPrim StrLength (a :: rest) = do r <- execPrim StrLength [a]; pure (Right (r, rest))
doPrim StrHead (a :: rest) = do r <- execPrim StrHead [a]; pure (Right (r, rest))
doPrim StrTail (a :: rest) = do r <- execPrim StrTail [a]; pure (Right (r, rest))
doPrim StrReverse (a :: rest) = do r <- execPrim StrReverse [a]; pure (Right (r, rest))
doPrim DoubleExp (a :: rest) = do r <- execPrim DoubleExp [a]; pure (Right (r, rest))
doPrim DoubleLog (a :: rest) = do r <- execPrim DoubleLog [a]; pure (Right (r, rest))
doPrim DoubleSin (a :: rest) = do r <- execPrim DoubleSin [a]; pure (Right (r, rest))
doPrim DoubleCos (a :: rest) = do r <- execPrim DoubleCos [a]; pure (Right (r, rest))
doPrim DoubleTan (a :: rest) = do r <- execPrim DoubleTan [a]; pure (Right (r, rest))
doPrim DoubleASin (a :: rest) = do r <- execPrim DoubleASin [a]; pure (Right (r, rest))
doPrim DoubleACos (a :: rest) = do r <- execPrim DoubleACos [a]; pure (Right (r, rest))
doPrim DoubleATan (a :: rest) = do r <- execPrim DoubleATan [a]; pure (Right (r, rest))
doPrim DoubleSqrt (a :: rest) = do r <- execPrim DoubleSqrt [a]; pure (Right (r, rest))
doPrim DoubleFloor (a :: rest) = do r <- execPrim DoubleFloor [a]; pure (Right (r, rest))
doPrim DoubleCeiling (a :: rest) = do r <- execPrim DoubleCeiling [a]; pure (Right (r, rest))
doPrim (Cast f t) (a :: rest) = do r <- execPrim (Cast f t) [a]; pure (Right (r, rest))
doPrim (Add ty) (a :: b :: rest) = do r <- execPrim (Add ty) [a, b]; pure (Right (r, rest))
doPrim (Sub ty) (a :: b :: rest) = do r <- execPrim (Sub ty) [a, b]; pure (Right (r, rest))
doPrim (Mul ty) (a :: b :: rest) = do r <- execPrim (Mul ty) [a, b]; pure (Right (r, rest))
doPrim (Div ty) (a :: b :: rest) = do r <- execPrim (Div ty) [a, b]; pure (Right (r, rest))
doPrim (Mod ty) (a :: b :: rest) = do r <- execPrim (Mod ty) [a, b]; pure (Right (r, rest))
doPrim (ShiftL ty) (a :: b :: rest) = do r <- execPrim (ShiftL ty) [a, b]; pure (Right (r, rest))
doPrim (ShiftR ty) (a :: b :: rest) = do r <- execPrim (ShiftR ty) [a, b]; pure (Right (r, rest))
doPrim (BAnd ty) (a :: b :: rest) = do r <- execPrim (BAnd ty) [a, b]; pure (Right (r, rest))
doPrim (BOr ty) (a :: b :: rest) = do r <- execPrim (BOr ty) [a, b]; pure (Right (r, rest))
doPrim (BXOr ty) (a :: b :: rest) = do r <- execPrim (BXOr ty) [a, b]; pure (Right (r, rest))
doPrim (LT ty) (a :: b :: rest) = do r <- execPrim (LT ty) [a, b]; pure (Right (r, rest))
doPrim (LTE ty) (a :: b :: rest) = do r <- execPrim (LTE ty) [a, b]; pure (Right (r, rest))
doPrim (EQ ty) (a :: b :: rest) = do r <- execPrim (EQ ty) [a, b]; pure (Right (r, rest))
doPrim (GTE ty) (a :: b :: rest) = do r <- execPrim (GTE ty) [a, b]; pure (Right (r, rest))
doPrim (GT ty) (a :: b :: rest) = do r <- execPrim (GT ty) [a, b]; pure (Right (r, rest))
doPrim StrIndex (a :: b :: rest) = do r <- execPrim StrIndex [a, b]; pure (Right (r, rest))
doPrim StrCons (a :: b :: rest) = do r <- execPrim StrCons [a, b]; pure (Right (r, rest))
doPrim StrAppend (a :: b :: rest) = do r <- execPrim StrAppend [a, b]; pure (Right (r, rest))
doPrim DoublePow (a :: b :: rest) = do r <- execPrim DoublePow [a, b]; pure (Right (r, rest))
doPrim Crash (a :: b :: rest) = do r <- execPrim Crash [a, b]; pure (Right (r, rest))
doPrim StrSubstr (a :: b :: c :: rest) = do r <- execPrim StrSubstr [a, b, c]; pure (Right (r, rest))
doPrim BelieveMe (a :: b :: c :: rest) = do r <- execPrim BelieveMe [a, b, c]; pure (Right (r, rest))
doPrim _ _ = pure (Left "PRIM: not enough args")

------------------------------------------------------------------------
-- Execution engine
------------------------------------------------------------------------

||| Handle RETURN: walk the return stack, skipping MarkFrames.
doReturn : List Frame -> Maybe (Label, List ZValue, List Frame)
doReturn (RetFrame retpc savedEnv :: rest) = Just (retpc, savedEnv, rest)
doReturn (MarkFrame :: rest) = doReturn rest
doReturn [] = Nothing

||| Run the ZAM. State is passed as separate arguments to avoid
||| record allocation per step.
export
run : Int -> ZState -> IO (Either String ZValue)
run fuel st0 = go fuel st0.accu st0.env st0.argStack st0.retStack st0.pc
  where
    codeArr : IOArray ZInst
    codeArr = st0.code

    go : Int -> (accu : ZValue) -> (env : List ZValue) -> (args : List ZValue)
       -> (ret : List Frame) -> (pc : Int) -> IO (Either String ZValue)
    go 0 accu _ _ _ _ = pure (Left "out of fuel")
    go n accu env args ret pc = do
      Just inst <- readArray codeArr pc
        | Nothing => pure (Left ("PC out of bounds: " ++ show pc))
      let pc1 : Int = pc + 1
      case inst of
        ACCESS slot =>
          case drop (cast {to=Nat} slot) env of
            (v :: _) => go (n-1) v env args ret pc1
            [] => pure (Left ("ACCESS out of bounds: slot " ++ show slot))

        ASSIGN slot =>
          let idx = cast {to=Nat} slot
              newEnv = take idx env ++ [accu] ++ drop (S idx) env
          in go (n-1) accu newEnv args ret pc1

        LET => go (n-1) accu (env ++ [accu]) args ret pc1

        ENDLET k => go (n-1) accu (take (minus (length env) k) env) args ret pc1

        GRAB =>
          case args of
            (arg :: rest) => go (n-1) accu (env ++ [arg]) rest ret pc1
            [] =>
              let closure = VClosure pc env []
              in case ret of
                (RetFrame retpc retenv :: MarkFrame :: retRest) =>
                  go (n-1) closure retenv [] retRest retpc
                (MarkFrame :: RetFrame retpc retenv :: retRest) =>
                  go (n-1) closure retenv [] retRest retpc
                (MarkFrame :: retRest) =>
                  go (n-1) closure env args retRest pc1
                _ => pure (Left "GRAB: empty arg stack and no mark")

        CLOSURE lab sz =>
          go (n-1) (VClosure lab (take sz env) []) env args ret pc1

        APPLY =>
          case accu of
            VClosure cpc cenv _ =>
              go (n-1) accu cenv args (RetFrame pc1 env :: ret) cpc
            _ => pure (Left ("APPLY: not a closure: " ++ show accu))

        TAILAPPLY =>
          case accu of
            VClosure cpc cenv _ => go (n-1) accu cenv args ret cpc
            _ => pure (Left ("TAILAPPLY: not a closure: " ++ show accu))

        PUSHRETADDR lab =>
          go (n-1) accu env args (RetFrame lab env :: ret) pc1

        RETURN =>
          case doReturn ret of
            Just (retpc, savedEnv, rest) =>
              go (n-1) accu savedEnv args rest retpc
            Nothing => pure (Right accu)  -- normal termination

        PUSHMARK => go (n-1) accu env args (MarkFrame :: ret) pc1

        CALL lab nargs =>
          go (n-1) accu [] args (RetFrame pc1 env :: ret) lab

        TAILCALL lab nargs => go (n-1) accu [] args ret lab

        MAKEBLOCK tag arity =>
          case popN arity args of
            Just (fields, rest) =>
              go (n-1) (VCon (Left tag) fields) env rest ret pc1
            Nothing =>
              pure (Left ("MAKEBLOCK: not enough args for arity " ++ show arity))

        MAKEBLOCKNAME nm arity =>
          case popN arity args of
            Just (fields, rest) =>
              go (n-1) (VCon (Right nm) fields) env rest ret pc1
            Nothing =>
              pure (Left ("MAKEBLOCKNAME: not enough args for arity " ++ show arity))

        GETFIELD pos =>
          case accu of
            VCon _ fields =>
              case drop pos fields of
                (v :: _) => go (n-1) v env args ret pc1
                [] => pure (Left ("GETFIELD: field " ++ show pos ++ " out of bounds"))
            _ => pure (Left ("GETFIELD: not a constructor: " ++ show accu))

        SWITCH alts def =>
          case getTag accu of
            Just (Left tag) =>
              case lookup tag alts of
                Just lab => go (n-1) accu env args ret lab
                Nothing => case def of
                  Just lab => go (n-1) accu env args ret lab
                  Nothing => pure (Left ("SWITCH: no match for tag " ++ show tag))
            _ => case def of
              Just lab => go (n-1) accu env args ret lab
              Nothing => pure (Left "SWITCH: not a tagged constructor")

        SWITCHNAME alts def =>
          case getTag accu of
            Just (Right nm) =>
              case lookup nm alts of
                Just lab => go (n-1) accu env args ret lab
                Nothing => case def of
                  Just lab => go (n-1) accu env args ret lab
                  Nothing => pure (Left ("SWITCHNAME: no match for " ++ show nm))
            _ => case def of
              Just lab => go (n-1) accu env args ret lab
              Nothing => pure (Left "SWITCHNAME: not a named constructor")

        CONSTSWITCH alts def =>
          case findConstMatch accu alts of
            Just lab => go (n-1) accu env args ret lab
            Nothing => case def of
              Just lab => go (n-1) accu env args ret lab
              Nothing => pure (Left "CONSTSWITCH: no match")

        CONST c => go (n-1) (constToVal c) env args ret pc1

        NULL => go (n-1) VNull env args ret pc1

        PRIM op => do
          result <- doPrim op args
          case result of
            Right (v, rest) => go (n-1) v env rest ret pc1
            Left msg => pure (Left msg)

        EXTPRIM nm nargs =>
          case popN nargs args of
            Just (as, rest) => do
              result <- execExtPrim nm as
              go (n-1) result env rest ret pc1
            Nothing => pure (Left ("EXTPRIM: not enough args for " ++ show nm))

        PUSH => go (n-1) accu env (accu :: args) ret pc1

        POP =>
          case args of
            (v :: rest) => go (n-1) v env rest ret pc1
            [] => pure (Left "POP: empty stack")

        JUMP lab => go (n-1) accu env args ret lab

        STOP => pure (Right accu)

        ERROR msg => pure (Left ("ERROR: " ++ msg))

        -- Superinstructions (expanded for interpreter)
        ACCESS_PUSH slot =>
          case drop (cast {to=Nat} slot) env of
            (v :: _) => go (n-1) v env (v :: args) ret pc1
            [] => pure (Left ("ACCESS_PUSH out of bounds: slot " ++ show slot))

        CONST_INT_LET v =>
          let val = VBigInt v
          in go (n-1) val (env ++ [val]) args ret pc1

        ACCESS0 =>
          case env of
            (v :: _) => go (n-1) v env args ret pc1
            [] => pure (Left "ACCESS0 out of bounds")

        ACCESS1 =>
          case drop 1 env of
            (v :: _) => go (n-1) v env args ret pc1
            [] => pure (Left "ACCESS1 out of bounds")

        ACCESS0_PUSH =>
          case env of
            (v :: _) => go (n-1) v env (v :: args) ret pc1
            [] => pure (Left "ACCESS0_PUSH out of bounds")

        ACCESS1_PUSH =>
          case drop 1 env of
            (v :: _) => go (n-1) v env (v :: args) ret pc1
            [] => pure (Left "ACCESS1_PUSH out of bounds")

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

zipWithIndex : List a -> List (Int, a)
zipWithIndex = go 0
  where
    go : Int -> List a -> List (Int, a)
    go _ [] = []
    go i (x :: xs) = (i, x) :: go (i + 1) xs

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
    }
