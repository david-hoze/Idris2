module Compiler.ZAM.Serialize

import Compiler.ZAM.Instruction

import Core.Core
import Core.TT
import Core.TT.Primitive

import Data.Buffer
import Data.IOArray
import Data.List
import Data.SortedMap
import Data.String

import System.File.Buffer

%default covering

------------------------------------------------------------------------
-- String pool
------------------------------------------------------------------------

record StringPool where
  constructor MkSP
  strings : List String       -- in order of first appearance
  indices : SortedMap String Int
  nextIdx : Int

emptySP : StringPool
emptySP = MkSP [] empty 0

||| Intern a string, returning its pool index.
intern : String -> StringPool -> (Int, StringPool)
intern s sp = case lookup s sp.indices of
  Just idx => (idx, sp)
  Nothing  =>
    let idx = sp.nextIdx
    in (idx, { strings $= (++ [s])
             , indices $= insert s idx
             , nextIdx := idx + 1 } sp)

------------------------------------------------------------------------
-- PrimFn -> prim_id encoding
------------------------------------------------------------------------

typeIdx : PrimType -> Int
typeIdx IntType     = 0
typeIdx Int8Type    = 1
typeIdx Int16Type   = 2
typeIdx Int32Type   = 3
typeIdx Int64Type   = 4
typeIdx IntegerType = 5
typeIdx Bits8Type   = 6
typeIdx Bits16Type  = 7
typeIdx Bits32Type  = 8
typeIdx Bits64Type  = 9
typeIdx StringType  = 10
typeIdx CharType    = 11
typeIdx DoubleType  = 12
typeIdx WorldType   = 13

primFnId : {0 arity : Nat} -> PrimFn arity -> Int
primFnId (Add ty) = 0 * 16 + typeIdx ty
primFnId (Sub ty) = 1 * 16 + typeIdx ty
primFnId (Mul ty) = 2 * 16 + typeIdx ty
primFnId (Div ty) = 3 * 16 + typeIdx ty
primFnId (Mod ty) = 4 * 16 + typeIdx ty
primFnId (ShiftL ty) = 5 * 16 + typeIdx ty
primFnId (ShiftR ty) = 6 * 16 + typeIdx ty
primFnId (BAnd ty) = 7 * 16 + typeIdx ty
primFnId (BOr ty) = 8 * 16 + typeIdx ty
primFnId (BXOr ty) = 9 * 16 + typeIdx ty
primFnId (LT ty) = 10 * 16 + typeIdx ty
primFnId (LTE ty) = 11 * 16 + typeIdx ty
primFnId (EQ ty) = 12 * 16 + typeIdx ty
primFnId (GTE ty) = 13 * 16 + typeIdx ty
primFnId (GT ty) = 14 * 16 + typeIdx ty
primFnId (Neg ty) = 15 * 16 + typeIdx ty
primFnId StrLength = 256
primFnId StrHead = 257
primFnId StrTail = 258
primFnId StrIndex = 259
primFnId StrCons = 260
primFnId StrAppend = 261
primFnId StrReverse = 262
primFnId StrSubstr = 263
primFnId DoublePow = 280
primFnId DoubleExp = 281
primFnId DoubleLog = 282
primFnId DoubleSin = 283
primFnId DoubleCos = 284
primFnId DoubleTan = 285
primFnId DoubleASin = 286
primFnId DoubleACos = 287
primFnId DoubleATan = 288
primFnId DoubleSqrt = 289
primFnId DoubleFloor = 290
primFnId DoubleCeiling = 291
primFnId (Cast from to) = 300 + typeIdx from * 14 + typeIdx to
primFnId BelieveMe = 500
primFnId Crash = 501

------------------------------------------------------------------------
-- ExtPrim -> extprim_id encoding
------------------------------------------------------------------------

