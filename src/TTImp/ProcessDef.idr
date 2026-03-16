module TTImp.ProcessDef

import Core.Case.CaseBuilder
import Core.Case.CaseTree
import Core.Case.CaseTree.Pretty
import Core.Coverage
import Core.Env
import Core.Hash
import Core.LinearCheck
import Core.Metadata
import Core.Termination
import Core.Termination.CallGraph
import Core.Transform
import Core.Value
import Core.Unify
import Core.UnifyState

import Idris.REPL.Opts
import Idris.Syntax
import Idris.Pretty.Annotations

import TTImp.BindImplicits
import TTImp.Elab
import TTImp.Elab.Binders
import TTImp.Elab.Check
import TTImp.Elab.Utils
import TTImp.Impossible
import TTImp.PartialEval
import TTImp.TTImp
import TTImp.TTImp.Functor
import TTImp.ProcessType
import TTImp.Unelab
import TTImp.WithClause

import Data.Either
import Data.List
import Data.String
import Data.Maybe
import Libraries.Data.IntMap
import Libraries.Data.NameMap
import Libraries.Data.NatSet
import Libraries.Data.WithDefault
import Libraries.Text.PrettyPrint.Prettyprinter
import Libraries.Data.List.SizeOf

%default covering

mutual
  mismatchNF : {auto c : Ref Ctxt Defs} ->
               {vars : _} ->
               Defs -> NF vars -> NF vars -> Core Bool
  mismatchNF defs (NTCon _ xn _ xargs) (NTCon _ yn _ yargs)
      = if xn /= yn
           then pure True
           else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
  mismatchNF defs (NDCon _ _ xt _ xargs) (NDCon _ _ yt _ yargs)
      = if xt /= yt
           then pure True
           else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
  mismatchNF defs (NPrimVal _ xc) (NPrimVal _ yc) = pure (xc /= yc)
  mismatchNF defs (NDelayed _ _ x) (NDelayed _ _ y) = mismatchNF defs x y
  mismatchNF defs (NDelay _ _ _ x) (NDelay _ _ _ y)
      = mismatchNF defs !(evalClosure defs x) !(evalClosure defs y)

  -- NPrimVal is apart from NDCon, NTCon, NBind, and NType
  mismatchNF defs (NPrimVal {}) (NDCon {}) = pure True
  mismatchNF defs (NDCon {}) (NPrimVal {}) = pure True
  mismatchNF defs (NPrimVal {}) (NBind {}) = pure True
  mismatchNF defs (NBind {}) (NPrimVal {}) = pure True
  mismatchNF defs (NPrimVal {}) (NTCon {}) = pure True
  mismatchNF defs (NTCon {}) (NPrimVal {}) = pure True
  mismatchNF defs (NPrimVal {}) (NType {}) = pure True
  mismatchNF defs (NType {}) (NPrimVal {}) = pure True

-- NTCon is apart from NBind, and NType
  mismatchNF defs (NTCon {}) (NBind {}) = pure True
  mismatchNF defs (NBind {}) (NTCon {}) = pure True
  mismatchNF defs (NTCon {}) (NType {}) = pure True
  mismatchNF defs (NType {}) (NTCon {}) = pure True

-- NBind is apart from NType
  mismatchNF defs (NBind {}) (NType {}) = pure True
  mismatchNF defs (NType {}) (NBind {}) = pure True

  mismatchNF _ _ _ = pure False

  mismatch : {auto c : Ref Ctxt Defs} ->
             {vars : _} ->
             Defs -> (Closure vars, Closure vars) -> Core Bool
  mismatch defs (x, y)
      = mismatchNF defs !(evalClosure defs x) !(evalClosure defs y)

-- If the terms have the same type constructor at the head, and one of
-- the argument positions has different constructors at its head, then this
-- is an impossible case, so return True
export
impossibleOK : {auto c : Ref Ctxt Defs} ->
               {vars : _} ->
               Defs -> NF vars -> NF vars -> Core Bool
impossibleOK defs (NTCon _ xn xa xargs) (NTCon _ yn ya yargs)
    = if xn /= yn
         then pure True
         else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
-- If it's a data constructor, any mismatch will do
impossibleOK defs (NDCon _ _ xt _ xargs) (NDCon _ _ yt _ yargs)
    = if xt /= yt
         then pure True
         else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
impossibleOK defs (NPrimVal _ x) (NPrimVal _ y) = pure (x /= y)

-- NPrimVal is apart from NDCon, NTCon, NBind, and NType
impossibleOK defs (NPrimVal {}) (NDCon {}) = pure True
impossibleOK defs (NDCon {}) (NPrimVal {}) = pure True
impossibleOK defs (NPrimVal {}) (NBind {}) = pure True
impossibleOK defs (NBind {}) (NPrimVal {}) = pure True
impossibleOK defs (NPrimVal {}) (NTCon {}) = pure True
impossibleOK defs (NTCon {}) (NPrimVal {}) = pure True
impossibleOK defs (NPrimVal {}) (NType {}) = pure True
impossibleOK defs (NType {}) (NPrimVal {}) = pure True

-- NTCon is apart from NBind, and NType
impossibleOK defs (NTCon {}) (NBind {}) = pure True
impossibleOK defs (NBind {}) (NTCon {}) = pure True
impossibleOK defs (NTCon {}) (NType {}) = pure True
impossibleOK defs (NType {}) (NTCon {}) = pure True

-- NBind is apart from NType
impossibleOK defs (NBind {}) (NType {}) = pure True
impossibleOK defs (NType {}) (NBind {}) = pure True

impossibleOK defs x y = pure False

export
impossibleErrOK : {auto c : Ref Ctxt Defs} ->
                  Defs -> Error -> Core Bool
impossibleErrOK defs (CantConvert fc gam env l r)
    = do let defs = { gamma := gam } defs
         impossibleOK defs !(nf defs env l)
                           !(nf defs env r)
impossibleErrOK defs (CantSolveEq fc gam env l r)
    = do let defs = { gamma := gam } defs
         impossibleOK defs !(nf defs env l)
                           !(nf defs env r)
impossibleErrOK defs (CyclicMeta {}) = pure True
impossibleErrOK defs (AllFailed errs)
    = allM (impossibleErrOK defs) (map snd errs)
impossibleErrOK defs (WhenUnifying _ _ _ _ _ err)
    = impossibleErrOK defs err
impossibleErrOK defs ImpossibleCase = pure True
impossibleErrOK defs _ = pure False

-- Given a type checked LHS and its type, return the environment in which we
-- should check the RHS, the LHS and its type in that environment,
-- and a function which turns a checked RHS into a
-- pattern clause
-- The 'Thin' proof contains a proof that refers to the *inner* environment,
-- so all the outer things are marked as 'Drop'
extendEnv : {vars : _} ->
            Env Term vars -> Thin inner vars ->
            NestedNames vars ->
            Term vars -> Term vars ->
            Core (vars' **
                    (Thin inner vars',
                     Env Term vars', NestedNames vars',
                     Term vars', Term vars'))
extendEnv env p nest (Bind _ n (PVar fc c pi tmty) sc) (Bind _ n' (PVTy {}) tysc) with (nameEq n n')
  extendEnv env p nest (Bind _ n (PVar fc c pi tmty) sc) (Bind _ n' (PVTy {}) tysc) | Nothing
      = throw (InternalError "Can't happen: names don't match in pattern type")
  extendEnv env p nest (Bind _ n (PVar fc c pi tmty) sc) (Bind _ n (PVTy {}) tysc) | (Just Refl)
      = extendEnv (PVar fc c pi tmty :: env) (Drop p) (weaken (dropName n nest)) sc tysc
extendEnv env p nest (Bind _ n (PLet fc c tmval tmty) sc) (Bind _ n' (PLet {}) tysc) with (nameEq n n')
  extendEnv env p nest (Bind _ n (PLet fc c tmval tmty) sc) (Bind _ n' (PLet {}) tysc) | Nothing
      = throw (InternalError "Can't happen: names don't match in pattern type")
  -- PLet on the left becomes Let on the right, to give it computational force
  extendEnv env p nest (Bind _ n (PLet fc c tmval tmty) sc) (Bind _ n (PLet {}) tysc) | (Just Refl)
      = extendEnv (Let fc c tmval tmty :: env) (Drop p) (weaken (dropName n nest)) sc tysc
extendEnv env p nest tm ty
      = pure (_ ** (p, env, nest, tm, ty))

-- Find names which are applied to a function in a Rig1/Rig0 position,
-- so that we know how they should be bound on the right hand side of the
-- pattern.
-- 'bound' counts the number of variables locally bound; these are the
-- only ones we're checking linearity of (we may be shadowing names if this
-- is a local definition, so we need to leave the earlier ones alone)
findLinear : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             Bool -> Nat -> RigCount -> Term vars ->
             Core (List (Name, RigCount))
findLinear top bound rig (Bind fc n b sc)
    = findLinear top (S bound) rig sc
findLinear top bound rig (As fc _ _ p)
    = findLinear top bound rig p
findLinear top bound rig tm
    = case getFnArgs tm of
           (Ref _ _ n, []) => pure []
           (Ref _ nt n, args)
              => do defs <- get Ctxt
                    Just nty <- lookupTyExact n (gamma defs)
                         | Nothing => pure []
                    findLinArg (accessible nt rig) !(nf defs Env.empty nty) args
           _ => pure []
    where
      accessible : NameType -> RigCount -> RigCount
      accessible Func r = if top then r else erased
      accessible _ r = r

      findLinArg : {vars : _} ->
                   RigCount -> ClosedNF -> List (Term vars) ->
                   Core (List (Name, RigCount))
      findLinArg rig ty@(NBind _ _ (Pi _ c _ _) _) (As fc u a p :: as)
          = if isLinear c
               then case u of
                         UseLeft => findLinArg rig ty (p :: as)
                         UseRight => findLinArg rig ty (a :: as)
               else pure $ !(findLinArg rig ty [a]) ++ !(findLinArg rig ty (p :: as))
      findLinArg rig (NBind _ x (Pi _ c _ _) sc) (Local {name=a} fc _ idx prf :: as)
          = do defs <- get Ctxt
               let a = nameAt prf
               if idx < bound
                 then do sc' <- sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x))
                         pure $ (a, rigMult c rig) ::
                                    !(findLinArg rig sc' as)
                 else do sc' <- sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x))
                         findLinArg rig sc' as
      findLinArg rig (NBind fc x (Pi _ c _ _) sc) (a :: as)
          = do defs <- get Ctxt
               pure $ !(findLinear False bound (c |*| rig) a) ++
                      !(findLinArg rig !(sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x))) as)
      findLinArg rig ty (a :: as)
          = pure $ !(findLinear False bound rig a) ++ !(findLinArg rig ty as)
      findLinArg _ _ [] = pure []

setLinear : List (Name, RigCount) -> Term vars -> Term vars
setLinear vs tm@(Bind fc x b sc)
    = if isPatternBinder b
         then let b' = maybe b (setMultiplicity b) (lookup x vs)
               in Bind fc x b' (setLinear vs sc)
         else tm
  where
    isPatternBinder : Binder a -> Bool
    isPatternBinder (PVar {}) = True
    isPatternBinder (PVTy {}) = True
    isPatternBinder (PLet {}) = True
    isPatternBinder _ = False
setLinear vs tm = tm

-- Combining multiplicities on LHS:
-- Rig1 + Rig1/W not valid, since it means we have repeated use of name
-- Rig0 + RigW = RigW
-- Rig0 + Rig1 = Rig1
combineLinear : FC -> List (Name, RigCount) ->
                Core (List (Name, RigCount))
