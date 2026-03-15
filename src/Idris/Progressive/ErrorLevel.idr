module Idris.Progressive.ErrorLevel

import Core.Core
import Core.Context
import Core.TT

%default covering

||| Annotation level of a module:
|||   0 = no user type annotations
|||   1 = simple types only (explicit Pi, no polymorphism)
|||   2 = polymorphic types or typeclass constraints
|||   3 = multiplicity annotations
|||   4 = dependent types
public export
AnnotationLevel : Type
AnnotationLevel = Nat

||| Classify a single type term by its annotation complexity.
||| Walks Pi binders and returns the max level found.
export
classifyType : Term vars -> AnnotationLevel
classifyType (Bind _ _ (Pi _ rig info _) scope) =
  let infoLevel : Nat
      infoLevel = case info of
                    Implicit     => 2
                    AutoImplicit => 2
                    DefImplicit _ => 2
                    Explicit     => 0
      rigLevel : Nat
      rigLevel = if isErased rig || isLinear rig then 3 else 0
      rest = classifyType scope
  in max infoLevel (max rigLevel rest)
classifyType (Bind _ _ _ scope) = classifyType scope
classifyType _ = 0

||| Check whether a Name belongs to the given Namespace (exact match).
isInNS : Namespace -> Name -> Bool
isInNS ns (NS n _) = ns == n
isInNS _ _ = False

||| Detect the annotation level of the current module.
||| Iterates definitions in the current namespace, skipping those
||| with SynthesisedType (inferred types). Returns the max level
||| across all user-annotated definitions.
||| Returns 0 if no user annotations exist.
export
detectAnnotationLevel : {auto c : Ref Ctxt Defs} -> Core AnnotationLevel
detectAnnotationLevel = do
  defs <- get Ctxt
  let ns = currentNS defs
  names <- allNames (gamma defs)
  lvls <- traverse (checkName defs ns) names
  pure (foldl max 0 lvls)
  where
    checkName : Defs -> Namespace -> Name -> Core AnnotationLevel
    checkName defs ns n =
      if isInNS ns n
        then do Just gdef <- lookupCtxtExact n (gamma defs)
                  | Nothing => pure 0
                if elem SynthesisedType (flags gdef)
                  then pure 0
                  else pure (max 1 (classifyType (type gdef)))
        else pure 0

||| Check whether the current module has any definitions with
||| SynthesisedType (no user-provided type annotation).
||| This indicates "progressive mode" usage.
export
hasProgressiveDefinitions : {auto c : Ref Ctxt Defs} -> Core Bool
hasProgressiveDefinitions = do
  defs <- get Ctxt
  let ns = currentNS defs
  names <- allNames (gamma defs)
  anyInNS defs ns names
  where
    isDefinedDef : Def -> Bool
    isDefinedDef (PMDef {}) = True
    isDefinedDef _ = False

    anyInNS : Defs -> Namespace -> List Name -> Core Bool
    anyInNS defs ns [] = pure False
    anyInNS defs ns (n :: rest) =
      if isInNS ns n
        then do Just gdef <- lookupCtxtExact n (gamma defs)
                  | Nothing => anyInNS defs ns rest
                if elem SynthesisedType (flags gdef)
                     && isDefinedDef (definition gdef)
                  then pure True
                  else anyInNS defs ns rest
        else anyInNS defs ns rest

||| Should we use beginner-friendly error messages?
||| True when the module is in progressive mode (has unannotated definitions)
||| AND the annotation level < 2 (no polymorphism/constraints).
export
useBeginnerMessages : {auto c : Ref Ctxt Defs} -> Core Bool
useBeginnerMessages = do
  progressive <- hasProgressiveDefinitions
  if progressive
    then do lvl <- detectAnnotationLevel
            pure (lvl < 2)
    else pure False