extPrimId : String -> Int
extPrimId n =
  if n == "Prelude.IO.prim__putStr" || n == "prelude.prim__putStr" then 0
  else if n == "Prelude.IO.prim__getStr" || n == "prelude.prim__getStr" then 1
  else if n == "Prelude.IO.prim__putChar" then 2
  else if n == "Prelude.IO.prim__getChar" then 3
  else if n == "Prelude.Types.fastUnpack" || n == "prelude.fastUnpack" then 4
  else if n == "Prelude.Types.fastPack" || n == "prelude.fastPack" then 5
  else if n == "Prelude.Types.fastConcat" || n == "prelude.fastConcat" then 6
  else if n == "Data.IORef.prim__newIORef" then 7
  else if n == "Data.IORef.prim__readIORef" then 8
  else if n == "Data.IORef.prim__writeIORef" then 9
  else 0xFFFF  -- unknown

------------------------------------------------------------------------
-- Instruction byte size calculation
------------------------------------------------------------------------

||| Size of a constant value in CONSTSWITCH alt encoding.
||| Each alt: uint8 type + 8 bytes value + uint32 label = 13 bytes.
constAltSize : Nat
constAltSize = 13

||| Byte size of a single instruction when serialized.
instSize : ZInst -> Int
instSize (ACCESS _)        = 3   -- opcode + uint16
instSize (ASSIGN _)        = 3
instSize LET               = 1
instSize (ENDLET _)        = 3
instSize GRAB              = 1
instSize (CLOSURE _ _)     = 7   -- opcode + uint32 + uint16
instSize APPLY             = 1
instSize TAILAPPLY         = 1
instSize (PUSHRETADDR _)   = 5   -- opcode + uint32
instSize RETURN            = 1
instSize PUSHMARK          = 1
instSize (CALL _ _)        = 7   -- opcode + uint32 + uint16
instSize (TAILCALL _ _)    = 7
instSize (MAKEBLOCK _ _)   = 5   -- opcode + uint16 + uint16
instSize (MAKEBLOCKNAME _ _) = 7 -- opcode + uint32 + uint16
instSize (GETFIELD _)      = 3
instSize (SWITCH alts def) =
  -- opcode(1) + ncases(2) + alts*(tag4+label4) + has_def(1) + [def_label(4)]
  let n = cast {to=Int} (length alts)
      defSz = case def of Nothing => 0; Just _ => 4
  in 1 + 2 + n * 8 + 1 + defSz
instSize (SWITCHNAME alts def) =
  let n = cast {to=Int} (length alts)
      defSz = case def of Nothing => 0; Just _ => 4
  in 1 + 2 + n * 8 + 1 + defSz
instSize (CONSTSWITCH alts def) =
  let n = cast {to=Int} (length alts)
      defSz = case def of Nothing => 0; Just _ => 4
  in 1 + 2 + n * cast {to=Int} constAltSize + 1 + defSz
instSize (CONST (I _))     = 9   -- CONST_INT: opcode + int64
instSize (CONST (I8 _))    = 9
instSize (CONST (I16 _))   = 9
instSize (CONST (I32 _))   = 9
instSize (CONST (I64 _))   = 9
instSize (CONST (BI _))    = 9   -- CONST_INT for now (all fit in int64)
instSize (CONST (B8 _))    = 9
instSize (CONST (B16 _))   = 9
instSize (CONST (B32 _))   = 9
instSize (CONST (B64 _))   = 9
instSize (CONST (Str _))   = 5   -- CONST_STRING: opcode + uint32
instSize (CONST (Ch _))    = 5   -- CONST_CHAR: opcode + uint32
instSize (CONST (Db _))    = 9   -- CONST_DOUBLE: opcode + double
instSize (CONST WorldVal)  = 1   -- CONST_WORLD
instSize (CONST _)         = 1   -- NULL fallback
instSize NULL              = 1
instSize (PRIM _)          = 3   -- opcode + uint16
instSize (EXTPRIM _ _)     = 7   -- opcode + uint32(name_id) + uint16(nargs)
instSize PUSH              = 1
instSize POP               = 1
instSize (JUMP _)          = 5   -- opcode + uint32
instSize STOP              = 1
instSize (ERROR _)         = 5   -- opcode + uint32
-- Superinstructions
instSize (ACCESS_PUSH _)   = 3   -- opcode + uint16
instSize (CONST_INT_LET _) = 9   -- opcode + int64
instSize ACCESS0           = 1
instSize ACCESS1           = 1
instSize ACCESS0_PUSH      = 1
instSize ACCESS1_PUSH      = 1

