module Compiler.ZAM.Compile

import Compiler.ANF
import Compiler.ZAM.Instruction

import Core.CompileExpr
import Core.Core
import Core.Context
import Core.TT

import Data.List
import Data.SnocList
import Data.Vect
import Data.SortedMap

%default covering

data CState : Type where

||| Compilation state: tracks current bytecode offset and label assignments.
record CompileState where
  constructor MkCS
  nextLabel : Label                   -- next free label
  funLabels : SortedMap Name Label    -- function name → entry label
  code      : SnocList ZInst          -- accumulated bytecode (built right)

initState : CompileState
initState = MkCS 0 empty [<]

||| Emit an instruction, advancing the label counter.
emit : {auto st : Ref CState CompileState} -> ZInst -> Core ()
emit inst = do
  s <- get CState
  put CState ({ nextLabel $= (+ 1), code $= (:< inst) } s)

||| Emit multiple instructions.
emitAll : {auto st : Ref CState CompileState} -> List ZInst -> Core ()
emitAll = traverse_ emit

||| Get the current bytecode offset (next instruction will be at this label).
here : {auto st : Ref CState CompileState} -> Core Label
here = nextLabel <$> get CState

||| Reserve a label (allocate an offset to be patched later).
||| Returns the current offset for forward reference.
reserveLabel : {auto st : Ref CState CompileState} -> Core Label
reserveLabel = here

||| Look up the entry label for a named function.
lookupFun : {auto st : Ref CState CompileState} -> Name -> Core (Maybe Label)
lookupFun n = lookup n . funLabels <$> get CState

||| Register a function's entry label.
registerFun : {auto st : Ref CState CompileState} -> Name -> Label -> Core ()
registerFun n lab = do
  s <- get CState
  put CState ({ funLabels $= insert n lab } s)

------------------------------------------------------------------------
-- ANF variable mapping
--
-- ANF variables are numbered (Int). In the ZAM, we use a flat register
-- model: each ANF variable maps to an environment slot. The environment
-- grows as we bind new variables.
--
-- For function arguments: args are in env[0], env[1], ..., env[n-1]
-- For let-bound variables: each ALet pushes to the next env slot
------------------------------------------------------------------------

||| Variable mapping: ANF variable Int → environment slot Int
VarMap : Type
VarMap = SortedMap Int Int

||| Compile a variable reference: load it into the accumulator.
compileVar : {auto st : Ref CState CompileState} -> VarMap -> AVar -> Core ()
compileVar vm (ALocal i) = case lookup i vm of
  Just slot => emit (ACCESS slot)
  Nothing   => emit (ERROR ("unbound variable v" ++ show i))
compileVar vm ANull = emit NULL

||| Compile expression in non-tail position (result in accumulator).
||| C[e] compilation scheme.
compileExpr : {auto st : Ref CState CompileState} -> VarMap -> (envDepth : Nat) -> ANF -> Core ()

||| Compile expression in tail position.
||| T[e] compilation scheme — may emit RETURN or TAILCALL.
compileTail : {auto st : Ref CState CompileState} -> VarMap -> (envDepth : Nat) -> ANF -> Core ()

-- Forward declarations for case compilation (mutually recursive with compileExpr/compileTail)
compileConCase : {auto st : Ref CState CompileState}
              -> VarMap -> Nat -> AVar -> List AConAlt -> Maybe ANF -> Core ()
compileConCaseTail : {auto st : Ref CState CompileState}
                  -> VarMap -> Nat -> AVar -> List AConAlt -> Maybe ANF -> Core ()
compileConstCase : {auto st : Ref CState CompileState}
                -> VarMap -> Nat -> AVar -> List AConstAlt -> Maybe ANF -> Core ()
compileConstCaseTail : {auto st : Ref CState CompileState}
                    -> VarMap -> Nat -> AVar -> List AConstAlt -> Maybe ANF -> Core ()

-- Push arguments onto the stack (right-to-left for push-enter convention)
pushArgs : {auto st : Ref CState CompileState} -> VarMap -> List AVar -> Core ()
pushArgs vm args = traverse_ (\a => do compileVar vm a; emit PUSH) (reverse args)

-- Push arguments from a Vect
pushArgsV : {auto st : Ref CState CompileState} -> VarMap -> {n : Nat} -> Vect n AVar -> Core ()
pushArgsV vm args = pushArgs vm (toList args)

compileExpr vm depth (AV fc var) = compileVar vm var

