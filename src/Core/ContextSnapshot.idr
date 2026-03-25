||| Save and restore the fully-loaded context to/from a single binary file.
||| This avoids re-reading dozens of TTC files on cold start.
module Core.ContextSnapshot

import Core.Binary
import public Core.Binary.Prims
import Core.Context
import Core.Context.Context
import Core.Core
import Core.TTC
import Core.UnifyState

import Idris.Syntax
import Idris.Syntax.TTC

import Libraries.Data.IntMap as IntMap
import Libraries.Data.NameMap
import Libraries.Utils.Binary

import Data.IOArray
import System.File

%default covering

snapshotVersion : Int
snapshotVersion = 1

-- Collect all (Name, Namespace, Binary) from the Context's IOArray.
-- Skips Decoded entries (builtins added by addPrimitives) since those
-- are re-added on load.
collectEntries : Context -> Core (List (Name, Namespace, Binary))
collectEntries ctxt
    = do let n = nextEntry ctxt
         arr <- get Arr @{content ctxt}
         -- Build reverse map: Int -> Name from resolvedAs
         let nameList = NameMap.toList (resolvedAs ctxt)
         let revMap = foldl (\m, (name, idx) => IntMap.insert idx name m)
                            IntMap.empty nameList
         go arr revMap 0 n []
  where
    go : IOArray ContextEntry -> IntMap.IntMap Name ->
         Int -> Int -> List (Name, Namespace, Binary) ->
         Core (List (Name, Namespace, Binary))
    go arr revMap idx limit acc
        = if idx >= limit
             then pure (reverse acc)
             else do Just entry <- coreLift (readArray arr idx)
                       | Nothing => go arr revMap (idx + 1) limit acc
                     case entry of
                          Coded ns bin =>
                            case IntMap.lookup idx revMap of
                                 Just name => go arr revMap (idx + 1) limit
                                                ((name, ns, bin) :: acc)
                                 Nothing => go arr revMap (idx + 1) limit acc
                          Decoded _ =>
                            -- Skip decoded entries (builtins); re-added on load
                            go arr revMap (idx + 1) limit acc

fullPair : Context -> Maybe PairNames -> Core (Maybe PairNames)
fullPair gam Nothing = pure Nothing
fullPair gam (Just (MkPairNs t f s))
    = pure $ Just $ MkPairNs !(full gam t) !(full gam f) !(full gam s)

fullRW : Context -> Maybe RewriteNames -> Core (Maybe RewriteNames)
fullRW gam Nothing = pure Nothing
fullRW gam (Just (MkRewriteNs e r))
    = pure $ Just $ MkRewriteNs !(full gam e) !(full gam r)

fullPrim : Context -> PrimNames -> Core PrimNames
fullPrim gam (MkPrimNs mi ms mc md mt mn mdl)
    = [| MkPrimNs (full gam mi)
                  (full gam ms)
                  (full gam mc)
                  (full gam md)
                  (full gam mt)
                  (full gam mn)
                  (full gam mdl) |]

||| Save the current context state to a snapshot file.
export
saveSnapshot : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto s : Ref Syn SyntaxInfo} ->
               (snapshotFile : String) ->
               (sourceFile : String) ->
               (sourceContent : String) ->
               Core ()
saveSnapshot snapshotFile sourceFile sourceContent
    = do defs <- get Ctxt
         ust <- get UST
         syn <- get Syn
         let gam = gamma defs

         -- Collect context entries
         entries <- collectEntries gam

         -- Convert Resolved names to full names for serialization
         -- typeHints: NameMap (List (Name, Bool)) → List (Name, Name, Bool)
         let typeHRaw = concatMap (\(k, vs) => map (\(n,b) => (k,n,b)) vs)
                                 (NameMap.toList (typeHints defs))
         typeH <- traverse (\(k,n,b) => pure (!(full gam k), !(full gam n), b)) typeHRaw
         -- autoHints: NameMap Bool → List (Name, Bool)
         autoH <- traverse (\(n,b) => pure (!(full gam n), b))
                           (NameMap.toList (autoHints defs))
         -- transforms: NameMap (List Transform) → List (Name, Transform)
         let transfRaw = concatMap (\(k, ts) => map (\t => (k, t)) ts)
                                   (NameMap.toList (transforms defs))
         transf <- traverse (\(n,t) => pure (!(full gam n), !(full gam t))) transfRaw
         -- userHoles
         uholes <- traverse (full gam) (keys (userHoles defs))
         -- namedirectives
         nds <- traverse (\(n,ds) => pure (!(full gam n), ds))
                         (NameMap.toList (namedirectives defs))
         -- foreignExports
         fexps <- traverse (\(n,es) => pure (!(full gam n), es))
                           (NameMap.toList (foreignExports defs))
         -- Options
         pns <- fullPair gam (pairnames (options defs))
         rws <- fullRW gam (rewritenames (options defs))
         prims <- fullPrim gam (primnames (options defs))
         fimpl <- traverse (\(n,s) => pure (!(full gam n), s))
                           (foreignImpl (options defs))

         -- Write snapshot
         bin <- initBinary
         toBuf "SNAP"
         toBuf snapshotVersion
         toBuf ttcVersion
         toBuf sourceFile
         toBuf sourceContent

         -- Context entries: List (Name, Namespace, Binary)
         toBuf (cast {to=Int} (length entries))
         traverse_ (\(n, ns, b) => do toBuf n; toBuf ns; toBuf b) entries

         -- Visible namespaces
         toBuf (visibleNS gam)

         -- Defs metadata
         toBuf (allImported defs)
         toBuf typeH
         toBuf autoH
         toBuf transf
         toBuf (imported defs)
         toBuf (currentNS defs)
         toBuf (nestedNS defs)
         toBuf nds
         toBuf (cgdirectives defs)
         toBuf fexps
         toBuf uholes
         toBuf (ifaceHash defs)
         toBuf (importHashes defs)

         -- Options
         toBuf pns
         toBuf rws
         toBuf prims
         toBuf fimpl

         -- Syntax info
         toBuf syn

         -- UState
         toBuf (nextName ust)

         Right () <- coreLift $ writeToFile snapshotFile !(get Bin)
            | Left err => pure () -- silently fail; not critical
         pure ()