------------------------------------------------------------------------
-- Label remapping: instruction index → byte offset
------------------------------------------------------------------------

||| Build a map from instruction index to byte offset.
buildLabelMap : List ZInst -> SortedMap Int Int
buildLabelMap insts = go 0 0 empty insts
  where
    go : Int -> Int -> SortedMap Int Int -> List ZInst -> SortedMap Int Int
    go idx offset m [] = insert idx offset m  -- sentinel for past-end
    go idx offset m (inst :: rest) =
      go (idx + 1) (offset + instSize inst) (insert idx offset m) rest

||| Translate a label (instruction index) to byte offset.
xlat : SortedMap Int Int -> Label -> Int
xlat m lab = case lookup lab m of
  Just off => off
  Nothing  => 0  -- should not happen

------------------------------------------------------------------------
-- String collection pass
------------------------------------------------------------------------

||| Collect all strings from instructions into the string pool.
collectStrings : List ZInst -> SortedMap Name Label -> StringPool -> StringPool
collectStrings insts funLabels sp0 =
  let sp1 = foldl collectFromFun sp0 (Data.SortedMap.toList funLabels)
      sp2 = foldl collectFromInst sp1 insts
  in sp2
  where
    collectFromFun : StringPool -> (Name, Label) -> StringPool
    collectFromFun sp (n, _) = snd (intern (show n) sp)

    collectFromInst : StringPool -> ZInst -> StringPool
    collectFromInst sp (ERROR msg) = snd (intern msg sp)
    collectFromInst sp (CONST (Str s)) = snd (intern s sp)
    collectFromInst sp (MAKEBLOCKNAME n _) = snd (intern (show n) sp)
    collectFromInst sp (SWITCHNAME alts _) =
      foldl (\s, (n, _) => snd (intern (show n) s)) sp alts
    collectFromInst sp (EXTPRIM n _) = snd (intern (show n) sp)
    collectFromInst sp _ = sp

------------------------------------------------------------------------
-- Peephole optimization: fuse common patterns into superinstructions
------------------------------------------------------------------------

||| Try to extract an int64-representable value from a Constant.
constToInt64 : Constant -> Maybe Integer
constToInt64 (I i)   = Just (cast i)
constToInt64 (I8 i)  = Just (cast i)
constToInt64 (I16 i) = Just (cast i)
constToInt64 (I32 i) = Just (cast i)
constToInt64 (I64 i) = Just (cast i)
constToInt64 (BI i)  = Just i
constToInt64 (B8 i)  = Just (cast i)
constToInt64 (B16 i) = Just (cast i)
constToInt64 (B32 i) = Just (cast i)
constToInt64 (B64 i) = Just (cast i)
constToInt64 _       = Nothing

||| Peephole optimization pass. Returns optimized instruction list and
||| a mapping from old instruction indices to new instruction indices.
peephole : List ZInst -> (List ZInst, SortedMap Int Int)
peephole insts = let (acc, m) = go 0 0 [] empty insts
                 in (reverse acc, m)
  where
    go : Int -> Int -> List ZInst -> SortedMap Int Int -> List ZInst
      -> (List ZInst, SortedMap Int Int)
    go oldIdx newIdx acc m [] = (acc, insert oldIdx newIdx m)
    go oldIdx newIdx acc m (ACCESS 0 :: PUSH :: rest) =
      go (oldIdx + 2) (newIdx + 1) (ACCESS0_PUSH :: acc)
         (insert (oldIdx + 1) newIdx (insert oldIdx newIdx m)) rest
    go oldIdx newIdx acc m (ACCESS 1 :: PUSH :: rest) =
      go (oldIdx + 2) (newIdx + 1) (ACCESS1_PUSH :: acc)
         (insert (oldIdx + 1) newIdx (insert oldIdx newIdx m)) rest
    go oldIdx newIdx acc m (ACCESS n :: PUSH :: rest) =
      go (oldIdx + 2) (newIdx + 1) (ACCESS_PUSH n :: acc)
         (insert (oldIdx + 1) newIdx (insert oldIdx newIdx m)) rest
    go oldIdx newIdx acc m (ACCESS 0 :: rest) =
      go (oldIdx + 1) (newIdx + 1) (ACCESS0 :: acc)
         (insert oldIdx newIdx m) rest
    go oldIdx newIdx acc m (ACCESS 1 :: rest) =
      go (oldIdx + 1) (newIdx + 1) (ACCESS1 :: acc)
         (insert oldIdx newIdx m) rest
    go oldIdx newIdx acc m (CONST c :: LET :: rest) =
      case constToInt64 c of
        Just v => go (oldIdx + 2) (newIdx + 1) (CONST_INT_LET v :: acc)
                     (insert (oldIdx + 1) newIdx (insert oldIdx newIdx m)) rest
        Nothing => go (oldIdx + 1) (newIdx + 1) (CONST c :: acc)
                      (insert oldIdx newIdx m) (LET :: rest)
    go oldIdx newIdx acc m (x :: rest) =
      go (oldIdx + 1) (newIdx + 1) (x :: acc) (insert oldIdx newIdx m) rest