combineLinear loc [] = pure []
combineLinear loc ((n, count) :: cs)
    = case lookupAll n cs of
           [] => pure $ (n, count) :: !(combineLinear loc cs)
           counts => do count' <- combineAll count counts
                        pure $ (n, count') ::
                               !(combineLinear loc (filter notN cs))
  where
    notN : (Name, RigCount) -> Bool
    notN (n', _) = n /= n'

    lookupAll : Name -> List (Name, RigCount) -> List RigCount
    lookupAll n [] = []
    lookupAll n ((n', c) :: cs)
       = if n == n' then c :: lookupAll n cs else lookupAll n cs

    -- Those combine rules are obtuse enough that they are worth investigating
    combine : RigCount -> RigCount -> Core RigCount
    combine l r = if l |+| r == top && not (isErased $ l `glb` r) && (l `glb` r) /= top
                     then throw (LinearUsed loc 2 n)
                     -- if everything is fine, return the linearity that has the
                     -- highest bound
                     else pure (l `lub` r)

    combineAll : RigCount -> List RigCount -> Core RigCount
    combineAll c [] = pure c
    combineAll c (c' :: cs)
        = do newc <- combine c c'
             combineAll newc cs

export -- also used by Transforms
checkLHS : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto m : Ref MD Metadata} ->
           {auto u : Ref UST UState} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           Bool -> -- in transform
           (mult : RigCount) ->
           Int -> List ElabOpt -> NestedNames vars -> Env Term vars ->
           FC -> RawImp ->
           Core (RawImp, -- checked LHS with implicits added
                 (vars' ** (Thin vars vars',
                           Env Term vars', NestedNames vars',
                           Term vars', Term vars')))
checkLHS {vars} trans mult n opts nest env fc lhs_in
    = do defs <- get Ctxt
         logRaw "declare.def.lhs" 30 "Raw LHS: " lhs_in
         lhs_raw <- if trans
                       then pure lhs_in
                       else lhsInCurrentNS nest lhs_in
         logRaw "declare.def.lhs" 30 "Raw LHS in current NS: " lhs_raw

         autoimp <- isUnboundImplicits
         setUnboundImplicits True
         (_, lhs_bound) <- bindNames False lhs_raw
         setUnboundImplicits autoimp
         logRaw "declare.def.lhs" 30 "Raw LHS with implicits bound" lhs_bound

         lhs <- if trans
                   then pure lhs_bound
                   else implicitsAs n defs vars lhs_bound

         logC "declare.def.lhs" 5 $ do pure $ "Checking LHS of " ++ show !(getFullName (Resolved n))
-- todo: add Pretty RawImp instance
--         logC "declare.def.lhs" 5 $ do pure $ show $ indent {ann = ()} 2 $ pretty lhs
         log "declare.def.lhs" 10 $ show lhs
         logEnv "declare.def.lhs" 5 "In env" env
         let lhsMode = if trans
                          then InTransform
                          else InLHS mult
         (lhstm, lhstyg) <-
             wrapErrorC opts (InLHS fc !(getFullName (Resolved n))) $
                     elabTerm n lhsMode opts nest env
                                (IBindHere fc PATTERN lhs) Nothing
         logTerm "declare.def.lhs" 5 "Checked LHS term" lhstm
         lhsty <- getTerm lhstyg

         defs <- get Ctxt
         let lhsenv = letToLam env
         -- we used to fully normalise the LHS, to make sure fromInteger
         -- patterns were allowed, but now they're fully normalised anyway
         -- so we only need to do the holes. If there's a lot of type level
         -- computation, this is a huge saving!
         lhstm <- normaliseHoles defs lhsenv lhstm
         lhsty <- normaliseHoles defs env lhsty
         linvars_in <- findLinear True 0 linear lhstm
         logTerm "declare.def.lhs" 10 "Checked LHS term after normalise" lhstm
         log "declare.def.lhs" 5 $ "Linearity of names in " ++ show n ++ ": " ++
                 show linvars_in

         linvars <- combineLinear fc linvars_in
         let lhstm_lin = setLinear linvars lhstm
         let lhsty_lin = setLinear linvars lhsty

         logTerm "declare.def.lhs" 3 "LHS term" lhstm_lin
         logTerm "declare.def.lhs" 5 "LHS type" lhsty_lin
         setHoleLHS (bindEnv fc env lhstm_lin)

         ext <- extendEnv env Refl nest lhstm_lin lhsty_lin
         pure (lhs, ext)

-- Return whether any of the pattern variables are in a trivially empty
-- type, where trivally empty means one of:
--  * No constructors
--  * Every constructor of the family has a return type which conflicts with
--    the given constructor's type
hasEmptyPat : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              Defs -> Env Term vars -> Term vars -> Core Bool
hasEmptyPat defs env (Bind fc x b sc)
   = pure $ !(isEmpty defs env !(nf defs env (binderType b)))
            || !(hasEmptyPat defs (b :: env) sc)
hasEmptyPat defs env _ = pure False

-- For checking with blocks as nested names
applyEnv : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           Env Term vars -> Name ->
           Core (Name, (Maybe Name, List (Var vars), FC -> NameType -> Term vars))
applyEnv env withname
    = do n' <- resolveName withname
         pure (withname, (Just withname, reverse (allVarsNoLet env),
                  \fc, nt => applyTo fc
                         (Ref fc nt (Resolved n')) env))

-- Check a pattern clause, returning the component of the 'Case' expression it
-- represents, or Nothing if it's an impossible clause
export
checkClause : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto m : Ref MD Metadata} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} ->
              (mult : RigCount) -> (vis : Visibility) ->
              (totreq : TotalReq) -> (hashit : Bool) ->
              Int -> List ElabOpt -> NestedNames vars -> Env Term vars ->
              ImpClause -> Core (Either RawImp Clause)
checkClause mult vis totreq hashit n opts nest env (ImpossibleClause fc lhs)
    = do lhs_raw <- lhsInCurrentNS nest lhs
         handleUnify
           (do autoimp <- isUnboundImplicits
               setUnboundImplicits True
               (_, lhs) <- bindNames False lhs_raw
               setUnboundImplicits autoimp

               log "declare.def.clause.impossible" 5 $ "Checking " ++ show lhs
               logEnv "declare.def.clause.impossible" 5 "In env" env
               (lhstm, lhstyg) <-
                           elabTerm n (InLHS mult) opts nest env
                                      (IBindHere fc COVERAGE lhs) Nothing
               defs <- get Ctxt
               lhs <- normaliseHoles defs env lhstm
               if !(hasEmptyPat defs env lhs)
                  then pure (Left lhs_raw)
                  else throw (ValidCase fc env (Left lhs)))
           (\err =>
              case err of
                   ValidCase {} => throw err
                   _ => do defs <- get Ctxt
                           if !(impossibleErrOK defs err)
                              then pure (Left lhs_raw)
                              else throw (ValidCase fc env (Right err)))
checkClause {vars} mult vis totreq hashit n opts nest env (PatClause fc lhs_in rhs)
    = do (_, (vars'  ** (sub', env', nest', lhstm', lhsty'))) <-
             checkLHS False mult n opts nest env fc lhs_in
         let rhsMode = if isErased mult then InType else InExpr
         log "declare.def.clause" 5 $ "Checking RHS " ++ show rhs
         logEnv "declare.def.clause" 5 "In env" env'

         rhstm <- logTime 3 ("Check RHS " ++ show fc) $
                    wrapErrorC opts (InRHS fc !(getFullName (Resolved n))) $
                       checkTermSub n rhsMode opts nest' env' env sub' rhs (gnf env' lhsty')
         clearHoleLHS

         logTerm "declare.def.clause" 3 "RHS term" rhstm
         when hashit $
           do addHashWithNames lhstm'
              addHashWithNames rhstm
              log "module.hash" 15 "Adding hash for def."

         -- If the rhs is a hole, record the lhs in the metadata because we
         -- might want to split it interactively
         case rhstm of
              Meta {} =>
                 addLHS (getFC lhs_in) (length env) env' lhstm'
              _ => pure ()

         pure (Right (MkClause env' lhstm' rhstm))
-- TODO: (to decide) With is complicated. Move this into its own module?
checkClause {vars} mult vis totreq hashit n opts nest env
    (WithClause ifc lhs_in rig wval_raw mprf flags cs)
    = do (lhs, (vars'  ** (sub', env', nest', lhspat, reqty))) <-
             checkLHS False mult n opts nest env ifc lhs_in
         let wmode
               = if isErased mult || isErased rig then InType else InExpr

         (wval, gwvalTy) <- wrapErrorC opts (InRHS ifc !(getFullName (Resolved n))) $
                elabTermSub n wmode opts nest' env' env sub' wval_raw Nothing
         clearHoleLHS

         logTerm "declare.def.clause.with" 5 "With value (at quantity \{show rig})" wval
         logTerm "declare.def.clause.with" 3 "Required type" reqty
         wvalTy <- getTerm gwvalTy
         defs <- get Ctxt
         wval <- normaliseHoles defs env' wval
         wvalTy <- normaliseHoles defs env' wvalTy

         let (wevars ** withSub) = keepOldEnv sub' (snd (findSubEnv env' wval))
         logTerm "declare.def.clause.with" 5 "With value type" wvalTy
         log "declare.def.clause.with" 5 $ "Using vars " ++ show wevars

         let Just wval = shrink wval withSub
             | Nothing => throw (InternalError "Impossible happened: With abstraction failure #1")
         let Just wvalTy = shrink wvalTy withSub
             | Nothing => throw (InternalError "Impossible happened: With abstraction failure #2")
         -- Should the env be normalised too? If the following 'impossible'
         -- error is ever thrown, that might be the cause!
         let Just wvalEnv = shrinkEnv env' withSub
             | Nothing => throw (InternalError "Impossible happened: With abstraction failure #3")

         -- Abstracting over 'wval' in the scope of bNotReq in order
         -- to get the 'magic with' behaviour
         (wargs ** (scenv, var, binder)) <- bindWithArgs rig wvalTy ((,wval) <$> mprf) wvalEnv

         let bnr = bindNotReq vfc 0 env' withSub [] reqty
         let notreqns = fst bnr
         let notreqty = snd bnr

         rdefs <- if Syntactic `elem` flags
                     then clearDefs defs
                     else pure defs
         wtyScope <- replace rdefs scenv !(nf rdefs scenv (weakenNs (mkSizeOf wargs) wval))
                            var
                            !(nf rdefs scenv
                                 (weakenNs (mkSizeOf wargs) notreqty))
         let bNotReq = binder wtyScope

         -- The environment has some implicit and some explcit args, potentially,
         -- which is inconvenient since we have to know which is which when
         -- elaborating the application of the rhs function. So it's easier
         -- if we just make them all explicit - this type isn't visible to
         -- users anyway!
         let env' = mkExplicit env'

         let Just (reqns, envns, wtype) = bindReq vfc env' withSub [] bNotReq
             | Nothing => throw (InternalError "Impossible happened: With abstraction failure #4")

         -- list of argument names - 'Just' means we need to match the name
         -- in the with clauses to find out what the pattern should be.
         -- 'Nothing' means it's the with pattern (so wargn)
         let wargNames
                 = map Just reqns ++
                   Nothing :: map Just notreqns

         logTerm "declare.def.clause.with" 3 "With function type" wtype
         log "declare.def.clause.with" 5 $ "Argument names " ++ show wargNames

         wname <- genWithName !(prettyName !(toFullNames (Resolved n)))
         widx <- addDef wname ({flags $= (SetTotal totreq ::)}
                                    (newDef vfc wname (if isErased mult then erased else top)
                                      vars wtype (specified vis) None))

         let toWarg : Maybe (PiInfo RawImp, Name) -> List (Maybe Name, RawImp)
               := flip maybe (\pn => [(Nothing, IVar vfc (snd pn))]) $
                    (Nothing, wval_raw) ::
                    case mprf of
                      Nothing => []
                      Just _  =>
                       let fc = emptyFC in
                       let refl = IVar fc (NS builtinNS (UN $ Basic "Refl")) in
                       [(map snd mprf, INamedApp fc refl (UN $ Basic "x") wval_raw)]

         let rhs_in = gapply (IVar vfc wname)
                    $ map (\ nm => (Nothing, IVar vfc nm)) envns
                   ++ concatMap toWarg wargNames

         log "declare.def.clause.with" 3 $ "Applying to with argument " ++ show rhs_in
         rhs <- wrapErrorC opts (InRHS ifc !(getFullName (Resolved n))) $
             checkTermSub n wmode opts nest' env' env sub' rhs_in
                          (gnf env' reqty)

         -- Generate new clauses by rewriting the matched arguments
         cs' <- traverse (mkClauseWith 1 wname wargNames lhs) cs
         log "declare.def.clause.with" 3 $ "With clauses: " ++ show cs'

         -- Elaborate the new definition here
         nestname <- applyEnv env wname
         let nest'' = { names $= (nestname ::) } nest

         let wdef = IDef ifc wname cs'
         processDecl [] nest'' env wdef

         pure (Right (MkClause env' lhspat rhs))
  where
    vfc : FC
    vfc = virtualiseFC ifc

    bindWithArgs :
       (rig : RigCount) -> (wvalTy : Term xs) -> Maybe ((RigCount, Name), Term xs) ->
       (wvalEnv : Env Term xs) ->
       Core (ext : Scope
         ** ( Env Term (ext ++ xs)
            , Term (ext ++ xs)
            , (Term (ext ++ xs) -> Term xs)
            ))
    bindWithArgs {xs} rig wvalTy Nothing wvalEnv =
      let wargn : Name
          wargn = MN "warg" 0
          wargs : Scope
          wargs = [wargn]

          scenv : Env Term (wargs ++ xs)
                := Pi vfc top Explicit wvalTy :: wvalEnv

          var : Term (wargs ++ xs)
              := Local vfc (Just False) Z First

          binder : Term (wargs ++ xs) -> Term xs
                 := Bind vfc wargn (Pi vfc rig Explicit wvalTy)

      in pure (wargs ** (scenv, var, binder))

    bindWithArgs {xs} rig wvalTy (Just ((rigPrf, name), wval)) wvalEnv = do
      defs <- get Ctxt

      let eqName = NS builtinNS (UN $ Basic "Equal")
      Just (TCon ar _ _ _ _ _ _) <- lookupDefExact eqName (gamma defs)
        | _ => throw (InternalError "Cannot find builtin Equal")
      let eqTyCon = Ref vfc (TyCon ar) !(toResolvedNames eqName)

      let wargn : Name
          wargn = MN "warg" 0
          wargs : Scope
          wargs = [name, wargn]

          wvalTy' := weaken wvalTy
          eqTy : Term (MN "warg" 0 :: xs)
               := apply vfc eqTyCon
                           [ wvalTy'
                           , wvalTy'
                           , weaken wval
                           , Local vfc (Just False) Z First
                           ]

          scenv : Env Term (wargs ++ xs)
                := Pi vfc top Implicit eqTy
                :: Pi vfc top Explicit wvalTy
                :: wvalEnv

          var : Term (wargs ++ xs)
              := Local vfc (Just False) (S Z) (Later First)

          binder : Term (wargs ++ xs) -> Term xs
                 := \ t => Bind vfc wargn (Pi vfc rig Explicit wvalTy)
                         $ Bind vfc name  (Pi vfc rigPrf Implicit eqTy) t

      pure (wargs ** (scenv, var, binder))

    -- If it's 'Keep/Refl' in 'outprf', that means it was in the outer
    -- environment so we need to keep it in the same place in the 'with'
    -- function. Hence, turn it to Keep whatever
    keepOldEnv : {0 outer : _} -> {vs : _} ->
                 (outprf : Thin outer vs) -> Thin vs' vs ->
                 (vs'' : Scope ** Thin vs'' vs)
    keepOldEnv {vs} Refl p = (vs ** Refl)
    keepOldEnv {vs} p Refl = (vs ** Refl)
    keepOldEnv (Drop p) (Drop p')
        = let (_ ** rest) = keepOldEnv p p' in
              (_ ** Drop rest)
    keepOldEnv (Drop p) (Keep p')
        = let (_ ** rest) = keepOldEnv p p' in
              (_ ** Keep rest)
    keepOldEnv (Keep p) (Drop p')
        = let (_ ** rest) = keepOldEnv p p' in
              (_ ** Keep rest)
    keepOldEnv (Keep p) (Keep p')
        = let (_ ** rest) = keepOldEnv p p' in
              (_ ** Keep rest)

    -- Rewrite the clauses in the block to use an updated LHS.
    -- 'drop' is the number of additional with arguments we expect
    -- (i.e. the things to drop from the end before matching LHSs)
    mkClauseWith : (drop : Nat) -> Name ->
                   List (Maybe (PiInfo RawImp, Name)) ->
                   RawImp -> ImpClause ->
                   Core ImpClause
    mkClauseWith drop wname wargnames lhs (PatClause ploc patlhs rhs)
        = do log "declare.def.clause.with" 20 "PatClause"
             newlhs <- getNewLHS ploc drop nest wname wargnames lhs patlhs
             newrhs <- withRHS ploc drop wname wargnames rhs lhs
             pure (PatClause ploc newlhs newrhs)
    mkClauseWith drop wname wargnames lhs (WithClause ploc patlhs rig wval prf flags ws)
        = do log "declare.def.clause.with" 20 "WithClause"
             newlhs <- getNewLHS ploc drop nest wname wargnames lhs patlhs
             newwval <- withRHS ploc drop wname wargnames wval lhs
             ws' <- traverse (mkClauseWith (S drop) wname wargnames lhs) ws
             pure (WithClause ploc newlhs rig newwval prf flags ws')
    mkClauseWith drop wname wargnames lhs (ImpossibleClause ploc patlhs)
        = do log "declare.def.clause.with" 20 "ImpossibleClause"
             newlhs <- getNewLHS ploc drop nest wname wargnames lhs patlhs
             pure (ImpossibleClause ploc newlhs)

-- Calculate references for the given name, and recursively if they haven't
-- been calculated already
calcRefs : {auto c : Ref Ctxt Defs} ->
           (runtime : Bool) -> (aTotal : Name) -> (fn : Name) -> Core ()
calcRefs rt at fn
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact fn (gamma defs)
              | _ => pure ()
         let PMDef r cargs tree_ct tree_rt pats = definition gdef
              | _ => pure () -- not a function definition
         let refs : Maybe (NameMap Bool)
                  = if rt then refersToRuntimeM gdef else refersToM gdef
         let Nothing = refs
              | Just _ => pure () -- already done
         let tree : CaseTree cargs = if rt then tree_rt else tree_ct
         let metas = CaseTree.getMetas tree
         traverse_ addToSave (keys metas)
         let refs_all = addRefs at metas tree
         refs <- ifThenElse rt
                    (dropErased (keys refs_all) refs_all)
                    (pure refs_all)
         ignore $ ifThenElse rt
            (addDef fn ({ refersToRuntimeM := Just refs } gdef))
            (addDef fn ({ refersToM := Just refs } gdef))
         traverse_ (calcRefs rt at) (keys refs)
  where
    dropErased : List Name -> NameMap Bool -> Core (NameMap Bool)
    dropErased [] refs = pure refs
    dropErased (n :: ns) refs
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact n (gamma defs)
                  | Nothing => dropErased ns refs
             if multiplicity gdef /= erased
                then dropErased ns refs
                else dropErased ns (delete n refs)

-- Compile run time case trees for the given name
mkRunTime : {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            FC -> Name -> Core ()
mkRunTime fc n
    = do logC "compile.casetree" 5 $ do pure $ "Making run time definition for " ++ show !(toFullNames n)
         defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
              | _ => pure ()
         let cov = gdef.totality.isCovering
         -- If it's erased at run time, don't build the tree
         when (not (isErased $ multiplicity gdef)) $ do
           let PMDef r cargs tree_ct _ pats = definition gdef
                | _ => pure () -- not a function definition
           let ty = type gdef
           -- Prepare RHS of definitions, by erasing 0-multiplicities, and
           -- finding any applications to specialise (partially evaluate)
           pats' <- traverse (toErased (location gdef) (getSpec (flags gdef)))
                             pats

           let clauses_init = map (toClause (location gdef)) pats'
           clauses <- case cov of
                           MissingCases _ => do log "compile.casetree.missing" 5 $ "Adding uncovered error to \{show clauses_init}"
                                                pure $ addErrorCase clauses_init
                           _ => pure clauses_init

           (rargs ** (tree_rt, _)) <- getPMDef (location gdef) RunTime n ty clauses
           logC "compile.casetree" 5 $ do
             tree_rt <- toFullNames tree_rt
             pure $ unlines
               [ show cov ++ ":"
               , "Runtime tree for " ++ show (fullname gdef) ++ ":"
               , show (indent 2 $ prettyTree tree_rt)
               ]
           log "compile.casetree" 10 $ show tree_rt
           log "compile.casetree.measure" 15 $ show (measure tree_rt)

           let Just Refl = scopeEq cargs rargs
                   | Nothing => throw (InternalError "WAT")
           ignore $ addDef n $
                       { definition := PMDef r rargs tree_ct tree_rt pats
                       } gdef
           -- If it's a case block, and not already set as inlinable or forced
           -- to not be inlinable, check if it's safe to inline
           when (caseName !(toFullNames n) && noInline (flags gdef)) $
             do inl <- canInlineCaseBlock n
                when inl $ do
                  logC "compiler.inline.eval" 5 $ do pure "Marking \{show !(toFullNames n)} for inlining in runtime case tree."
                  setFlag fc n Inline
  where
    -- check if the flags contain explicit inline or noinline directives:
    noInline : List DefFlag -> Bool
    noInline (Inline :: _)   = False
    noInline (NoInline :: _) = False
    noInline (x :: xs) = noInline xs
    noInline _ = True

    caseName : Name -> Bool
    caseName (CaseBlock {}) = True
    caseName (NS _ n) = caseName n
    caseName _ = False

    mkCrash : {vars : _} -> String -> Term vars
    mkCrash msg
       = apply fc (Ref fc Func (UN $ Basic "prim__crash"))
               [Erased fc Placeholder, PrimVal fc (Str msg)]

    matchAny : Term vars -> Term vars
    matchAny (App fc f a) = App fc (matchAny f) (Erased fc Placeholder)
    matchAny tm = tm

    makeErrorClause : {vars : _} -> Env Term vars -> Term vars -> Clause
    makeErrorClause env lhs
        = MkClause env (matchAny lhs)
             (mkCrash ("Unhandled input for " ++ show n ++ " at " ++ show fc))

    addErrorCase : List Clause -> List Clause
    addErrorCase [] = []
    addErrorCase [MkClause env lhs rhs]
        = MkClause env lhs rhs :: makeErrorClause env lhs :: []
    addErrorCase (x :: xs) = x :: addErrorCase xs

    getSpec : List DefFlag -> Maybe (List (Name, Nat))
    getSpec [] = Nothing
    getSpec (PartialEval n :: _) = Just n
    getSpec (x :: xs) = getSpec xs

    toErased : FC -> Maybe (List (Name, Nat)) ->
               (vars ** (Env Term vars, Term vars, Term vars)) ->
               Core (vars ** (Env Term vars, Term vars, Term vars))
    toErased fc spec (_ ** (env, lhs, rhs))
        = do lhs_erased <- linearCheck fc linear True env lhs
             -- Partially evaluate RHS here, where appropriate
             rhs' <- applyTransforms env rhs
             rhs' <- applySpecialise env spec rhs'
             rhs_erased <- linearCheck fc linear True env rhs'
             pure (_ ** (env, lhs_erased, rhs_erased))

    toClause : FC -> (vars ** (Env Term vars, Term vars, Term vars)) -> Clause
    toClause fc (_ ** (env, lhs, rhs))
        = MkClause env lhs rhs

compileRunTime : {auto c : Ref Ctxt Defs} ->
                 {auto m : Ref MD Metadata} ->
                 {auto u : Ref UST UState} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 FC -> Name -> Core ()
compileRunTime fc atotal
    = do defs <- get Ctxt
         traverse_ (mkRunTime fc) (toCompileCase defs)
         traverse_ (calcRefs True atotal) (toCompileCase defs)

         update Ctxt { toCompileCase := [] }

toPats : Clause -> (vs ** (Env Term vs, Term vs, Term vs))
toPats (MkClause {vars} env lhs rhs)
    = (_ ** (env, lhs, rhs))

warnUnreachable : {auto c : Ref Ctxt Defs} ->
                  Clause -> Core ()
warnUnreachable (MkClause env lhs rhs)
    = recordWarning (UnreachableClause (getLoc lhs) env lhs)

isAlias : RawImp -> Maybe ((FC, Name)              -- head symbol
                          , List (FC, (FC, Name))) -- pattern variables
isAlias lhs
  = do let (hd, apps) = getFnArgs lhs []
       hd <- isIVar hd
       args <- traverse (isExplicit >=> bitraverse pure isIBindVar) apps
       pure (hd, args)

-- Pre-scan LHS and RHS patterns across clauses to infer argument and return
-- types from constructors. Synthesizes a type and registers it via processType.
-- Returns the newly-registered GlobalDef, or Nothing if no clauses/LHS found.
synthTypeFromPatterns : {vars : _} ->
                        {auto m : Ref MD Metadata} ->
                        {auto c : Ref Ctxt Defs} ->
                        {auto u : Ref UST UState} ->
                        {auto s : Ref Syn SyntaxInfo} ->
                        {auto o : Ref ROpts REPLOpts} ->
                        List ElabOpt -> NestedNames vars -> Env Term vars -> FC ->
                        Name -> List ImpClause -> Core (Maybe GlobalDef)
synthTypeFromPatterns eopts nest env fc n cs
  = do let Just firstLhs = getFirstLhs cs
         | Nothing => pure Nothing
       let (_, args) = getFnArgs firstLhs []
       let explicitArgs = mapMaybe isExplicit args
       argTypes <- guessAllArgTypes fc cs 0 explicitArgs
       mRetTy <- guessReturnType fc cs
       let retTy = fromMaybe (Implicit fc False) mRetTy
       -- Decide between IBindVar and Implicit for HOF function types.
       -- IBindVar + prependImplicitPis: puts HOF type vars at outer scope,
       --   needed when arity > 1 (avoids Pi-scoped codomain problem).
       --   But fails for multiple HOF args (rigid vars can't unify cross-arg).
       -- Implicit: creates flexible metas that allow cross-arg unification
       --   (e.g., compose's g-codomain = f-domain), but fails for arity > 1
       --   due to Pi-scoped metas.
       -- Strategy: count HOF-enhanced positions. Single HOF arg → IBindVar.
       --   Multiple HOF args → Implicit (flexible cross-arg unification).
       let argTypesBV = enhanceWithHOFAnalysis fc cs 0 True explicitArgs argTypes
       let hofCount = countHOFEnhanced argTypes argTypesBV
       let useBindVars = hofCount <= 1
       let argTypes' = if useBindVars then argTypesBV
                          else enhanceWithHOFAnalysis fc cs 0 False explicitArgs argTypes
       log "declare.def" 10 $ "After HOF analysis (bindVars=" ++ show useBindVars
                           ++ ", hofCount=" ++ show hofCount ++ "): " ++ show argTypes'
       let hofVars = collectAllBindVars argTypes' retTy
       let synthType = if useBindVars && not (null hofVars)
             then let argTypes'' = map bindVarsToVars argTypes'
                      retTy' = bindVarsToVars retTy
                      innerType = buildSynthType fc 0 argTypes'' retTy'
                  in prependImplicitPis fc hofVars innerType
             else buildSynthType fc 0 argTypes' retTy
       log "declare.def" 5 $
         "No type declaration for " ++ show n
         ++ " (" ++ show (length explicitArgs) ++ " args). "
         ++ "Synthesized type from patterns."
       log "declare.def" 10 $ "Synthesized type: " ++ show synthType
       processType eopts nest env fc top Public []
          $ Mk [fc, MkFCVal fc n] synthType
       -- Mark all unsolved holes in the synthesized type as constSolvable.
       -- This is needed when pattern matching substitutes constructor
       -- arguments into hole args (e.g., return type or implicit type params).
       do defs <- get Ctxt
          Just gdef <- lookupCtxtExact n (gamma defs)
            | Nothing => pure ()
          markSynthHoles (type gdef)
       -- Mark this definition as having a synthesised type, but only if
       -- it has function arguments. Zero-argument constants (like `x = 3`)
       -- don't benefit from type generalisation and should just default.
       when (not (null explicitArgs)) $
         setFlag fc n SynthesisedType
       defs <- get Ctxt
       lookupCtxtExact n (gamma defs)
  where
    getFirstLhs : List ImpClause -> Maybe RawImp
    getFirstLhs (PatClause _ lhs _ :: _) = Just lhs
    getFirstLhs (_ :: rest) = getFirstLhs rest
    getFirstLhs [] = Nothing

    getRetTy : Defs -> ClosedNF -> Core (Maybe (Name, ClosedNF))
    getRetTy defs (NBind bfc _ (Pi {}) sc)
        = getRetTy defs !(sc defs (toClosure defaultOpts Env.empty (Erased bfc Placeholder)))
    getRetTy defs (NTCon _ tn _ _)
        = do Just ty <- lookupTyExact tn (gamma defs)
                  | Nothing => pure Nothing
             pure (Just (tn, !(nf defs Env.empty ty)))
    getRetTy _ _ = pure Nothing

    applyTo : Defs -> RawImp -> ClosedNF -> Core RawImp
    applyTo defs ty (NBind bfc _ (Pi _ _ Explicit _) sc)
        = applyTo defs (IApp bfc ty (Implicit bfc False))
               !(sc defs (toClosure defaultOpts Env.empty (Erased bfc Placeholder)))
    applyTo defs ty (NBind bfc x (Pi {}) sc)
        = applyTo defs (INamedApp bfc ty x (Implicit bfc False))
               !(sc defs (toClosure defaultOpts Env.empty (Erased bfc Placeholder)))
    applyTo defs ty _ = pure ty

    -- Try to resolve a constructor name to its parent type
    resolveConName : FC -> Name -> Core (Maybe RawImp)
    resolveConName fc pn
      = do defs <- get Ctxt
           results <- lookupTyName pn (gamma defs)
           case results of
                [(_, (_, ty))] =>
                  do tyNF <- nf defs Env.empty ty
                     Just (tyn, tyty) <- getRetTy defs tyNF
                       | Nothing => pure Nothing
                     Just <$> applyTo defs (IVar fc tyn) tyty
                _ => pure Nothing

    -- Try to guess a type from a pattern, handling IAlternative (pairs, etc.)
    guessFromPat : FC -> RawImp -> Core (Maybe RawImp)
    guessFromPat fc pat
      = do let patHead = getFn pat
           case patHead of
                IVar pfc pn => resolveConName fc pn
                IAlternative _ _ alts => tryAlts alts
                _ => pure Nothing
      where
        tryAlts : List RawImp -> Core (Maybe RawImp)
        tryAlts [] = pure Nothing
        tryAlts (alt :: alts)
          = do let altHead = getFn alt
               case altHead of
                    IVar _ pn =>
                      do Just res <- resolveConName fc pn
                           | Nothing => tryAlts alts
                         pure (Just res)
                    _ => tryAlts alts

    guessFromClauses : FC -> Nat -> List ImpClause -> Core (Maybe RawImp)
    guessFromClauses fc pos [] = pure Nothing
    guessFromClauses fc pos (PatClause _ lhs _ :: rest)
      = do let (_, args) = getFnArgs lhs []
           let explArgs = mapMaybe isExplicit args
           case drop pos (map snd explArgs) of
                (pat :: _) =>
                  do Just res <- guessFromPat fc pat
                       | Nothing => guessFromClauses fc pos rest
                     pure (Just res)
                [] => guessFromClauses fc pos rest
    guessFromClauses fc pos (_ :: rest) = guessFromClauses fc pos rest

    guessAllArgTypes : FC -> List ImpClause -> Nat -> List (FC, RawImp) -> Core (List RawImp)
    guessAllArgTypes fc cs pos [] = pure []
    guessAllArgTypes fc cs pos ((argfc, _) :: rest)
      = do mty <- guessFromClauses fc pos cs
           let argTy = fromMaybe (Implicit argfc False) mty
           rest' <- guessAllArgTypes fc cs (S pos) rest
           pure (argTy :: rest')

    -- HOF body analysis: detect when pattern variables are used as functions
    -- in clause bodies and compute their max explicit application arity.

    -- Get the IBindVar name from a pattern, if it is a variable pattern
    getBindName : RawImp -> Maybe Name
    getBindName (IBindVar _ n) = Just n
    getBindName _ = Nothing

    -- Collect all variable names at a given explicit-arg position across clauses
    argNamesAtPos : Nat -> List ImpClause -> List Name
    argNamesAtPos pos [] = []
    argNamesAtPos pos (PatClause _ lhs _ :: rest)
      = let (_, args) = getFnArgs lhs []
            explArgs = mapMaybe isExplicit args
        in case drop pos (map snd explArgs) of
                (pat :: _) => case getBindName pat of
                                   Just nm => nm :: argNamesAtPos pos rest
                                   Nothing => argNamesAtPos pos rest
                [] => argNamesAtPos pos rest
    argNamesAtPos pos (_ :: rest) = argNamesAtPos pos rest

    -- Scan a RawImp for applications where the head is a target variable.
    -- Returns list of (name, explicitArgCount).
    -- Handles both application chains and non-application constructs.
    scanAppsIn : List Name -> RawImp -> List (Name, Nat)
    scanAppsIn targets tm
      = let (hd, allArgs) = getFnArgs tm []
            explArgs = mapMaybe isExplicit allArgs
        in if null allArgs
              then -- Not an application chain; check special constructs
                   case tm of
                     ICase _ _ _ scrut alts =>
                       scanAppsIn targets scrut
                       ++ concatMap (\case PatClause _ _ rhs => scanAppsIn targets rhs
                                           _ => []) alts
                     ILet _ _ _ _ ty val sc =>
                       scanAppsIn targets ty
                       ++ scanAppsIn targets val
                       ++ scanAppsIn targets sc
                     ILocal _ _ body => scanAppsIn targets body
                     ILam _ _ _ _ ty sc =>
                       scanAppsIn targets ty ++ scanAppsIn targets sc
                     IUpdate _ _ inner => scanAppsIn targets inner
                     _ => []
              else -- Application chain: check head and recurse into args
                   (case hd of
                      IVar _ n => if elem n targets
                                     then [(n, length explArgs)]
                                     else []
                      _ => scanAppsIn targets hd)
                   ++ concatMap (scanAppsIn targets . unIArg) allArgs

    -- Compute max arity for a name from a list of (name, arity) pairs
    maxArityFor : Name -> List (Name, Nat) -> Nat
    maxArityFor n [] = 0
    maxArityFor n ((n', a) :: rest)
      = if n == n' then max a (maxArityFor n rest) else maxArityFor n rest

    -- Generate a function type with k arrows using IBindVar.
    -- Uses IBindVar so domain/codomain become implicit Pi binders at the
    -- OUTER level (via prependImplicitPis). This is needed when HOF args
    -- coexist with constructor-derived types, to give all metas the HOF
    -- type variables in their scope.
    -- E.g., for argPos=0, arity=1: (hof0_0 -> hof0_1)
    mkFuncTypeBindVars : FC -> Nat -> Nat -> Nat -> RawImp
    mkFuncTypeBindVars fc argPos idx Z
      = IBindVar fc (UN (Basic ("hof" ++ show argPos ++ "_" ++ show idx)))
    mkFuncTypeBindVars fc argPos idx (S k)
      = IPi fc top Explicit Nothing
            (IBindVar fc (UN (Basic ("hof" ++ show argPos ++ "_" ++ show idx))))
            (mkFuncTypeBindVars fc argPos (S idx) k)

    -- Generate a function type with k arrows using plain Implicit holes.
    -- Used for pure alias-shaped HOFs (all args are bare holes) where
    -- IBindHere in processType handles implicit binding naturally.
    -- E.g., for arity=1: (_ -> _)
    mkFuncTypeImplicit : FC -> Nat -> RawImp
    mkFuncTypeImplicit fc Z = Implicit fc False
    mkFuncTypeImplicit fc (S k)
      = IPi fc top Explicit Nothing
            (Implicit fc False)
            (mkFuncTypeImplicit fc k)

    -- Enhance guessed arg types with HOF body analysis.
    -- For each position where guessAllArgTypes returned a bare hole (Implicit),
    -- check if the arg is used as a function in the body and replace with
    -- a function type if so.
    -- When useBindVars is True, generates IBindVar-based types (for use
    -- with prependImplicitPis). When False, generates Implicit-based types
    -- (for pure alias-shaped HOFs where IBindHere handles binding).
    enhanceWithHOFAnalysis : FC -> List ImpClause -> Nat -> Bool -> List (FC, RawImp) -> List RawImp -> List RawImp
    enhanceWithHOFAnalysis fc cs pos useBindVars [] [] = []
    enhanceWithHOFAnalysis fc cs pos useBindVars ((argfc, _) :: restArgs) (argTy :: restTys)
      = let enhanced = case argTy of
              Implicit _ False =>
                let names = argNamesAtPos pos cs
                    allHits = concatMap (\cl => case cl of
                                PatClause _ _ rhs => scanAppsIn names rhs
                                _ => []) cs
                    maxA = foldl (\acc, n => max acc (maxArityFor n allHits)) 0 names
                in if maxA > 0
                      then if useBindVars
                              then mkFuncTypeBindVars argfc pos 0 maxA
                              else mkFuncTypeImplicit argfc maxA
                      else argTy
              _ => argTy
        in enhanced :: enhanceWithHOFAnalysis fc cs (S pos) useBindVars restArgs restTys
    enhanceWithHOFAnalysis _ _ _ _ _ _ = []

    -- Check if a RawImp is a numeric literal expression
    -- Covers: IPrimVal (BI _), IAlternative (UniqueDefault ...) [...],
    -- and IApp (IVar fromInteger) (IPrimVal (BI _))
    isNumericRHS : RawImp -> Bool
    isNumericRHS (IPrimVal _ (BI _)) = True
    isNumericRHS (IPrimVal _ (I _)) = True
    isNumericRHS (IAlternative _ (UniqueDefault _) _) = True
    isNumericRHS (IApp _ _ (IPrimVal _ (BI _))) = True
    isNumericRHS (IApp _ _ (IPrimVal _ (I _))) = True
    isNumericRHS _ = False

    guessReturnType : FC -> List ImpClause -> Core (Maybe RawImp)
    guessReturnType fc [] = pure Nothing
    guessReturnType fc (PatClause _ _ rhs :: rest)
      = do let rhsHead = getFn rhs
           case rhsHead of
                IVar pfc pn =>
                  do defs <- get Ctxt
                     results <- lookupTyName pn (gamma defs)
                     case results of
                          [(_, (_, ty))] =>
                            do tyNF <- nf defs Env.empty ty
                               case !(getRetTy defs tyNF) of
                                    Just (tyn, tyty) =>
                                      Just <$> applyTo defs (IVar fc tyn) tyty
                                    Nothing =>
                                      if isNumericRHS rhs
                                         then pure (Just (IPrimVal fc (PrT IntegerType)))
                                         else guessReturnType fc rest
                          _ => if isNumericRHS rhs
                                  then pure (Just (IPrimVal fc (PrT IntegerType)))
                                  else guessReturnType fc rest
                _ => if isNumericRHS rhs
                        then pure (Just (IPrimVal fc (PrT IntegerType)))
                        else guessReturnType fc rest
    guessReturnType fc (_ :: rest) = guessReturnType fc rest

    -- Mark a single hole as constSolvable if it exists and is still a Hole
    markHoleConstSolvable : Int -> Core ()
    markHoleConstSolvable idx
      = do defs <- get Ctxt
           Just gdef <- lookupCtxtExact (Resolved idx) (gamma defs)
             | Nothing => pure ()
           case definition gdef of
                Hole locs flags =>
                  do let flags' = { constSolvable := True } flags
                     updateDef (Resolved idx) (const (Just (Hole locs flags')))
                _ => pure ()

    -- Walk the synthesized type and mark all unsolved holes as constSolvable.
    -- These holes were created by processType for implicit type parameters
    -- and the return type; they may need constant-function solving when
    -- pattern matching substitutes constructors into their argument lists.
    markSynthHoles : {vars : _} -> Term vars -> Core ()
    markSynthHoles (Bind _ _ b scope)
      = do markSynthHoles (binderType b)
           markSynthHoles scope
    markSynthHoles (Meta _ _ idx args)
      = do markHoleConstSolvable idx
           traverse_ markSynthHoles args
    markSynthHoles (App _ f a) = do markSynthHoles f; markSynthHoles a
    markSynthHoles _ = pure ()

    buildSynthType : FC -> Int -> List RawImp -> RawImp -> RawImp
    buildSynthType fc _ [] retTy = retTy
    buildSynthType fc i (argTy :: rest) retTy
      = let vfc = virtualiseFC fc in
        IPi vfc top Explicit (Just (MN "arg" i)) argTy (buildSynthType fc (i + 1) rest retTy)

    -- Collect all IBindVar names from a RawImp (used to find HOF type vars)
    collectBindVars : RawImp -> List Name
    collectBindVars (IBindVar _ n) = [n]
    collectBindVars (IPi _ _ _ _ argTy retTy)
      = collectBindVars argTy ++ collectBindVars retTy
    collectBindVars (IApp _ f a) = collectBindVars f ++ collectBindVars a
    collectBindVars (INamedApp _ f _ a) = collectBindVars f ++ collectBindVars a
    collectBindVars _ = []

    -- Collect IBindVar names from all arg types and return type
    collectAllBindVars : List RawImp -> RawImp -> List Name
    collectAllBindVars argTys retTy
      = nub (concatMap collectBindVars argTys ++ collectBindVars retTy)

    -- Replace IBindVar references with IVar references in a RawImp.
    -- After manually prepending implicit Pi binders, IBindVar names
    -- become proper variable references (IVar), not implicit binding sites.
    bindVarsToVars : RawImp -> RawImp
    bindVarsToVars (IBindVar bfc n)
      = IVar bfc n
    bindVarsToVars (IPi pfc c pi mn argTy retTy)
      = IPi pfc c pi mn (bindVarsToVars argTy) (bindVarsToVars retTy)
    bindVarsToVars (IApp afc f a)
      = IApp afc (bindVarsToVars f) (bindVarsToVars a)
    bindVarsToVars (INamedApp afc f nm a)
      = INamedApp afc (bindVarsToVars f) nm (bindVarsToVars a)
    bindVarsToVars other = other

    -- Prepend implicit Pi binders for HOF type variables and convert
    -- IBindVar references to IVar. This ensures Implicit holes in the
    -- type are elaborated UNDER the implicit Pi binders, giving them
    -- the HOF type variables in their scope.
    prependImplicitPis : FC -> List Name -> RawImp -> RawImp
    prependImplicitPis fc [] ty = ty
    prependImplicitPis fc (n :: ns) ty
      = IPi fc erased Implicit (Just n) (IType fc)
            (prependImplicitPis fc ns ty)

    -- Check if a RawImp is just a bare unsolved hole (Implicit _ False).
    -- Used to distinguish constructor-derived arg types (e.g., List _)
    -- from unguessed arg types (plain holes).
    isImplicitHole : RawImp -> Bool
    isImplicitHole (Implicit _ False) = True
    isImplicitHole _ = False

    -- Count positions where an originally-Implicit arg was enhanced to a
    -- function type by HOF analysis.
    countHOFEnhanced : List RawImp -> List RawImp -> Nat
    countHOFEnhanced [] [] = 0
    countHOFEnhanced (orig :: origs) (enh :: enhs)
      = (if isImplicitHole orig && not (isImplicitHole enh) then 1 else 0)
        + countHOFEnhanced origs enhs
    countHOFEnhanced _ _ = 0

-- Check if any of the given names appear as function heads (applied to
-- at least one explicit argument) in a RawImp expression.
-- Used to detect higher-order function usage in clause bodies.
hasHOFUsage : List Name -> RawImp -> Bool
hasHOFUsage names tm
  = let (hd, allArgs) = getFnArgs tm []
        explArgs = mapMaybe isExplicit allArgs
    in if null allArgs
          then -- Not an application; check sub-constructs
               case tm of
                 ICase _ _ _ scrut alts =>
                   hasHOFUsage names scrut
                   || any (\case PatClause _ _ r => hasHOFUsage names r
                                 _ => False) alts
                 ILet _ _ _ _ ty val sc =>
                   hasHOFUsage names ty || hasHOFUsage names val || hasHOFUsage names sc
                 ILocal _ _ body => hasHOFUsage names body
                 ILam _ _ _ _ ty sc =>
                   hasHOFUsage names ty || hasHOFUsage names sc
                 IUpdate _ _ inner => hasHOFUsage names inner
                 _ => False
          else -- Application chain: check head and recurse into args
               (case hd of
                  IVar _ n => elem n names
                  _ => hasHOFUsage names hd)
               || any (hasHOFUsage names . unIArg) allArgs

lookupOrAddAlias : {vars : _} ->
                   {auto m : Ref MD Metadata} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   {auto s : Ref Syn SyntaxInfo} ->
                   {auto o : Ref ROpts REPLOpts} ->
                   List ElabOpt -> NestedNames vars -> Env Term vars -> FC ->
                   Name -> List ImpClause -> Core (Maybe GlobalDef)
lookupOrAddAlias eopts nest env fc n [cl@(PatClause _ lhs rhs)]
  = do defs <- get Ctxt
       log "declare.def.alias" 20 $ "Looking at \{show cl}"
       Nothing <- lookupCtxtExact n (gamma defs)
         | Just gdef => pure (Just gdef)
       -- No prior declaration:
       --   1) check whether it has the shape of an alias
       let Just (hd, args) = isAlias lhs
         | Nothing => synthTypeFromPatterns eopts nest env fc n [cl]
       --   1b) if any arg is used as a function in the body,
       --       delegate to synthTypeFromPatterns which does HOF analysis
       let False = hasHOFUsage (map (snd . snd) args) rhs
         | True => do log "declare.def" 5 $
                        "HOF usage detected for " ++ show n
                        ++ ", delegating to synthTypeFromPatterns"
                      synthTypeFromPatterns eopts nest env fc n [cl]
       --   2) check whether it could be a misspelling
       log "declare.def" 5 $
         "Missing type declaration for the alias "
         ++ show n
         ++ ". Checking first whether it is a misspelling."
       [] <- do -- get the candidates
                Just (str, kept) <- getSimilarNames n
                   | Nothing => pure []
                -- only keep the ones that haven't been defined yet
                decls <- for kept $ \ (cand, vis, weight) => do
                    Just gdef <- lookupCtxtExact cand (gamma defs)
                      | Nothing => pure Nothing -- should be impossible
                    let None = definition gdef
                      | _ => pure Nothing
                    pure (Just (cand, vis, weight))
                pure $ showSimilarNames (currentNS defs) n str $ catMaybes decls
          | (x :: xs) => throw (MaybeMisspelling (NoDeclaration fc n) (x ::: xs))
       --   3) declare an alias
       log "declare.def" 5 "Not a misspelling: go ahead and declare it!"
       processType eopts nest env fc top Public []
          -- See #3409
          $ Mk [fc, MkFCVal fc n] $ holeyType (map snd args)
       when (not (null args)) $
         setFlag fc n SynthesisedType
       defs <- get Ctxt
       lookupCtxtExact n (gamma defs)

  where
    holeyType : List (FC, Name) -> RawImp
    holeyType [] = Implicit fc False
    holeyType ((xfc, x) :: xs)
      = let xfc = virtualiseFC xfc in
        IPi xfc top Explicit (Just x) (Implicit xfc False)
      $ holeyType xs

-- Multi-clause or constructor-pattern definitions without type declaration.
-- Pre-scan LHS patterns to infer argument types from constructor heads,
-- then synthesize a type and register it via processType.
lookupOrAddAlias eopts nest env fc n cs
  = do defs <- get Ctxt
       Just gdef <- lookupCtxtExact n (gamma defs)
         | Nothing => synthTypeFromPatterns eopts nest env fc n cs
       pure (Just gdef)

----------------------------------------------------------------------
-- Type generalisation for synthesised types
--
-- After processDef elaborates clauses and builds the case tree,
-- any unsolved metavariables in the type represent positions that
-- are truly polymorphic. We generalise them by:
--   1. Prepending {0 a : Type} -> Pi binders for each unique unsolved meta
--   2. Replacing Meta nodes in the type with Local references
--   3. Weakening the case tree to account for the new args
--   4. Updating the PMDef's args and pats
----------------------------------------------------------------------

-- Collect unique meta indices from a term in order of first appearance
collectMetaInts : {vars : _} -> IntMap () -> Term vars -> (IntMap (), List Int)
collectMetaInts seen (Meta _ _ i _)
  = case lookup i seen of
      Just _ => (seen, [])
      Nothing => (insert i () seen, [i])
collectMetaInts seen (Bind _ _ b sc)
  = let (seen1, ms1) = collectMetaInts seen (binderType b)
        (seen2, ms2) = collectMetaInts seen1 sc
    in (seen2, ms1 ++ ms2)
collectMetaInts seen (App _ f a)
  = let (seen1, ms1) = collectMetaInts seen f
        (seen2, ms2) = collectMetaInts seen1 a
    in (seen2, ms1 ++ ms2)
collectMetaInts seen (As _ _ as pat)
  = let (seen1, ms1) = collectMetaInts seen as
        (seen2, ms2) = collectMetaInts seen1 pat
    in (seen2, ms1 ++ ms2)
collectMetaInts seen (TDelayed _ _ tm) = collectMetaInts seen tm
collectMetaInts seen (TDelay _ _ ty arg)
  = let (seen1, ms1) = collectMetaInts seen ty
        (seen2, ms2) = collectMetaInts seen1 arg
    in (seen2, ms1 ++ ms2)
collectMetaInts seen (TForce _ _ tm) = collectMetaInts seen tm
collectMetaInts seen _ = (seen, [])

-- Replace Meta nodes with Local references for generalised type variables.
-- metaMap: meta Int -> (position in new binder sequence, name)
-- k: number of new implicit binders being prepended
-- depth: number of existing Bind nodes above the current position
-- Replace Metas in TYPE terms (not yet weakened, indices prepended later
-- via believe_me). New binders end up at the high end of the scope.
-- Formula: idx = (depth + k - 1) - pos
replaceMetas : {vars : _} -> IntMap (Nat, Name) -> (k : Nat) -> (depth : Nat) ->
               Term vars -> Term vars
replaceMetas mm k depth (Meta fc n i _)
  = case lookup i mm of
      Just (pos, nm) =>
        -- de Bruijn index: depth existing binders + k new binders - 1 - position
        let idx = (depth + k `minus` 1) `minus` pos in
        Local {name = nm} fc Nothing idx (believe_me (the Nat 0))
      Nothing => Meta fc n i []
replaceMetas mm k depth (Bind fc x b sc)
  = Bind fc x (map (replaceMetas mm k depth) b)
               (replaceMetas mm k (S depth) sc)
replaceMetas mm k depth (App fc f a)
  = App fc (replaceMetas mm k depth f) (replaceMetas mm k depth a)
replaceMetas mm k depth (As fc s as pat)
  = As fc s (replaceMetas mm k depth as) (replaceMetas mm k depth pat)
replaceMetas mm k depth (TDelayed fc r tm)
  = TDelayed fc r (replaceMetas mm k depth tm)
replaceMetas mm k depth (TDelay fc r ty arg)
  = TDelay fc r (replaceMetas mm k depth ty) (replaceMetas mm k depth arg)
replaceMetas mm k depth (TForce fc r tm)
  = TForce fc r (replaceMetas mm k depth tm)
replaceMetas _ _ _ tm = tm

-- Replace Metas in WEAKENED terms (case trees, pats RHS). After weakenNs,
-- new binders are at the low end of the scope (indices 0..k-1).
-- Formula: idx = pos + depth  (depth tracks inner Binds)
replaceMetasW : {vars : _} -> IntMap (Nat, Name) -> (depth : Nat) ->
                Term vars -> Term vars
replaceMetasW mm depth (Meta fc n i _)
  = case lookup i mm of
      Just (pos, nm) =>
        let idx = pos + depth in
        Local {name = nm} fc Nothing idx (believe_me (the Nat 0))
      Nothing => Meta fc n i []
replaceMetasW mm depth (Bind fc x b sc)
  = Bind fc x (map (replaceMetasW mm depth) b)
               (replaceMetasW mm (S depth) sc)
replaceMetasW mm depth (App fc f a)
  = App fc (replaceMetasW mm depth f) (replaceMetasW mm depth a)
replaceMetasW mm depth (As fc s as pat)
  = As fc s (replaceMetasW mm depth as) (replaceMetasW mm depth pat)
replaceMetasW mm depth (TDelayed fc r tm)
  = TDelayed fc r (replaceMetasW mm depth tm)
replaceMetasW mm depth (TDelay fc r ty arg)
  = TDelay fc r (replaceMetasW mm depth ty) (replaceMetasW mm depth arg)
replaceMetasW mm depth (TForce fc r tm)
  = TForce fc r (replaceMetasW mm depth tm)
replaceMetasW _ _ tm = tm

-- Add erased applications to self-recursive calls in a term.
-- After generalisation, the function has k extra erased type arguments,
-- so every occurrence of (Ref Func n) must become
-- (App ... (App (Ref Func n) Erased) ... Erased) with k erased args.
addErasedSelfCalls : {vars : _} -> Int -> Nat -> FC -> Term vars -> Term vars
addErasedSelfCalls nidx k fc (Ref rfc Func nm)
  = case nm of
      Resolved i =>
        if i == nidx
          then apply fc (Ref rfc Func nm)
                        (replicate k (Erased fc Placeholder))
          else Ref rfc Func nm
      _ => Ref rfc Func nm
addErasedSelfCalls nidx k fc (App afc f a)
  = App afc (addErasedSelfCalls nidx k fc f)
            (addErasedSelfCalls nidx k fc a)
addErasedSelfCalls nidx k fc (Bind bfc x b sc)
  = Bind bfc x (map (addErasedSelfCalls nidx k fc) b)
               (addErasedSelfCalls nidx k fc sc)
addErasedSelfCalls nidx k fc (As afc s as pat)
  = As afc s (addErasedSelfCalls nidx k fc as)
             (addErasedSelfCalls nidx k fc pat)
addErasedSelfCalls nidx k fc (TDelayed dfc r tm)
  = TDelayed dfc r (addErasedSelfCalls nidx k fc tm)
addErasedSelfCalls nidx k fc (TDelay dfc r ty arg)
  = TDelay dfc r (addErasedSelfCalls nidx k fc ty)
                 (addErasedSelfCalls nidx k fc arg)
addErasedSelfCalls nidx k fc (TForce ffc r tm)
  = TForce ffc r (addErasedSelfCalls nidx k fc tm)
addErasedSelfCalls _ _ _ tm = tm

-- Apply addErasedSelfCalls to all terms in a CaseTree.
mutual
  fixSelfCallsTree : {vars : _} -> Int -> Nat -> FC ->
                     CaseTree vars -> CaseTree vars
  fixSelfCallsTree nidx k fc (Case idx p scTy alts)
    = Case idx p scTy (map (fixSelfCallsAlt nidx k fc) alts)
  fixSelfCallsTree nidx k fc (STerm i tm)
    = STerm i (addErasedSelfCalls nidx k fc tm)
  fixSelfCallsTree _ _ _ t = t  -- Unmatched, Impossible

  fixSelfCallsAlt : {vars : _} -> Int -> Nat -> FC ->
                    CaseAlt vars -> CaseAlt vars
  fixSelfCallsAlt nidx k fc (ConCase cn tag args ct)
    = ConCase cn tag args (fixSelfCallsTree nidx k fc ct)
  fixSelfCallsAlt nidx k fc (DelayCase ty arg ct)
    = DelayCase ty arg (fixSelfCallsTree nidx k fc ct)
  fixSelfCallsAlt nidx k fc (ConstCase c ct)
    = ConstCase c (fixSelfCallsTree nidx k fc ct)
  fixSelfCallsAlt nidx k fc (DefaultCase ct)
    = DefaultCase (fixSelfCallsTree nidx k fc ct)

-- Generate Local references for constraint arguments at a given depth.
-- Produces [Local (startPos+depth), Local (startPos+1+depth), ...].
mkConstraintLocals : {vars : _} -> (remaining : Nat) -> (startPos : Nat) ->
                     (depth : Nat) -> FC -> List (Term vars)
mkConstraintLocals 0 _ _ _ = []
mkConstraintLocals (S n) pos depth fc
  = Local {name = MN "__cb_con" (cast pos)} fc Nothing (pos + depth)
          (believe_me (the Nat 0))
    :: mkConstraintLocals n (S pos) depth fc

-- Collect resolved function reference indices from a Term
collectFuncRefs : {vars : _} -> Term vars -> List Int
collectFuncRefs (Ref _ _ (Resolved i)) = [i]
collectFuncRefs (App _ f a) = collectFuncRefs f ++ collectFuncRefs a
collectFuncRefs _ = []

mutual
  -- Collect resolved function references from a CaseTree
  collectTreeRefs : {vars : _} -> CaseTree vars -> List Int
  collectTreeRefs (STerm _ tm) = collectFuncRefs tm
  collectTreeRefs (Case _ _ _ alts) = concatMap collectAltRefs alts
  collectTreeRefs _ = []

  collectAltRefs : {vars : _} -> CaseAlt vars -> List Int
  collectAltRefs (ConCase _ _ _ ct) = collectTreeRefs ct
  collectAltRefs (DelayCase _ _ ct) = collectTreeRefs ct
  collectAltRefs (ConstCase _ ct) = collectTreeRefs ct
  collectAltRefs (DefaultCase ct) = collectTreeRefs ct

mutual
  -- Add implicit arguments to case block calls in a Term.
  -- For each Ref to a modified case block, insert nTypes Erased args
  -- and nCons Local args (constraint binders) before the original args.
  addCBCallArgs : {vars : _} -> IntMap () -> Nat -> Nat -> FC ->
                  Nat -> Term vars -> Term vars
  addCBCallArgs cbSet nTypes nCons fc depth (Ref rfc nt (Resolved i))
    = if isJust (lookup i cbSet)
      then let args = replicate nTypes (Erased fc Placeholder)
                      ++ mkConstraintLocals nCons nTypes depth fc
           in apply fc (Ref rfc nt (Resolved i)) args
      else Ref rfc nt (Resolved i)
  addCBCallArgs cbSet nTypes nCons fc depth (App afc f a)
    = App afc (addCBCallArgs cbSet nTypes nCons fc depth f)
              (addCBCallArgs cbSet nTypes nCons fc depth a)
  addCBCallArgs cbSet nTypes nCons fc depth (Bind bfc x b sc)
    = Bind bfc x (map (addCBCallArgs cbSet nTypes nCons fc depth) b)
                 (addCBCallArgs cbSet nTypes nCons fc (S depth) sc)
  addCBCallArgs cbSet nTypes nCons fc depth (As afc s as pat)
    = As afc s (addCBCallArgs cbSet nTypes nCons fc depth as)
               (addCBCallArgs cbSet nTypes nCons fc depth pat)
  addCBCallArgs cbSet nTypes nCons fc depth (TDelayed dfc r tm)
    = TDelayed dfc r (addCBCallArgs cbSet nTypes nCons fc depth tm)
  addCBCallArgs cbSet nTypes nCons fc depth (TDelay dfc r ty arg)
    = TDelay dfc r (addCBCallArgs cbSet nTypes nCons fc depth ty)
                   (addCBCallArgs cbSet nTypes nCons fc depth arg)
  addCBCallArgs cbSet nTypes nCons fc depth (TForce ffc r tm)
    = TForce ffc r (addCBCallArgs cbSet nTypes nCons fc depth tm)
  addCBCallArgs _ _ _ _ _ tm = tm

  -- Apply addCBCallArgs to a CaseTree
  addCBCallArgsTree : {vars : _} -> IntMap () -> Nat -> Nat -> FC ->
                      Nat -> CaseTree vars -> CaseTree vars
  addCBCallArgsTree cbSet nTypes nCons fc depth (Case idx p scTy alts)
    = Case idx p scTy (map (addCBCallArgsAlt cbSet nTypes nCons fc depth) alts)
  addCBCallArgsTree cbSet nTypes nCons fc depth (STerm i tm)
    = STerm i (addCBCallArgs cbSet nTypes nCons fc depth tm)
  addCBCallArgsTree _ _ _ _ _ t = t

  addCBCallArgsAlt : {vars : _} -> IntMap () -> Nat -> Nat -> FC ->
                     Nat -> CaseAlt vars -> CaseAlt vars
  addCBCallArgsAlt cbSet nTypes nCons fc depth (ConCase cn tag args ct)
    = ConCase cn tag args
        (addCBCallArgsTree cbSet nTypes nCons fc (depth + length args) ct)
  addCBCallArgsAlt cbSet nTypes nCons fc depth (DelayCase ty arg ct)
    = DelayCase ty arg
        (addCBCallArgsTree cbSet nTypes nCons fc (depth + 2) ct)
  addCBCallArgsAlt cbSet nTypes nCons fc depth (ConstCase c ct)
    = ConstCase c (addCBCallArgsTree cbSet nTypes nCons fc depth ct)
  addCBCallArgsAlt cbSet nTypes nCons fc depth (DefaultCase ct)
    = DefaultCase (addCBCallArgsTree cbSet nTypes nCons fc depth ct)

-- Transitively collect all case block function indices reachable from
-- a set of starting function references.
collectCaseBlocks : {auto c : Ref Ctxt Defs} ->
                    List Int -> IntMap () -> Core (IntMap ())
collectCaseBlocks [] visited = pure visited
collectCaseBlocks (idx :: rest) visited
  = if isJust (lookup idx visited)
    then collectCaseBlocks rest visited
    else do defs <- get Ctxt
            Just gdef <- lookupCtxtExact (Resolved idx) (gamma defs)
              | Nothing => collectCaseBlocks rest visited
            fn <- toFullNames (fullname gdef)
            if isCB fn
              then do let PMDef _ _ ct _ _ = definition gdef
                        | _ => collectCaseBlocks rest (insert idx () visited)
                      let refs = collectTreeRefs ct
                      collectCaseBlocks (refs ++ rest) (insert idx () visited)
              else collectCaseBlocks rest visited
  where
    isCB : Name -> Bool
    isCB (CaseBlock {}) = True
    isCB (NS _ n) = isCB n
    isCB _ = False

-- Prepend {0 name : Type} -> Pi binders to a ClosedTerm.
-- The body has metas replaced with Locals referencing these binders.
-- Safety of believe_me: the recursive call returns ClosedTerm (Term []),
-- but wrapping in Bind requires Term [nm]. The de Bruijn indices in body
-- already account for all prepended binders (computed by replaceMetas),
-- so the cast is representationally correct — only the type-level scope
-- list is wrong.
prependImplPis : FC -> List Name -> ClosedTerm -> ClosedTerm
prependImplPis fc [] body = body
prependImplPis fc (nm :: rest) body
  = Bind fc nm (Pi fc erased Implicit (TType fc (MN "top" 0)))
    (believe_me $ prependImplPis fc rest body)

-- Prepend {auto name : constraintTy} -> Pi binders to a ClosedTerm.
-- Same believe_me justification as prependImplPis.
prependAutoImplPis : FC -> List (Name, ClosedTerm) -> ClosedTerm -> ClosedTerm
prependAutoImplPis fc [] body = body
prependAutoImplPis fc ((nm, cty) :: rest) body
  = Bind fc nm (Pi fc top AutoImplicit cty)
    (believe_me $ prependAutoImplPis fc rest body)

-- Walk a CaseTree replacing Meta nodes using replaceMetasW (weakened terms).
-- depth tracks inner binders (ConCase/DelayCase pattern vars) that shift
-- the new binder indices upward.
mutual
  replaceMetasInTree : {vars : _} -> IntMap (Nat, Name) -> Nat ->
                       CaseTree vars -> CaseTree vars
  replaceMetasInTree mm depth (Case idx p scTy alts)
    = Case idx p scTy (map (replaceMetasInAlt mm depth) alts)
  replaceMetasInTree mm depth (STerm i tm)
    = STerm i (replaceMetasW mm depth tm)
  replaceMetasInTree _ _ t = t

  replaceMetasInAlt : {vars : _} -> IntMap (Nat, Name) -> Nat ->
                      CaseAlt vars -> CaseAlt vars
  replaceMetasInAlt mm depth (ConCase cn tag args ct)
    = ConCase cn tag args (replaceMetasInTree mm (depth + length args) ct)
  replaceMetasInAlt mm depth (DelayCase ty arg ct)
    = DelayCase ty arg (replaceMetasInTree mm (depth + 2) ct)
  replaceMetasInAlt mm depth (ConstCase c ct)
    = ConstCase c (replaceMetasInTree mm depth ct)
  replaceMetasInAlt mm depth (DefaultCase ct)
    = DefaultCase (replaceMetasInTree mm depth ct)

-- Extend an Env with implicit Pi binders at the front.
-- The new binders have type Type (which doesn't reference any locals),
-- so existing binder types in the env don't need weakening.
extendEnvWithImpls : {vars : _} -> FC -> (names : List Name) ->
                     Env Term vars -> Env Term (names ++ vars)
extendEnvWithImpls fc [] env = env
extendEnvWithImpls fc (n :: ns) env
  = Pi fc erased Implicit (TType fc (MN "top" 0))
    :: extendEnvWithImpls fc ns env

-- Strip all Pi/Let binders from a ClosedTerm to get the innermost body.
-- Used to extract the bare constraint type from abstractEnvType'd BySearch types.
-- Safety of believe_me: the body doesn't reference the stripped binders
-- (constraint types like Num ?a only reference global metas, not locals).
stripPis : ClosedTerm -> ClosedTerm
stripPis (Bind _ _ (Pi _ _ _ _) sc) = stripPis (believe_me sc)
stripPis (Bind _ _ (Let _ _ _ _) sc) = stripPis (believe_me sc)
stripPis tm = tm

-- Check if a ClosedTerm contains any Meta with an index in the given set
containsAnyMeta : IntMap () -> ClosedTerm -> Bool
containsAnyMeta metas (Meta _ _ i _)
  = isJust (lookup i metas)
containsAnyMeta metas (App _ f a)
  = containsAnyMeta metas f || containsAnyMeta metas a
containsAnyMeta metas (Bind _ _ b sc)
  = containsAnyMeta metas (binderType b) || containsAnyMeta metas (believe_me sc)
containsAnyMeta metas (TDelayed _ _ tm) = containsAnyMeta metas tm
containsAnyMeta metas (TDelay _ _ ty arg)
  = containsAnyMeta metas ty || containsAnyMeta metas arg
containsAnyMeta metas (TForce _ _ tm) = containsAnyMeta metas tm
containsAnyMeta _ _ = False

-- Update pat RHS by adding implicit args to case block calls.
updatePatCBCalls : IntMap () -> Nat -> Nat -> FC ->
                   (vs ** (Env Term vs, Term vs, Term vs)) ->
                   (vs ** (Env Term vs, Term vs, Term vs))
updatePatCBCalls cbSet nTypes nCons fc (vs ** (env, lhs, rhs))
  = (vs ** (env, lhs, addCBCallArgs cbSet nTypes nCons fc 0 rhs))

-- Like addImplsToPat but for case blocks: no self-call fixing needed.
addImplsToPatCB : FC -> (implNames : List Name) -> (totalK : Nat) ->
                  IntMap (Nat, Name) ->
                  SizeOf implNames ->
                  (vs ** (Env Term vs, Term vs, Term vs)) ->
                  (vs' ** (Env Term vs', Term vs', Term vs'))
addImplsToPatCB fc implNames totalK combinedMap sz (vs ** (env, lhs, rhs))
  = let wenv = extendEnvWithImpls fc implNames env
        wlhs = weakenNs sz lhs
        wrhs = replaceMetasW combinedMap 0 (weakenNs sz rhs)
        (fn, args) = getFnArgs wlhs
        erasedArgs = replicate totalK (Erased fc Placeholder)
        newLhs = apply fc fn (erasedArgs ++ args)
    in (implNames ++ vs ** (wenv, newLhs, wrhs))

-- Generalise a synthesised type by turning unsolved metas into
-- universally quantified implicit type parameters and unsolved
-- BySearch constraints into auto-implicit Pi binders.
-- e.g. add x y = x + y  =>  {0 a : Type} -> Num a => a -> a -> a
generaliseType : {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 FC -> Name -> Int -> Core ()
generaliseType fc n nidx
  = do defs <- get Ctxt
       Just gdef <- lookupCtxtExact (Resolved nidx) (gamma defs)
         | Nothing => pure ()
       -- Only generalise synthesised top-level user definitions
       -- (not case blocks, nested/where functions, etc.)
       fn <- toFullNames n
       when ((SynthesisedType `elem` flags gdef) && isTopLevelUser fn) $ do
         let ty = type gdef
         -- Normalise to resolve any solved metas
         nty <- normalise defs [] ty
         -- Collect unsolved meta indices in order of appearance
         let (_, metaInts) = collectMetaInts empty nty
         unsolved <- filterM
           (\i => do defs' <- get Ctxt
                     Just mgdef <- lookupCtxtExact (Resolved i) (gamma defs')
                       | Nothing => pure False
                     case definition mgdef of
                       Hole _ _ => pure True
                       _ => pure False) metaInts
         -- Find unsolved BySearch constraints referencing the type metas
         let typeMetaSet = fromList (map (\i => (i, ())) unsolved)
         allConstraintMetas <- findConstraintMetas typeMetaSet
         let nTypes = length unsolved
         case unsolved of
           [] => pure ()  -- All metas solved; nothing to generalise
           ms => do
             let PMDef pi cargs treeCT treeRT pats = definition gdef
               | _ => pure ()
             -- Deduplicate constraints with the same type (e.g. two Ord ?a
             -- from separate uses of < and >)
             let (constraintMetas', dupMap) =
                   deduplicateConstraints nTypes allConstraintMetas
             let nConstraints = length constraintMetas'
             let totalK = nTypes + nConstraints
             -- Assign variable names: a, b, c, ... for type params
             let typeNames = assignNames 0 ms
             -- Assign constraint names: __con0, __con1, ... (internal)
             let constraintNames = map fst constraintMetas'
             let allNames = typeNames ++ constraintNames
             -- Build IntMap: meta Int -> (position, name)
             -- Type metas at positions 0..nTypes-1
             let metaMap = buildMap 0 ms typeNames
             -- Constraint metas at positions nTypes..totalK-1
             -- Also merge in duplicate mappings (pointing to same position)
             let baseMap = addConstraintsToMap nTypes constraintMetas' metaMap
             let combinedMap = foldl (\m, (k, v) => insert k v m)
                                     baseMap (IntMap.toList dupMap)
             -- Replace type metas in the function body type
             let body = replaceMetas metaMap totalK 0 nty
             -- Build constraint binder types: strip env Pis, replace type metas
             let constraintBinderTypes =
                   buildConstraintBinderTypes fc nTypes constraintMetas' metaMap
             -- Build generalised type:
             -- {0 a : Type} -> ... -> {auto _ : Constraint a} -> ... -> body
             let withConstraints = prependAutoImplPis fc constraintBinderTypes body
             let genTy = prependImplPis fc typeNames withConstraints
             -- Update the PMDef
             let sz = mkSizeOf allNames
             -- Weaken case trees, replace constraint metas, fix self-calls
             let wCT0 = weakenNs sz treeCT
             let wRT0 = weakenNs sz treeRT
             -- Replace metas in case trees with Local refs to new binders
             let wCT1 = replaceMetasInTree combinedMap 0 wCT0
             let wRT1 = replaceMetasInTree combinedMap 0 wRT0
             -- Fix self-recursive calls to include erased type arguments
             let wCT = fixSelfCallsTree nidx nTypes fc wCT1
             let wRT = fixSelfCallsTree nidx nTypes fc wRT1
             -- Update pats
             let newPats = map (addImplsToPat fc nidx allNames totalK nTypes
                                              combinedMap sz) pats
             -- Store updated definition
             ignore $ addDef (Resolved nidx) $
               { type := genTy
               , definition := PMDef pi (allNames ++ cargs) wCT wRT newPats
               } gdef
             -- Remove generalised metas from hole/guess lists
             traverse_ removeHole ms
             traverse_ (\(_, ci, _) => removeGuess ci) constraintMetas'
             -- Remove duplicate constraint metas
             traverse_ (\(ci, _) => do
               defs'' <- get Ctxt
               Just gdef'' <- lookupCtxtExact (Resolved ci) (gamma defs'')
                 | Nothing => pure ()
               let erasedRHS : ClosedTerm = Erased fc Placeholder
               let solvedDef = MkPMDefInfo (SolvedHole 0) True False
               ignore $ addDef (Resolved ci) $
                 { definition := PMDef solvedDef Scope.empty
                     (STerm 0 erasedRHS) (STerm 0 erasedRHS) [] } gdef''
               removeGuess ci) (IntMap.toList dupMap)
             -- Recompute eraseArgs for the new type
             (es, dtes) <- findErased genTy
             defs' <- get Ctxt
             Just gdef' <- lookupCtxtExact (Resolved nidx) (gamma defs')
               | Nothing => pure ()
             ignore $ addDef (Resolved nidx) $
               { eraseArgs := es, safeErase := dtes } gdef'
             -- Propagate generalisation to case blocks: add the same
             -- implicit type/constraint binders so that constraint metas
             -- inside case block bodies get replaced with Local refs.
             let parentRefs = collectTreeRefs wCT
             cbSet <- collectCaseBlocks parentRefs empty
             when (not (null (IntMap.toList cbSet))) $ do
               traverse_ (\(cbidx, _) => do
                 defs3 <- get Ctxt
                 Just cbgdef <- lookupCtxtExact (Resolved cbidx) (gamma defs3)
                   | Nothing => pure ()
                 let PMDef cbpi cbcargs cbCT cbRT cbpats = definition cbgdef
                   | _ => pure ()
                 ncbty <- normalise defs3 [] (type cbgdef)
                 let cbBody = replaceMetas metaMap totalK 0 ncbty
                 let cbWC = prependAutoImplPis fc constraintBinderTypes cbBody
                 let cbGenTy = prependImplPis fc typeNames cbWC
                 let wcbCT = replaceMetasInTree combinedMap 0 (weakenNs sz cbCT)
                 let wcbRT = replaceMetasInTree combinedMap 0 (weakenNs sz cbRT)
                 let wcbPats = map (addImplsToPatCB fc allNames totalK
                                                     combinedMap sz) cbpats
                 ignore $ addDef (Resolved cbidx) $
                   { type := cbGenTy
                   , definition := PMDef cbpi (allNames ++ cbcargs)
                                         wcbCT wcbRT wcbPats
                   } cbgdef
                 (cbes, cbdtes) <- findErased cbGenTy
                 defs4 <- get Ctxt
                 Just cbgdef4 <- lookupCtxtExact (Resolved cbidx) (gamma defs4)
                   | Nothing => pure ()
                 ignore $ addDef (Resolved cbidx) $
                   { eraseArgs := cbes, safeErase := cbdtes } cbgdef4
                 ) (IntMap.toList cbSet)
               -- Update call sites: add implicit args to case block calls
               -- in the parent function and in all modified case blocks.
               let allToUpdate = nidx :: map fst (IntMap.toList cbSet)
               traverse_ (\uidx => do
                 defs5 <- get Ctxt
                 Just ugdef <- lookupCtxtExact (Resolved uidx) (gamma defs5)
                   | Nothing => pure ()
                 let PMDef upi ucargs uCT uRT upats = definition ugdef
                   | _ => pure ()
                 let updCT = addCBCallArgsTree cbSet nTypes nConstraints fc 0 uCT
                 let updRT = addCBCallArgsTree cbSet nTypes nConstraints fc 0 uRT
                 let updPats = map (updatePatCBCalls cbSet nTypes nConstraints fc)
                                   upats
                 ignore $ addDef (Resolved uidx) $
                   { definition := PMDef upi ucargs updCT updRT updPats } ugdef
                 ) allToUpdate
             log "declare.def" 5 $
               "Generalised " ++ show n ++ " with "
               ++ show nTypes ++ " type parameter(s) and "
               ++ show nConstraints ++ " constraint(s)"
  where
    isTopLevelUser : Name -> Bool
    isTopLevelUser (NS _ n) = isTopLevelUser n
    isTopLevelUser (UN _) = True
    isTopLevelUser _ = False

    assignNames : Nat -> List Int -> List Name
    assignNames _ [] = []
    assignNames i (_ :: rest)
      = UN (Basic (singleton (chr (cast (ord 'a' + cast i)))))
        :: assignNames (S i) rest

    buildMap : Nat -> List Int -> List Name -> IntMap (Nat, Name)
    buildMap _ [] _ = empty
    buildMap _ _ [] = empty
    buildMap pos (mi :: ms) (nm :: nms)
      = insert mi (pos, nm) (buildMap (S pos) ms nms)

    -- Find BySearch constraints in UST guesses whose types reference
    -- any of the given type metas. Returns (name, index, stripped type).
    findConstraintMetas : IntMap () ->
                          Core (List (Name, Int, ClosedTerm))
    findConstraintMetas typeMetaSet
      = do ust <- get UST
           defs <- get Ctxt
           let gs = toList (guesses ust)
           results <- traverse (checkGuess defs) gs
           pure (mapMaybe id results)
      where
        checkGuess : Defs -> (Int, (FC, Name)) ->
                     Core (Maybe (Name, Int, ClosedTerm))
        checkGuess defs (gidx, (gfc, gname))
          = do Just gdef <- lookupCtxtExact (Resolved gidx) (gamma defs)
                 | Nothing => pure Nothing
               case definition gdef of
                 BySearch {} =>
                   do ngty <- normalise defs [] (type gdef)
                      let stripped = stripPis ngty
                      if containsAnyMeta typeMetaSet stripped
                         then pure (Just (MN "__con" gidx, gidx, stripped))
                         else pure Nothing
                 _ => pure Nothing

    -- Deduplicate constraint metas by type. When multiple BySearch
    -- constraints have the same type (e.g. two `Ord ?a` from `<` and `>`),
    -- keep only one binder and map all duplicates to the same position.
    -- Returns (unique constraints, mapping from duplicate Int to (pos, name))
    deduplicateConstraints : Nat -> List (Name, Int, ClosedTerm) ->
                             (List (Name, Int, ClosedTerm), IntMap (Nat, Name))
    deduplicateConstraints startPos cs = go startPos cs [] empty
      where
        -- Check if a type is already in the unique list
        findDup : ClosedTerm -> Nat -> List (Name, Int, ClosedTerm) ->
                  Maybe (Nat, Name)
        findDup _ _ [] = Nothing
        findDup ty pos ((nm, _, ty') :: rest)
          = if eqTerm ty ty' then Just (pos, nm)
            else findDup ty (S pos) rest
        go : Nat -> List (Name, Int, ClosedTerm) ->
             List (Name, Int, ClosedTerm) -> IntMap (Nat, Name) ->
             (List (Name, Int, ClosedTerm), IntMap (Nat, Name))
        go _ [] acc dupMap = (reverse acc, dupMap)
        go pos ((nm, ci, ty) :: rest) acc dupMap
          = case findDup ty startPos acc of
              Just (dupPos, dupNm) =>
                -- Duplicate: map this meta to the existing position
                go pos rest acc (insert ci (dupPos, dupNm) dupMap)
              Nothing =>
                -- Unique: add to accum, advance position
                go (S pos) rest ((nm, ci, ty) :: acc) dupMap

    -- Add constraint metas to the metaMap at positions after type metas
    addConstraintsToMap : Nat -> List (Name, Int, ClosedTerm) ->
                          IntMap (Nat, Name) -> IntMap (Nat, Name)
    addConstraintsToMap _ [] mm = mm
    addConstraintsToMap pos ((nm, ci, _) :: rest) mm
      = addConstraintsToMap (S pos) rest (insert ci (pos, nm) mm)

    -- Build constraint binder types by replacing type metas with Locals.
    -- For constraint j (0-indexed), k = nTypes + j because there are
    -- nTypes type binders and j constraint binders above it.
    buildConstraintBinderTypes : FC -> Nat ->
                                 List (Name, Int, ClosedTerm) ->
                                 IntMap (Nat, Name) ->
                                 List (Name, ClosedTerm)
    buildConstraintBinderTypes fc nTypes cs typeMetaMap
      = go 0 cs
      where
        go : Nat -> List (Name, Int, ClosedTerm) -> List (Name, ClosedTerm)
        go _ [] = []
        go j ((nm, _, stripped) :: rest)
          = let replaced = replaceMetas typeMetaMap (nTypes + j) 0 stripped
            in (nm, replaced) :: go (S j) rest

    addImplsToPat : FC -> Int -> (implNames : List Name) -> (totalK : Nat) ->
                    (nTypes : Nat) -> IntMap (Nat, Name) ->
                    SizeOf implNames ->
                    (vs ** (Env Term vs, Term vs, Term vs)) ->
                    (vs' ** (Env Term vs', Term vs', Term vs'))
    addImplsToPat fc fidx implNames totalK nTypes combinedMap sz
                  (vs ** (env, lhs, rhs))
      = let wenv = extendEnvWithImpls fc implNames env
            wlhs = weakenNs sz lhs
            wrhs0 = weakenNs sz rhs
            -- Replace metas with Locals in the weakened RHS
            wrhs1 = replaceMetasW combinedMap 0 wrhs0
            -- Fix self-recursive calls (type params only)
            wrhs = addErasedSelfCalls fidx nTypes fc wrhs1
            -- Prepend erased/placeholder applications for the implicit args
            (fn, args) = getFnArgs wlhs
            erasedArgs = replicate totalK (Erased fc Placeholder)
            newLhs = apply fc fn (erasedArgs ++ args)
        in (implNames ++ vs ** (wenv, newLhs, wrhs))

-- Tighten multiplicities of explicit arguments in a synthesised type
-- by trial: temporarily set each argument to linear (Rig1), run the
-- linearity checker, and keep Rig1 only if the check passes.
-- This correctly handles cases where a variable appears once but in
-- an unrestricted position (e.g. list constructor).
tightenMultiplicities : {auto c : Ref Ctxt Defs} ->
                        {auto u : Ref UST UState} ->
                        FC -> Name -> Int -> Core ()
tightenMultiplicities fc n nidx
  = do defs <- get Ctxt
       Just gdef <- lookupCtxtExact (Resolved nidx) (gamma defs)
         | Nothing => pure ()
       when (SynthesisedType `elem` flags gdef) $ do
         let PMDef pi cargs treeCT treeRT pats = definition gdef
           | _ => pure ()
         -- Count explicit Pi binders in the type
         let nExplicit = countExplicitPis (type gdef)
         when (nExplicit > 0) $ do
           -- For each explicit arg, test if linear is valid
           mults <- testArgs 0 nExplicit pats (type gdef)
           when (any isLinear mults) $ do
             let newTy = setExplicitMults mults (type gdef)
             ignore $ addDef (Resolved nidx) $ { type := newTy } gdef
             (es, dtes) <- findErased newTy
             defs' <- get Ctxt
             Just gdef' <- lookupCtxtExact (Resolved nidx) (gamma defs')
               | Nothing => pure ()
             ignore $ addDef (Resolved nidx) $
               { eraseArgs := es, safeErase := dtes } gdef'
             log "declare.def" 5 $
               "Tightened multiplicities for " ++ show n
  where
    countExplicitPis : Term vars -> Nat
    countExplicitPis (Bind _ _ (Pi _ _ Explicit _) sc) = S (countExplicitPis sc)
    countExplicitPis (Bind _ _ (Pi _ _ _ _) sc) = countExplicitPis sc
    countExplicitPis _ = 0

    -- Set the multiplicity of the Nth binder (counting from the head/outermost)
    setEnvMult : {vars : _} -> Nat -> RigCount ->
                 Env Term vars -> Env Term vars
    setEnvMult Z m (b :: env) = setMultiplicity b m :: env
    setEnvMult (S k) m (b :: env) = b :: setEnvMult k m env
    setEnvMult _ _ env = env

    -- Find the env position of the Nth explicit argument.
    -- Skips implicit/auto Pi binders (from generalization) that appear
    -- as Let/Pi binders in the clause env.
    findExplicitPos : {vars : _} -> Nat -> Env Term vars -> Maybe Nat
    findExplicitPos target env = go 0 target env
      where
        isExplicitPat : Binder t -> Bool
        isExplicitPat (PVar _ _ Explicit _) = True
        isExplicitPat (PVTy _ _ _) = True
        isExplicitPat _ = False

        go : {vs : _} -> Nat -> Nat -> Env Term vs -> Maybe Nat
        go pos Z (b :: _) = if isExplicitPat b then Just pos else Nothing
        go pos (S k) (b :: rest)
            = if isExplicitPat b
                 then go (S pos) k rest
                 else go (S pos) (S k) rest
        go _ _ [] = Nothing

    -- Try linearCheck on all clause RHSes with a modified env.
    -- Returns True if ALL clauses pass with the modified multiplicity.
    -- We normalise the RHS first to substitute solved metas, because
    -- linearCheck's updateHoleUsage forgives zero-usage linear vars
    -- when ANY unsolved hole exists in the term.
    trialLinear : Nat ->
                  List (vs ** (Env Term vs, Term vs, Term vs)) ->
                  Core Bool
    trialLinear envPos [] = pure True
    trialLinear envPos ((vs ** (env, lhs, rhs)) :: rest)
        = do let env' = setEnvMult envPos linear env
             defs <- get Ctxt
             -- Normalise to substitute solved metas; linearCheck's
             -- updateHoleUsage forgives zero-usage linear vars when
             -- any unsolved hole exists in the term.
             rhs' <- catch
               (normalise defs env' rhs)
               (\_ => pure rhs)
             ok <- catch
               (do ignore $ linearCheck fc linear False env' rhs'
                   pure True)
               (\_ => pure False)
             if ok then trialLinear envPos rest
                   else pure False

    -- Test each explicit argument: can it be linear?
    testArgs : Nat -> Nat ->
               List (vs ** (Env Term vs, Term vs, Term vs)) ->
               Term vs' -> Core (List RigCount)
    testArgs i nTotal pats ty
        = if i >= nTotal then pure []
          else do -- Find env position for this explicit arg in the first clause
                  canBeLinear <- case pats of
                    ((vs ** (env, _, _)) :: _) =>
                      case findExplicitPos i env of
                        Just pos => trialLinear pos pats
                        Nothing => pure False
                    _ => pure False
                  let m = if canBeLinear then linear else top
                  rest <- testArgs (S i) nTotal pats ty
                  pure (m :: rest)

    -- Update multiplicities of explicit Pi binders in a type.
    setExplicitMults : List RigCount -> Term vars -> Term vars
    setExplicitMults (m :: ms) (Bind bfc x (Pi pfc _ Explicit ty) sc)
        = Bind bfc x (Pi pfc m Explicit ty) (setExplicitMults ms sc)
    setExplicitMults ms (Bind bfc x b@(Pi _ _ _ _) sc)
        = Bind bfc x b (setExplicitMults ms sc)
    setExplicitMults _ ty = ty

-- Check if a RawImp term contains any literal values (IPrimVal).
-- Used to detect numeric/string literal patterns in clause LHS.
hasLiteralPat : RawImp -> Bool
hasLiteralPat (IPrimVal _ _) = True
hasLiteralPat (IApp _ f a) = hasLiteralPat f || hasLiteralPat a
hasLiteralPat (IAutoApp _ f a) = hasLiteralPat f || hasLiteralPat a
hasLiteralPat (INamedApp _ f _ a) = hasLiteralPat f || hasLiteralPat a
hasLiteralPat _ = False

-- Check if any clause has literal patterns in its LHS.
-- Functions with literal patterns (e.g. `fib 0 = 0`) need concrete types
-- for pattern matching, so their type metas should not be protected from
-- defaulting during synthesised-type elaboration.
clausesHaveLiteralPats : List ImpClause -> Bool
clausesHaveLiteralPats [] = False
clausesHaveLiteralPats (PatClause _ lhs _ :: cs)
    = hasLiteralPat lhs || clausesHaveLiteralPats cs
clausesHaveLiteralPats (WithClause _ lhs _ _ _ _ _ :: cs)
    = hasLiteralPat lhs || clausesHaveLiteralPats cs
clausesHaveLiteralPats (ImpossibleClause _ lhs :: cs)
    = hasLiteralPat lhs || clausesHaveLiteralPats cs

export
processDef : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto o : Ref ROpts REPLOpts} ->
             List ElabOpt -> NestedNames vars -> Env Term vars -> FC ->
             Name -> List ImpClause -> Core ()
processDef opts nest env fc n_in cs_in
  = do n <- inCurrentNS n_in
       withDefStacked n $ do
         defs <- get Ctxt
         Just gdef <- lookupOrAddAlias opts nest env fc n cs_in
           | Nothing => noDeclaration fc n
         let None = definition gdef
              | _ => throw (AlreadyDefined fc n)
         let ty = type gdef
         -- a module's interface hash (what determines when the module has changed)
         -- should include the definition (RHS) of anything that is public (available
         -- at compile time for elaboration) _or_ inlined (dropped into destination definitions
         -- during compilation).
         let hashit = (collapseDefault $ visibility gdef) == Public || (Inline `elem` gdef.flags)
         let mult = if isErased (multiplicity gdef)
                       then erased
                       else linear
         nidx <- resolveName n

         -- Dynamically rebind default totality requirement to this function's totality requirement
         -- and use this requirement when processing `with` blocks
         log "declare.def" 5 $ "Traversing clauses of " ++ show n ++ " with mult " ++ show mult
         let treq = fromMaybe !getDefaultTotalityOption (findSetTotal (flags gdef))
         -- When elaborating synthesised-type definitions, suppress default
         -- hint resolution so typeclass constraints remain unsolved for
         -- later generalisation (e.g. Num a => a -> a -> a)
         let isSynth = SynthesisedType `elem` flags gdef
         when isSynth $ update UST { synthElabMode := True }
         cs <- withTotality treq $
               traverse (checkClause mult (collapseDefault $ visibility gdef) treq
                                     hashit nidx opts nest env) cs_in
         when isSynth $ do
           -- Phase 2: retry constraints not related to type generalisation.
           -- Compute the function type's unsolved metas, then retry with
           -- synthTypeMetas set so retryGuess only suppresses constraints
           -- whose types reference these specific metas.
           defs' <- get Ctxt
           Just gdef' <- lookupCtxtExact (Resolved nidx) (gamma defs')
             | Nothing => update UST { synthElabMode := False }
           nty' <- normalise defs' [] (type gdef')
           let (_, metaInts) = collectMetaInts empty nty'
           unsolvedMetas <- filterM
             (\i => do defs'' <- get Ctxt
                       Just mgdef <- lookupCtxtExact (Resolved i) (gamma defs'')
                         | Nothing => pure False
                       case definition mgdef of
                         Hole _ _ => pure True
                         _ => pure False) metaInts
           -- Phase 2: turn off synthElabMode and retry constraint solving.
           -- If clauses have literal patterns (e.g. `fib 0 = 0`), don't
           -- protect type metas — they must resolve to concrete types for
           -- pattern matching. Otherwise, protect type metas with noSolve
           -- so they remain unsolved for generalisation.
           let hasLitPats = clausesHaveLiteralPats cs_in
           let protectedMetas : List Int
                 = if hasLitPats then [] else unsolvedMetas
           update UST { synthElabMode := False }
           traverse_ addNoSolve protectedMetas
           solveConstraints inTerm Normal
           solveConstraints inTerm Defaults
           solveConstraints inTerm LastChance
           traverse_ removeNoSolve protectedMetas

         let pats = map toPats (rights cs)

         (cargs ** (tree_ct, unreachable)) <-
             logTime 3 ("Building compile time case tree for " ++ show n) $
                getPMDef fc (CompileTime mult) n ty (rights cs)

         traverse_ warnUnreachable unreachable

         logC "declare.def" 2 $
                 do t <- toFullNames tree_ct
                    pure ("Case tree for " ++ show n ++ ": " ++ show t)

         -- check whether the name was declared in a different source file
         defs <- get Ctxt
         let pi = case lookup n (userHoles defs) of
                        Nothing => defaultPI
                        Just e => { externalDecl := e } defaultPI
         -- Add compile time tree as a placeholder for the runtime tree,
         -- but we'll rebuild that in a later pass once all the case
         -- blocks etc are resolved
         ignore $ addDef (Resolved nidx)
                  ({ definition := PMDef pi cargs tree_ct tree_ct pats
                   } gdef)

         when (collapseDefault (visibility gdef) == Public) $
             do let rmetas = getMetas tree_ct
                log "declare.def" 10 $ "Saving from " ++ show n ++ ": " ++ show (keys rmetas)
                traverse_ addToSave (keys rmetas)
         when (isUserName n && collapseDefault (visibility gdef) /= Private) $
             do let tymetas = getMetas (type gdef)
                traverse_ addToSave (keys tymetas)
         addToSave n

         -- Flag this name as one which needs compiling
         update Ctxt { toCompileCase $= (n ::) }

         atotal <- toResolvedNames (NS builtinNS (UN $ Basic "assert_total"))
         logTime 3 ("Building size change graphs " ++ show n) $
           when (not (InCase `elem` opts)) $
             do calcRefs False atotal (Resolved nidx)
                sc <- calculateSizeChange fc n
                setSizeChange fc n sc
                checkIfGuarded fc n

         md <- get MD -- don't need the metadata collected on the coverage check

         cov <- logTime 3 ("Checking Coverage " ++ show n) $ checkCoverage nidx ty mult cs
         setCovering fc n cov
         put MD md

         -- If we're not in a case tree, compile all the outstanding case
         -- trees.
         when (not (elem InCase opts)) $
              compileRunTime fc atotal

         -- Generalise synthesised types: turn unsolved metas into
         -- universally quantified implicit type parameters.
         -- Must run AFTER compileRunTime so that mkRunTime's scopeEq
         -- check sees the original (ungeneralised) PMDef args.
         generaliseType fc n nidx
         tightenMultiplicities fc n nidx
  where
    -- Move `withTotality` to Core.Context if we need it elsewhere
    ||| Temporarily rebind the default totality requirement (%default total/partial/covering).
    withTotality : TotalReq -> Lazy (Core a) -> Core a
    withTotality tot c = do
         defaultTotality <- getDefaultTotalityOption
         setDefaultTotalityOption tot
         x <- catch c (\error => do setDefaultTotalityOption defaultTotality
                                    throw error)
         setDefaultTotalityOption defaultTotality
         pure x


    simplePat : forall vars . Term vars -> Bool
    simplePat (Local {}) = True
    simplePat (Erased {}) = True
    simplePat (As _ _ _ p) = simplePat p
    simplePat _ = False

    -- Is the clause returned from 'checkClause' a catch all clause, i.e.
    -- one where all the arguments are variables? If so, no need to do the
    -- (potentially expensive) coverage check
    catchAll : Clause -> Bool
    catchAll (MkClause env lhs _)
       = all simplePat (getArgs lhs)

    -- Return 'Nothing' if the clause is impossible, otherwise return the
    -- checked clause (with implicits filled in, so that we can see if they
    -- match any of the given clauses)
    checkImpossible : Int -> RigCount -> ClosedTerm ->
                      Core (Maybe ClosedTerm)
    checkImpossible n mult tm
        = do itm <- unelabNoPatvars Env.empty tm
             let itm = map rawName itm
             handleUnify
               (do ctxt <- get Ctxt
                   log "declare.def.impossible" 3 $ "Checking for impossibility: " ++ show itm
                   autoimp <- isUnboundImplicits
                   setUnboundImplicits True
                   (_, lhstm) <- bindNames False itm
                   setUnboundImplicits autoimp
                   (lhstm, _) <- elabTerm n (InLHS mult) [] (MkNested []) Env.empty
                                    (IBindHere fc COVERAGE lhstm) Nothing
                   defs <- get Ctxt
                   lhs <- normaliseHoles defs Env.empty lhstm
                   if !(hasEmptyPat defs Env.empty lhs)
                      then do log "declare.def.impossible" 5 "Some empty pat"
                              put Ctxt ctxt
                              pure Nothing
                      else do log "declare.def.impossible" 5 "No empty pat"
                              empty <- clearDefs ctxt
                              rtm <- closeEnv empty !(nf empty Env.empty lhs)
                              put Ctxt ctxt
                              pure (Just rtm))
               (\err => do defs <- get Ctxt
                           if !(impossibleErrOK defs err)
                              then do
                                log "declare.def.impossible" 5 "impossible because \{show err}"
                                pure Nothing
                              else pure (Just tm))
      where
        closeEnv : Defs -> ClosedNF -> Core ClosedTerm
        closeEnv defs (NBind _ x (PVar {}) sc)
            = closeEnv defs !(sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x)))
        closeEnv defs nf = quote defs Env.empty nf

    getClause : Either RawImp Clause -> Core (Maybe Clause)
    getClause (Left rawlhs)
        = catch (do lhsp <- getImpossibleTerm env nest rawlhs
                    log "declare.def.impossible" 3 $ "Generated impossible LHS: " ++ show lhsp
                    pure $ Just $ MkClause Env.empty lhsp (Erased (getFC rawlhs) Impossible))
                (\e => do log "declare.def" 5 $ "Error in getClause " ++ show e
                          recordWarning $ GenericWarn (fromMaybe (getFC rawlhs) $ getErrorLoc e) (show e)
                          pure Nothing)
    getClause (Right c) = pure (Just c)

    checkCoverage : Int -> ClosedTerm -> RigCount ->
                    List (Either RawImp Clause) ->
                    Core Covering
    checkCoverage n ty mult cs
        = do covcs' <- traverse getClause cs -- Make stand in LHS for impossible clauses
             log "declare.def" 5 $ unlines
               $ "Using clauses :"
               :: map (("  " ++) . show) !(traverse toFullNames covcs')
             let covcs = mapMaybe id covcs'
             (_ ** (ctree, _)) <-
                 getPMDef fc (CompileTime mult) (Resolved n) ty covcs
             logC "declare.def" 3 $ do pure $ "Working from " ++ show !(toFullNames ctree)
             missCase <- if any catchAll covcs
                            then do logC "declare.def" 3 $ do pure "Catch all case in \{show !(getFullName (Resolved n))}"
                                    pure []
                            else getMissing fc (Resolved n) ty ctree
             logC "declare.def" 3 $
                     do mc <- traverse toFullNames missCase
                        pure ("Initially missing in " ++
                                 show !(getFullName (Resolved n)) ++ ":\n" ++
                                showSep "\n" (map show mc))
             -- Filter out the ones which are impossible
             missImp <- traverse (checkImpossible n mult) missCase
             -- Filter out the ones which are actually matched (perhaps having
             -- come up due to some overlapping patterns)
             missMatch <- traverse (checkMatched (not $ isErased mult) covcs) (mapMaybe id missImp)
                                              -- ^ Do not check coverage for erased arguments
                                              -- only in non-erased functions (Issues #1998, #3357)
             let miss = catMaybes missMatch
             if isNil miss
                then do [] <- getNonCoveringRefs fc (Resolved n)
                           | ns => toFullNames (NonCoveringCall ns)
                        pure IsCovering
                else pure (MissingCases miss)