compileExpr vm depth (AAppName fc _ n args) = do
  mlab <- lookupFun n
  case mlab of
    Just lab => do
      pushArgs vm args
      afterCall <- here
      emit (PUSHRETADDR (afterCall + 2))  -- will be patched
      emit (CALL lab (length args))
    Nothing => do
      -- Unknown function: build closure and apply args
      pushArgs vm args
      emit (CONST (Str (show n)))
      emit (ERROR ("unknown function: " ++ show n))

compileExpr vm depth (AUnderApp fc n missing args) = do
  -- Create a partial application closure
  -- Push captured args, then create closure
  pushArgs vm args
  mlab <- lookupFun n
  case mlab of
    Just lab => emit (CLOSURE lab (length args))
    Nothing => emit (ERROR ("unknown function for closure: " ++ show n))

compileExpr vm depth (AApp fc _ closure arg) = do
  -- Evaluate closure, push it, evaluate arg, apply
  compileVar vm arg
  emit PUSH
  compileVar vm closure
  emit PUSHMARK
  emit APPLY

compileExpr vm depth (ALet fc var val body) = do
  compileExpr vm depth val
  emit LET
  let vm' = insert var (cast depth) vm
  compileExpr vm' (S depth) body
  emit (ENDLET 1)

compileExpr vm depth (ACon fc n ci (Just tag) args) = do
  pushArgs vm args
  emit (MAKEBLOCK tag (length args))

compileExpr vm depth (ACon fc n ci Nothing args) = do
  pushArgs vm args
  emit (MAKEBLOCKNAME n (length args))

compileExpr vm depth (AOp fc _ op args) = do
  pushArgs vm (toList args)
  emit (PRIM op)

compileExpr vm depth (AExtPrim fc _ p args) = do
  pushArgs vm args
  emit (EXTPRIM p (length args))

compileExpr vm depth (AConCase fc scr alts def) = do
  compileVar vm scr
  -- Emit SWITCH with forward labels (to be resolved)
  -- For now, compile inline with jumps
  compileConCase vm depth scr alts def

compileExpr vm depth (AConstCase fc scr alts def) = do
  compileVar vm scr
  compileConstCase vm depth scr alts def

compileExpr vm depth (APrimVal fc c) = emit (CONST c)
compileExpr vm depth (AErased fc) = emit NULL
compileExpr vm depth (ACrash fc msg) = emit (ERROR msg)

-- Tail-position compilation
compileTail vm depth (AV fc var) = do
  compileVar vm var
  emit RETURN

compileTail vm depth (AAppName fc _ n args) = do
  mlab <- lookupFun n
  case mlab of
    Just lab => do
      pushArgs vm args
      emit (TAILCALL lab (length args))
    Nothing => do
      compileExpr vm depth (AAppName fc Nothing n args)
      emit RETURN

compileTail vm depth (AApp fc _ closure arg) = do
  compileVar vm arg
  emit PUSH
  compileVar vm closure
  emit TAILAPPLY

compileTail vm depth (ALet fc var val body) = do
  compileExpr vm depth val
  emit LET
  let vm' = insert var (cast depth) vm
  compileTail vm' (S depth) body
  -- no ENDLET needed, tail call handles stack cleanup

compileTail vm depth (AConCase fc scr alts def) = do
  compileVar vm scr
  compileConCaseTail vm depth scr alts def

compileTail vm depth (AConstCase fc scr alts def) = do
  compileVar vm scr
  compileConstCaseTail vm depth scr alts def

compileTail vm depth e = do
  compileExpr vm depth e
  emit RETURN

------------------------------------------------------------------------
-- Case compilation: linear dispatch with jumps
--
-- For now, we compile cases inline with conditional jumps.
-- A future optimization could build jump tables for dense integer switches.
------------------------------------------------------------------------

||| Save the current compilation state for measuring code size.
saveState : {auto st : Ref CState CompileState} -> Core CompileState
saveState = get CState

||| Restore compilation state after a measuring pass.
restoreState : {auto st : Ref CState CompileState} -> CompileState -> Core ()
restoreState = put CState

||| Measure the number of instructions a compilation action would emit.
measureCode : {auto st : Ref CState CompileState} -> Core () -> Core Int
measureCode action = do
  saved <- saveState
  action
  after <- here
  restoreState saved
  before <- here
  pure (after - before)