||| Try to load a context snapshot. Returns True if successful.
export
loadSnapshot : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto s : Ref Syn SyntaxInfo} ->
               (snapshotFile : String) ->
               (sourceFile : String) ->
               (sourceContent : String) ->
               Core Bool
loadSnapshot snapshotFile sourceFile sourceContent
    = do Right buffer <- coreLift $ readFromFile snapshotFile
            | Left err => pure False
         bin <- newRef Bin buffer
         catch (loadFromBin bin)
               (\err => pure False)
  where
    restoreEntries : Ref Bin Binary -> Int -> Core ()
    restoreEntries bin 0 = pure ()
    restoreEntries bin remaining
        = do n <- fromBuf {a=Name}
             ns <- fromBuf {a=Namespace}
             b <- fromBuf {a=Binary}
             ignore $ addContextEntry ns n b
             restoreEntries bin (remaining - 1)

    loadFromBin : Ref Bin Binary -> Core Bool
    loadFromBin bin
        = do -- Validate header
             hdr <- fromBuf {a=String}
             when (hdr /= "SNAP") $ throw (InternalError "Not a snapshot")
             sv <- fromBuf {a=Int}
             when (sv /= snapshotVersion) $ throw (InternalError "Snapshot version mismatch")
             tv <- fromBuf {a=Int}
             when (tv /= ttcVersion) $ throw (InternalError "TTC version mismatch")

             -- Validate source
             sf <- fromBuf {a=String}
             sc <- fromBuf {a=String}
             when (sf /= sourceFile) $ throw (InternalError "Source file mismatch")
             when (sc /= sourceContent) $ throw (InternalError "Source content changed")

             -- Restore context entries
             numEntries <- fromBuf {a=Int}
             restoreEntries bin numEntries

             -- Restore visible namespaces
             visNS <- fromBuf {a=List Namespace}
             traverse_ (\ns => update Ctxt { gamma->visibleNS $= (ns ::) }) visNS

             -- Restore Defs metadata
             allImp <- fromBuf {a=List (String, (ModuleIdent, Bool, Namespace))}
             typeH <- fromBuf {a=List (Name, Name, Bool)}
             autoH <- fromBuf {a=List (Name, Bool)}
             transf <- fromBuf {a=List (Name, Transform)}
             imp <- fromBuf {a=List (ModuleIdent, Bool, Namespace)}
             cns <- fromBuf {a=Namespace}
             nns <- fromBuf {a=List Namespace}
             nds <- fromBuf {a=List (Name, List String)}
             cgds <- fromBuf {a=List (CG, String)}
             fexps <- fromBuf {a=List (Name, List (String, String))}
             uholes <- fromBuf {a=List Name}
             ihash <- fromBuf {a=Int}
             ihashes <- fromBuf {a=List (Namespace, Int)}

             -- Options
             pns <- fromBuf {a=Maybe PairNames}
             rws <- fromBuf {a=Maybe RewriteNames}
             prims <- fromBuf {a=PrimNames}
             fimpl <- fromBuf {a=List (Name, String)}

             -- Syntax
             syn <- fromBuf {a=SyntaxInfo}

             -- UState
             nextV <- fromBuf {a=Int}

             -- Rebuild NameMaps from flat lists
             let typeHMap = foldl (\m, (k,n,b) =>
                     case NameMap.lookup k m of
                          Nothing => insert k [(n,b)] m
                          Just vs => insert k ((n,b) :: vs) m)
                     NameMap.empty typeH
             let autoHMap = fromList autoH
             let transfMap = foldl (\m, (k,t) =>
                     case NameMap.lookup k m of
                          Nothing => insert k [t] m
                          Just ts => insert k (t :: ts) m)
                     NameMap.empty transf

             -- Apply metadata to Defs
             update Ctxt { allImported := allImp
                         , typeHints := typeHMap
                         , autoHints := autoHMap
                         , transforms := transfMap
                         , imported := imp
                         , currentNS := cns
                         , nestedNS := nns
                         , namedirectives := fromList nds
                         , cgdirectives := cgds
                         , foreignExports := fromList fexps
                         , ifaceHash := ihash
                         , importHashes := ihashes
                         , options->pairnames := pns
                         , options->rewritenames := rws
                         , options->primnames := prims
                         , options->foreignImpl := fimpl
                         }
             traverse_ (\n => update Ctxt { userHoles $= insert n True }) uholes

             -- Restore syntax
             put Syn syn

             -- Restore UState
             update UST { nextName := nextV }

             pure True