||| Remap a label using the index mapping.
remapLabel : SortedMap Int Int -> Label -> Label
remapLabel m lab = fromMaybe lab (lookup lab m)

||| Remap all labels in a single instruction.
remapInst : SortedMap Int Int -> ZInst -> ZInst
remapInst m (CLOSURE lab sz) = CLOSURE (remapLabel m lab) sz
remapInst m (PUSHRETADDR lab) = PUSHRETADDR (remapLabel m lab)
remapInst m (CALL lab n) = CALL (remapLabel m lab) n
remapInst m (TAILCALL lab n) = TAILCALL (remapLabel m lab) n
remapInst m (SWITCH alts def) =
  SWITCH (map (\(t,l) => (t, remapLabel m l)) alts) (map (remapLabel m) def)
remapInst m (SWITCHNAME alts def) =
  SWITCHNAME (map (\(n,l) => (n, remapLabel m l)) alts) (map (remapLabel m) def)
remapInst m (CONSTSWITCH alts def) =
  CONSTSWITCH (map (\(c,l) => (c, remapLabel m l)) alts) (map (remapLabel m) def)
remapInst m (JUMP lab) = JUMP (remapLabel m lab)
remapInst _ x = x

||| Apply peephole optimization: fuse patterns, then fix up all labels.
optimizeCode : List ZInst -> SortedMap Name Label -> Label
            -> (List ZInst, SortedMap Name Label, Label)