||| Project constructor fields into environment slots.
||| The scrutinee is at env[scrSlot]. Each field is extracted and pushed to env.
projectFields : {auto st : Ref CState CompileState}
             -> VarMap -> Nat -> (scrSlot : Int) -> List Int -> Nat -> Core VarMap
projectFields vm depth scrSlot [] pos = pure vm
projectFields vm depth scrSlot (arg :: args) pos = do
  emit (ACCESS scrSlot)  -- reload scrutinee into accu
  emit (GETFIELD pos)
  emit LET
  let vm' = insert arg (cast (depth + pos)) vm
  projectFields vm' depth scrSlot args (S pos)

||| Compile a constructor alt body (non-tail). Scrutinee in accu on entry.
||| Emits: LET (save scrutinee), project fields, compile body, ENDLET, JUMP end
compileAltBody : {auto st : Ref CState CompileState}
              -> VarMap -> Nat -> AConAlt -> Core ()
compileAltBody vm depth (MkAConAlt n ci tag args body) = do
  emit LET  -- save scrutinee
  let scrSlot = cast depth
  let nargs = length args
  vm' <- projectFields vm (S depth) scrSlot args 0
  compileExpr vm' (S depth + nargs) body
  emit (ENDLET (S nargs))

||| Compile a constructor alt body (tail position).
compileAltBodyTail : {auto st : Ref CState CompileState}
                  -> VarMap -> Nat -> AConAlt -> Core ()
compileAltBodyTail vm depth (MkAConAlt n ci tag args body) = do
  emit LET  -- save scrutinee
  let scrSlot = cast depth
  let nargs = length args
  vm' <- projectFields vm (S depth) scrSlot args 0
  compileTail vm' (S depth + nargs) body

||| Measure the size of each alt body + JUMP instruction.
measureAlts : {auto st : Ref CState CompileState}
           -> VarMap -> Nat -> (AConAlt -> Core ()) -> List AConAlt -> Core (List Int)
measureAlts vm depth compileBody [] = pure []
measureAlts vm depth compileBody (alt :: alts) = do
  sz <- measureCode (do compileBody alt; emit (JUMP 0))  -- +1 for JUMP
  rest <- measureAlts vm depth compileBody alts
  pure (sz :: rest)

||| Get the constructor tag from an AConAlt.
altTag : AConAlt -> Either Int Name
altTag (MkAConAlt _ _ (Just tag) _ _) = Left tag
altTag (MkAConAlt n _ Nothing _ _) = Right n

computePositions : Label -> List Int -> List Label
computePositions _ [] = []
computePositions pos (sz :: szs) = pos :: computePositions (pos + sz) szs

partitionTags : List (Either Int Name, Label) -> (List (Int, Label), List (Name, Label))
partitionTags [] = ([], [])
partitionTags ((Left tag, lab) :: rest) =
  let (is, ns) = partitionTags rest in ((tag, lab) :: is, ns)
partitionTags ((Right n, lab) :: rest) =
  let (is, ns) = partitionTags rest in (is, (n, lab) :: ns)

totalSize : List Int -> Int
totalSize = foldl (+) 0

compileConCase vm depth scr alts def = do
  -- Scrutinee is already in accu
  let compBody = compileAltBody vm depth
  sizes <- measureAlts vm depth compBody alts
  switchPos <- here
  let altPositions = computePositions (switchPos + 1) sizes
  let afterAlts = switchPos + 1 + totalSize sizes
  let taggedAlts = zip (map altTag alts) altPositions
  let (intAlts, nameAlts) = partitionTags taggedAlts
  let defLab = map (const afterAlts) def
  -- Measure default to compute real end label
  defSize <- case def of
    Just d  => measureCode (compileExpr vm depth d)
    Nothing => pure 0
  let endLab = afterAlts + defSize
  if isNil nameAlts
    then emit (SWITCH intAlts defLab)
    else emit (SWITCHNAME nameAlts defLab)
  -- Emit alt bodies with JUMP to end
  traverse_ (\alt => do compBody alt; emit (JUMP endLab)) alts
  case def of
    Just d  => compileExpr vm depth d
    Nothing => pure ()

compileConCaseTail vm depth scr alts def = do
  let compBody = compileAltBodyTail vm depth
  sizes <- measureAlts vm depth compBody alts
  switchPos <- here
  let altPositions = computePositions (switchPos + 1) sizes
  let afterAlts = switchPos + 1 + totalSize sizes
  let taggedAlts = zip (map altTag alts) altPositions
  let (intAlts, nameAlts) = partitionTags taggedAlts
  let defLab = map (const afterAlts) def
  if isNil nameAlts
    then emit (SWITCH intAlts defLab)
    else emit (SWITCHNAME nameAlts defLab)
  traverse_ compBody alts
  case def of
    Just d  => compileTail vm depth d
    Nothing => emit (ERROR "non-exhaustive case")

compileConstCase vm depth scr alts def = do
  let altBodies = map (\(MkAConstAlt c body) => (c, body)) alts
  sizes <- traverse (\(_, body) => measureCode (do compileExpr vm depth body; emit (JUMP 0))) altBodies
  switchPos <- here
  let altPositions = computePositions (switchPos + 1) sizes
  let afterAlts = switchPos + 1 + totalSize sizes
  let constAlts = zip (map fst altBodies) altPositions
  let defLab = map (const afterAlts) def
  defSize <- case def of
    Just d  => measureCode (compileExpr vm depth d)
    Nothing => pure 0
  let endLab = afterAlts + defSize
  emit (CONSTSWITCH constAlts defLab)
  traverse_ (\(_, body) => do compileExpr vm depth body; emit (JUMP endLab)) altBodies
  case def of
    Just d  => compileExpr vm depth d
    Nothing => pure ()

compileConstCaseTail vm depth scr alts def = do
  let altBodies = map (\(MkAConstAlt c body) => (c, body)) alts
  sizes <- traverse (\(_, body) => measureCode (compileTail vm depth body)) altBodies
  switchPos <- here
  let altPositions = computePositions (switchPos + 1) sizes
  let afterAlts = switchPos + 1 + totalSize sizes
  let constAlts = zip (map fst altBodies) altPositions
  let defLab = map (const afterAlts) def
  emit (CONSTSWITCH constAlts defLab)
  traverse_ (\(_, body) => compileTail vm depth body) altBodies
  case def of
    Just d  => compileTail vm depth d
    Nothing => emit (ERROR "non-exhaustive const case")

------------------------------------------------------------------------
-- Top-level compilation
------------------------------------------------------------------------

||| Build a VarMap from a list of ANF variable names, assigning sequential slots.
buildVarMap : List Int -> Int -> VarMap
buildVarMap [] _ = empty
buildVarMap (arg :: args) idx = insert arg idx (buildVarMap args (idx + 1))

||| Compile a single ANF function definition to ZAM bytecode.
compileFun : {auto st : Ref CState CompileState} -> Name -> ANFDef -> Core ()
compileFun n (MkAFun args body) = do
  lab <- here
  registerFun n lab
  let vm = buildVarMap args 0
  emitAll (replicate (length args) GRAB)
  compileTail vm (length args) body

compileFun n (MkAForeign ccs fargs ret) = do
  lab <- here
  registerFun n lab
  -- Foreign functions: GRAB all args, then call EXTPRIM
  let nargs = length fargs
  emitAll (replicate nargs GRAB)
  -- Push env args onto stack for EXTPRIM (ACCESS i, PUSH for each)
  emitAll (concatMap (\i => [ACCESS (cast i), PUSH]) [0 .. cast nargs - 1])
  emit (EXTPRIM n nargs)
  emit RETURN

compileFun n (MkACon _ _ _) = pure ()

compileFun n (MkAError body) = do
  lab <- here
  registerFun n lab
  compileTail empty 0 body

||| Pre-register all function names with dummy labels so lookups always succeed.
preRegister : {auto st : Ref CState CompileState} -> List (Name, ANFDef) -> Core ()
preRegister [] = pure ()
preRegister ((n, MkACon _ _ _) :: rest) = preRegister rest
preRegister ((n, _) :: rest) = do registerFun n (-1); preRegister rest

||| Compile all ANF definitions to a flat ZAM bytecode program.
||| Two-pass approach: pre-register so instruction emission is deterministic,
||| compile once for correct labels, then recompile with those labels.
export
compileAll : List (Name, ANFDef) -> Core (List ZInst, SortedMap Name Label)
compileAll defs = do
  st <- newRef CState initState
  -- Pass 1: pre-register with dummies, compile to discover real labels
  preRegister defs
  traverse_ (\(n, d) => compileFun n d) defs
  s1 <- get CState
  let knownLabels = s1.funLabels
  -- Pass 2: recompile with correct labels
  put CState (MkCS 0 knownLabels [<])
  traverse_ (\(n, d) => compileFun n d) defs
  emit STOP
  s2 <- get CState
  pure (toList s2.code, s2.funLabels)