optimizeCode code funLabels entryPoint =
  let (code', idxMap) = peephole code
      code'' = map (remapInst idxMap) code'
      funLabels' = Data.SortedMap.fromList $
                     map (\(n, l) => (n, remapLabel idxMap l))
                         (Data.SortedMap.toList funLabels)
      entryPoint' = remapLabel idxMap entryPoint
  in (code'', funLabels', entryPoint')

------------------------------------------------------------------------
-- Buffer writing
------------------------------------------------------------------------

||| Write a uint8 to the buffer at offset, return next offset.
writeU8 : Buffer -> Int -> Int -> IO Int
writeU8 buf off v = do setBits8 buf off (cast v); pure (off + 1)

||| Write a uint16 (little-endian) to the buffer.
writeU16 : Buffer -> Int -> Int -> IO Int
writeU16 buf off v = do setBits16 buf off (cast v); pure (off + 2)

||| Write a uint32 (little-endian) to the buffer.
writeU32 : Buffer -> Int -> Int -> IO Int
writeU32 buf off v = do setBits32 buf off (cast v); pure (off + 4)

||| Write an int32 (little-endian) to the buffer.
writeI32 : Buffer -> Int -> Int -> IO Int
writeI32 buf off v = do setInt32 buf off (cast v); pure (off + 4)

||| Write an int64 (little-endian) to the buffer.
writeI64 : Buffer -> Int -> Integer -> IO Int
writeI64 buf off v = do setInt64 buf off (cast v); pure (off + 8)

||| Write a double (IEEE 754) to the buffer.
writeF64 : Buffer -> Int -> Double -> IO Int
writeF64 buf off v = do setDouble buf off v; pure (off + 8)

------------------------------------------------------------------------
-- Instruction serialization
------------------------------------------------------------------------

||| Serialize one CONST instruction.
writeConst : Buffer -> Int -> SortedMap Int Int -> StringPool -> Constant -> IO Int
writeConst buf off lm sp (I i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (I8 i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (I16 i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (I32 i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (I64 i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (BI i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off i
writeConst buf off lm sp (B8 i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (B16 i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (B32 i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (B64 i) = do
  off <- writeU8 buf off 0x1C
  writeI64 buf off (cast i)
writeConst buf off lm sp (Str s) = do
  let (idx, _) = intern s sp
  off <- writeU8 buf off 0x1F
  writeU32 buf off idx
writeConst buf off lm sp (Ch c) = do
  off <- writeU8 buf off 0x20
  writeU32 buf off (ord c)
writeConst buf off lm sp (Db d) = do
  off <- writeU8 buf off 0x1E
  writeF64 buf off d
writeConst buf off lm sp WorldVal = writeU8 buf off 0x21
writeConst buf off lm sp _ = writeU8 buf off 0x1A  -- NULL

||| Serialize a CONSTSWITCH alt value (8 bytes, type-tagged).
writeConstAlt : Buffer -> Int -> SortedMap Int Int -> StringPool
             -> (Constant, Label) -> IO Int
writeConstAlt buf off lm sp (I i, lab) = do
  off <- writeU8 buf off 0  -- ZAM_CONST_INT
  off <- writeI64 buf off (cast i)
  writeU32 buf off (xlat lm lab)
writeConstAlt buf off lm sp (BI i, lab) = do
  off <- writeU8 buf off 1  -- ZAM_CONST_BIGINT (stored as int64)
  off <- writeI64 buf off i
  writeU32 buf off (xlat lm lab)
writeConstAlt buf off lm sp (Str s, lab) = do
  let (idx, _) = intern s sp
  off <- writeU8 buf off 2  -- ZAM_CONST_STR
  off <- writeU32 buf off idx
  off <- writeU32 buf off 0  -- padding to 8 bytes total
  writeU32 buf off (xlat lm lab)
writeConstAlt buf off lm sp (Ch c, lab) = do
  off <- writeU8 buf off 3  -- ZAM_CONST_CHAR
  off <- writeU32 buf off (ord c)
  off <- writeU32 buf off 0  -- padding
  writeU32 buf off (xlat lm lab)
writeConstAlt buf off lm sp (Db d, lab) = do
  off <- writeU8 buf off 4  -- ZAM_CONST_DOUBLE
  off <- writeF64 buf off d
  writeU32 buf off (xlat lm lab)
writeConstAlt buf off lm sp (B8 i, lab) = do
  off <- writeU8 buf off 5
  off <- writeI64 buf off (cast i)
  writeU32 buf off (xlat lm lab)
writeConstAlt buf off lm sp (B16 i, lab) = do
  off <- writeU8 buf off 5
  off <- writeI64 buf off (cast i)
  writeU32 buf off (xlat lm lab)
writeConstAlt buf off lm sp (B32 i, lab) = do
  off <- writeU8 buf off 5
  off <- writeI64 buf off (cast i)
  writeU32 buf off (xlat lm lab)
writeConstAlt buf off lm sp (c, lab) = do
  -- fallback: treat as int
  off <- writeU8 buf off 0
  off <- writeI64 buf off 0
  writeU32 buf off (xlat lm lab)

||| Serialize one instruction.
writeInst : Buffer -> Int -> SortedMap Int Int -> StringPool -> ZInst -> IO Int
writeInst buf off lm sp (ACCESS slot) = do
  off <- writeU8 buf off 0x00
  writeU16 buf off slot
writeInst buf off lm sp (ASSIGN slot) = do
  off <- writeU8 buf off 0x01
  writeU16 buf off slot
writeInst buf off lm sp LET = writeU8 buf off 0x02
writeInst buf off lm sp (ENDLET n) = do
  off <- writeU8 buf off 0x03
  writeU16 buf off (cast n)
writeInst buf off lm sp GRAB = writeU8 buf off 0x04
writeInst buf off lm sp (CLOSURE lab sz) = do
  off <- writeU8 buf off 0x05
  off <- writeU32 buf off (xlat lm lab)
  writeU16 buf off (cast sz)
writeInst buf off lm sp APPLY = writeU8 buf off 0x06
writeInst buf off lm sp TAILAPPLY = writeU8 buf off 0x07
writeInst buf off lm sp (PUSHRETADDR lab) = do
  off <- writeU8 buf off 0x08
  writeU32 buf off (xlat lm lab)
writeInst buf off lm sp RETURN = writeU8 buf off 0x09
writeInst buf off lm sp PUSHMARK = writeU8 buf off 0x0A
writeInst buf off lm sp (CALL lab n) = do
  off <- writeU8 buf off 0x0B
  off <- writeU32 buf off (xlat lm lab)
  writeU16 buf off (cast n)
writeInst buf off lm sp (TAILCALL lab n) = do
  off <- writeU8 buf off 0x0C
  off <- writeU32 buf off (xlat lm lab)
  writeU16 buf off (cast n)
writeInst buf off lm sp (MAKEBLOCK tag arity) = do
  off <- writeU8 buf off 0x0D
  off <- writeU16 buf off tag
  writeU16 buf off (cast arity)
writeInst buf off lm sp (MAKEBLOCKNAME n arity) = do
  let (idx, _) = intern (show n) sp
  off <- writeU8 buf off 0x0E
  off <- writeU32 buf off idx
  writeU16 buf off (cast arity)
writeInst buf off lm sp (GETFIELD pos) = do
  off <- writeU8 buf off 0x0F
  writeU16 buf off (cast pos)
writeInst buf off lm sp (SWITCH alts def) = do
  off <- writeU8 buf off 0x10
  off <- writeU16 buf off (cast (length alts))
  off <- foldlM (\o, (tag, lab) => do
    o <- writeI32 buf o tag
    writeU32 buf o (xlat lm lab)) off alts
  case def of
    Just lab => do
      off <- writeU8 buf off 1
      writeU32 buf off (xlat lm lab)
    Nothing => writeU8 buf off 0
writeInst buf off lm sp (SWITCHNAME alts def) = do
  off <- writeU8 buf off 0x11
  off <- writeU16 buf off (cast (length alts))
  off <- foldlM (\o, (n, lab) => do
    let (idx, _) = intern (show n) sp
    o <- writeU32 buf o idx
    writeU32 buf o (xlat lm lab)) off alts
  case def of
    Just lab => do
      off <- writeU8 buf off 1
      writeU32 buf off (xlat lm lab)
    Nothing => writeU8 buf off 0
writeInst buf off lm sp (CONSTSWITCH alts def) = do
  off <- writeU8 buf off 0x12
  off <- writeU16 buf off (cast (length alts))
  off <- foldlM (\o, alt => writeConstAlt buf o lm sp alt) off alts
  case def of
    Just lab => do
      off <- writeU8 buf off 1
      writeU32 buf off (xlat lm lab)
    Nothing => writeU8 buf off 0
writeInst buf off lm sp (CONST c) = writeConst buf off lm sp c
writeInst buf off lm sp NULL = writeU8 buf off 0x1A
writeInst buf off lm sp (PRIM op) = do
  off <- writeU8 buf off 0x13
  writeU16 buf off (cast (primFnId op))
writeInst buf off lm sp (EXTPRIM n nargs) = do
  let (idx, _) = intern (show n) sp
  off <- writeU8 buf off 0x14
  off <- writeU32 buf off idx
  writeU16 buf off (cast nargs)
writeInst buf off lm sp PUSH = writeU8 buf off 0x15
writeInst buf off lm sp POP = writeU8 buf off 0x16
writeInst buf off lm sp (JUMP lab) = do
  off <- writeU8 buf off 0x17
  writeU32 buf off (xlat lm lab)
writeInst buf off lm sp STOP = writeU8 buf off 0x18
writeInst buf off lm sp (ERROR msg) = do
  let (idx, _) = intern msg sp
  off <- writeU8 buf off 0x19
  writeU32 buf off idx
-- Superinstructions
writeInst buf off lm sp (ACCESS_PUSH slot) = do
  off <- writeU8 buf off 0x30
  writeU16 buf off slot
writeInst buf off lm sp (CONST_INT_LET v) = do
  off <- writeU8 buf off 0x31
  writeI64 buf off v
writeInst buf off lm sp ACCESS0 = writeU8 buf off 0x32
writeInst buf off lm sp ACCESS1 = writeU8 buf off 0x33
writeInst buf off lm sp ACCESS0_PUSH = writeU8 buf off 0x34
writeInst buf off lm sp ACCESS1_PUSH = writeU8 buf off 0x35

------------------------------------------------------------------------
-- Top-level serialization
------------------------------------------------------------------------

||| Compute total bytecode size.
totalCodeSize : List ZInst -> Int
totalCodeSize = foldl (\acc, inst => acc + instSize inst) 0

||| Serialize ZAM bytecode to a file.
export
serializeToFile : (filename : String)
               -> (code : List ZInst)
               -> (funLabels : SortedMap Name Label)
               -> (entryPoint : Label)
               -> Core ()
serializeToFile filename code funLabels entryPoint = do
  -- 0. Peephole optimization: fuse common patterns
  let (code, funLabels, entryPoint) = optimizeCode code funLabels entryPoint

  -- 1. Collect strings
  let sp = collectStrings code funLabels emptySP

  -- 2. Build label map
  let lm = buildLabelMap code

  -- 3. Compute sizes
  let codeSize = totalCodeSize code
  let funList = Data.SortedMap.toList funLabels
  let numFuns = cast {to=Int} (length funList)

  -- String pool size: for each string, 4 bytes length + string bytes + padding
  let strPoolSize = foldl (\acc, s =>
        let len = cast {to=Int} (length s)
            padded = len + (4 - (len `mod` 4)) `mod` 4
        in acc + 4 + padded) 0 sp.strings

  -- Function table size: per entry = 4 (name_id) + 4 (offset) + 2 (arity) = 10 bytes
  let funTableSize = numFuns * 10

  -- Header: 20 bytes (magic4 + version4 + entry4 + numfuns4 + strpoolsize4)
  let headerSize = 20

  -- String pool header: 4 bytes (num_strings)
  let spHeaderSize = 4

  let totalSize = headerSize + spHeaderSize + strPoolSize + funTableSize + codeSize

  -- 4. Allocate buffer
  Just buf <- coreLift $ newBuffer (totalSize + 1024)  -- extra padding
    | Nothing => throw $ InternalError "ZAM serialize: failed to allocate buffer"

  -- 5. Write header
  let entryOff = xlat lm entryPoint
  off <- coreLift $ writeU32 buf 0 0x43425A49  -- "IZBC"
  off <- coreLift $ writeU32 buf off 1          -- version
  off <- coreLift $ writeU32 buf off entryOff   -- entry point (byte offset)
  off <- coreLift $ writeU32 buf off numFuns    -- num functions
  off <- coreLift $ writeU32 buf off strPoolSize -- string pool data size

  -- 6. Write string pool
  off <- coreLift $ writeU32 buf off (cast (length sp.strings))
  off <- coreLift $ foldlM (\o, s => do
    let len = cast {to=Int} (length s)
    o <- writeU32 buf o len
    setString buf o s
    let padded = len + (4 - (len `mod` 4)) `mod` 4
    pure (o + padded)) off sp.strings

  -- 7. Write function table
  off <- coreLift $ foldlM (\o, (n, lab) => do
    let (nameIdx, _) = intern (show n) sp
    o <- writeU32 buf o nameIdx
    o <- writeU32 buf o (xlat lm lab)
    writeU16 buf o 0  -- arity (not tracked currently)
    ) off funList

  -- 8. Write bytecode
  off <- coreLift $ foldlM (\o, inst => writeInst buf o lm sp inst) off code

  -- 9. Write to file
  Right () <- coreLift $ writeBufferToFile filename buf off
    | Left (err, _) => throw $ InternalError ("ZAM serialize: write failed: " ++ show err)

  pure ()
