module RefinementPPDATE (specRefinement, getClassVar) where

import Types
import CommonFunctions
import Translators.DL2JML
import UpgradePPDATE
import Data.List
import Data.Maybe
import Optimisations.Optimisations
import qualified ParserActions.ParserAct as ParAct
import ErrM
import qualified ParserActions.PrintActions as PrintAct
import Translators.TranslatorActions
import Translators.PPDATE2Script
import Control.Lens hiding(Context,pre)


specRefinement :: UpgradePPD PPDATE -> Either [Proof] [Proof] -> Filename -> FilePath -> IO (UpgradePPD PPDATE)
specRefinement ppdate (Left []) _ _  = return $ translateActions $ replacePInit $ namedCreateActPPD ppdate
specRefinement ppdate (Right []) _ _ =
 if (null (_htsGet $ getValue ppdate))
 then return $ translateActions $ replacePInit $ namedCreateActPPD ppdate
 else let ppdref = generateNewTriggers ppdate (_htsGet $ getValue ppdate)  
      in return $ translateActions $ replacePInit $ namedCreateActPPD ppdref
specRefinement ppdate (Right proofs) fn output_addr =
 do let ppdref  = refinePPDATE ppdate proofs
    let ppdref' = prepareRefPPD ppdref
    let ppdate' = translateActions $ replacePInit $ namedCreateActPPD ppdref
    let refFile = output_addr ++ generateRefPPDFileName fn
    writeFile refFile (ppd2Script $ getValue ppdref')
    return ppdate'

-------------------------
-- Auxiliary functions --
-------------------------

generateRefPPDFileName :: Filename -> Filename
generateRefPPDFileName fn = 
 let (ext, _:name) = break ('.' ==) $ reverse fn 
     xs = splitOnIdentifier "/" name     
 in if (length xs == 1)
    then reverse name ++ "_optimised.ppd"
    else reverse (head xs) ++ "_optimised.ppd"

prepareRefPPD :: UpgradePPD PPDATE -> UpgradePPD PPDATE
prepareRefPPD = removeGeneratedTriggers

removeGeneratedTriggers :: UpgradePPD PPDATE -> UpgradePPD PPDATE
removeGeneratedTriggers ppd = 
 do ppdate <- ppd
    return $ remGeneratedTriggers ppdate

remGeneratedTriggers :: PPDATE -> PPDATE
remGeneratedTriggers ppdate@(PPDATE _ (Global ctxt@(Ctxt [] [] [] PNIL (foreach:fors))) _ _ _ _) = 
 let for'    = getCtxtForeach %~ removeFromTrsCtxt $ foreach
     fors'   = for':fors
 in ppdate & (globalGet . ctxtGet . foreaches) .~ fors'
remGeneratedTriggers ppdate = (globalGet . ctxtGet) %~ removeFromTrsCtxt $ ppdate

removeFromTrsCtxt :: Context -> Context 
removeFromTrsCtxt ctxt = triggers %~ removeFromTriggers $ ctxt

removeFromTriggers :: Triggers -> Triggers
removeFromTriggers []       = []
removeFromTriggers (tr:trs) = 
 if isInfixOf "_ppden" (tr ^. tName) || isInfixOf "_ppdex" (tr ^. tName)
 then removeFromTriggers trs
 else tr:removeFromTriggers trs

-----------------------
-- ppDATE refinement --
-----------------------

refinePPDATE :: UpgradePPD PPDATE -> [Proof] -> UpgradePPD PPDATE
refinePPDATE ppd proofs = 
 let ppdate    = getValue ppd 
     env       = getEnvVal ppd
     consts    = ppdate ^. htsGet
     nproved   = filter (\npr -> (not.null) (npr ^. _3)) $ map getInfoFromProof proofs
     proved    = filter (\pr -> null (pr ^. _3)) $ map getInfoFromProof proofs
     consts'   = [c | c <- consts, npr <- nproved, c ^. htName == npr ^. _2]  
     cproved   = [c | c <- consts, pr <- proved, c ^. htName == pr ^. _2]
     ppd'      = generateNewTriggers ppd consts'
     ppdate'   = getValue ppd'
     global    = ppdate' ^. globalGet
     triggers' = getAllTriggers global env
     consts''  = strengthenPre $ updateHTs nproved consts' triggers'
     env'      = getEnvVal ppd'
     chan      = map (caiArgs %~ (map (optimisedProvenHTs cproved rArgsByNull))) $ allCreateAct env'
     chan'     = map (caiAct %~ (optimisedProvenHTs cproved rActionsByNull)) $ chan
     env''     = env' { allCreateAct = chan' }
     global'   = optimisedProvenHTs cproved refinePropertyOptGlobal global
     temps     = ppdate' ^. templatesGet
     temps'    = optimisedProvenHTs cproved refinePropertyOptTemplates temps
     ppdate''  = ppdate' & globalGet .~ global' & htsGet .~ consts'' & templatesGet .~ temps'
 in do put env''
       return ppdate''

-----------------------------------------------------------------
-- Generate name for the channels associated to actions create --
-----------------------------------------------------------------

namedCreateActPPD :: UpgradePPD PPDATE -> UpgradePPD PPDATE
namedCreateActPPD ppd = 
 do let env = getEnvVal ppd
    put (namedCreateAct env)
    return (getValue ppd)

namedCreateAct :: Env -> Env
namedCreateAct env =
 let xs = allCreateAct env 
     ys = genChannelNames $ zip xs [1..length xs]
 in env { allCreateAct = ys}

genChannelNames :: [(CreateActInfo,Int)] -> [CreateActInfo]
genChannelNames []                 = []
genChannelNames ((cai,n):xs) = (caiCh .~ ("cact"++show n) $ cai):genChannelNames xs

---------------------------------------------------------------------------------------
-- Translates actions specific to ppDATEs into Larva artifacts (i.e. DATE's actions) --
---------------------------------------------------------------------------------------

translateActions :: UpgradePPD PPDATE -> UpgradePPD PPDATE
translateActions ppd =
 do ppdate <- ppd
    return $ translateActInPPD ppdate (getEnvVal ppd)

translateActInPPD :: PPDATE -> Env -> PPDATE
translateActInPPD (PPDATE imps global temps cinvs hts ms) env = 
 PPDATE imps (translateActInGlobal global env) (translateActInTemps temps env) cinvs hts ms

translateActInGlobal :: Global -> Env -> Global
translateActInGlobal (Global ctxt) env = Global (translateActInCtxt ctxt env)

translateActInCtxt :: Context -> Env -> Context
translateActInCtxt ctxt env = 
 ctxt & property %~ (\ p -> translateActInProps p env)
      & foreaches %~ (translateActInFors env)
 
translateActInProps :: Property -> Env -> Property
translateActInProps PNIL _                            = PNIL
translateActInProps (PINIT nm tmp bnds props) env     = PINIT nm tmp bnds (translateActInProps props env)
translateActInProps (Property nm sts trans props) env = Property nm sts (translateActInTrans env trans) (translateActInProps props env)

translateActInFors :: Env -> Foreaches -> Foreaches
translateActInFors env = map (translateActInFor env)

translateActInFor :: Env -> Foreach -> Foreach
translateActInFor env foreach = getCtxtForeach %~ (\ ctxt -> translateActInCtxt ctxt env) $ foreach

translateActInTrans :: Env -> Transitions -> Transitions
translateActInTrans env = map (translateActInTran env)

translateActInTran :: Env -> Transition -> Transition
translateActInTran env (Transition q (Arrow tr cond act) q') =
 Transition q (Arrow tr cond (translateAction act env)) q'

translateAction :: Action -> Env -> Action
translateAction [] _    = ""
translateAction act env = 
 case ParAct.parse act of 
      Ok ac -> PrintAct.printTree (translateAct ac env)

translateActInTemps :: Templates -> Env -> Templates
translateActInTemps TempNil _       = TempNil
translateActInTemps (Temp tmps) env = Temp $ map (translateActInTemp env) tmps

translateActInTemp :: Env -> Template -> Template
translateActInTemp env tmp = tempProp %~ (\ t -> translateActInProps t env) $ tmp


------------------------------------------------------
-- Get information from the results produced by KeY --
------------------------------------------------------

updateHTs :: [(MethodName, HTName, [Pre],String)] -> HTriples -> Triggers -> HTriples
updateHTs [] consts _      = consts
updateHTs (x:xs) consts es = updateHTs xs (updateHT x consts es) es

updateHT :: (MethodName, HTName, [Pre],String) -> HTriples -> Triggers -> HTriples
updateHT (mn,cn,pres,path) [] _      = []
updateHT (mn,cn,pres,path) (c:cs) es = 
 if (c ^. htName == cn && (_methodCN c ^. mname) == mn)
 then if (null pres)
      then c:updateHT (mn,cn,pres,path) cs es
      else let pres' = removeDuplicates pres
               opt'  = simplify $ map refineNewCond pres'
               opt'' = '(':introduceOr opt' ++ [')']
               c'    = c & pre %~ refineCond 
                         & post %~ refineCond  
                         & newPRe .~ [opt'']
                         & path2it .~ path 
           in c':cs
 else c:updateHT (mn,cn,pres,path) cs es

getClassVar :: HT -> Triggers -> TriggerVariation -> String
getClassVar c es ev = lookupClassVar es c ev

refineNewCond :: Pre -> Pre
refineNewCond = addParenthesisNot . removeDLstrContent

refineCond :: Pre -> Pre
refineCond = removeDLstrContent


-- returns variable name used to instantiate the class in the ppDATE
lookupClassVar :: Triggers -> HT -> TriggerVariation -> String
lookupClassVar trs c ev = 
 let trs' = filterTriggers trs c ev
 in case getGeneratedExTr trs' c of
         []   -> getExTr trs' c ev
         [id] -> id

filterTriggers :: Triggers -> HT -> TriggerVariation -> Triggers
filterTriggers [] _ _      = []
filterTriggers (e:es) c ev = 
 case (e ^. compTrigger) of
      NormalEvent (BindingVar _) id _ ev' -> 
           let mn = _methodCN c ^. mname 
               ov = _methodCN c ^. overl
           in if (id == mn && compareEV ev ev'
                 && checkArgsOver (e ^. args) (getCTArgs (e ^. compTrigger)) (_methodCN c ^. overl))
              then e:filterTriggers es c ev
              else filterTriggers es c ev
      _                                   -> filterTriggers es c ev

getGeneratedExTr :: Triggers -> HT -> [String]
getGeneratedExTr [] _       = []
getGeneratedExTr (tr:trs) c = 
  case (tr ^. compTrigger) of
      NormalEvent (BindingVar b) id _ ev' -> 
                  if (isInfixOf "_ppdex" (tr ^. tName) && checkArgsOver (tr ^. args) (getCTArgs (tr ^. compTrigger)) (_methodCN c ^. overl)) 
                  then case getIdBind b of
                            "" -> []
                            id -> [id]
                  else getGeneratedExTr trs c

getExTr :: Triggers -> HT -> TriggerVariation -> String
getExTr [] _ _      = ""
getExTr (e:es) c ev = 
 case (e ^. compTrigger) of
      NormalEvent (BindingVar b) id _ ev' -> 
                  if (id == (_methodCN c ^. mname) && compareEV ev ev')
                  then getIdBind b
                  else getExTr es c ev
      _                                   -> getExTr es c ev

checkArgsOver :: [Bind] -> [Bind] -> Overriding -> Bool
checkArgsOver _ _ OverNil  = True
checkArgsOver bs ceargs ov =
 let ov' = generateOverloading bs ceargs
 in ov == ov'
 

compareEV :: TriggerVariation -> TriggerVariation -> Bool
compareEV EVEntry EVEntry         = True
compareEV (EVExit _) (EVExit _)   = True
compareEV _ _                     = False

-----------------------------------------------------------------------------------------
-- Generate triggers whenever a method to be runtime verified is not associated to one --
-----------------------------------------------------------------------------------------

--If trigger associated to *, it will be considered as defined even if the the class is wrong
generateNewTriggers :: UpgradePPD PPDATE -> HTriples -> UpgradePPD PPDATE
generateNewTriggers ppd consts =
  do let env    = getEnvVal ppd
     let ppdate = getValue ppd     
     let mfiles = javaFilesInfo env
     let mns    = removeDuplicates $ map _methodCN consts
     let entry  = filterDefEntryTriggers mns (allTriggers env) 
     let entry' = [(mnc, checkOverloading (filter (\mn -> mnc ^. mname == mn ^. _2) (methodsInFiles (dz ^. _3))) (mnc ^. overl)) | mnc <- entry, dz <- mfiles, (dz ^. _2) == mnc ^. clinf]
     let exit   = [(mnc, checkOverloading (filter (\mn -> mnc ^. mname == mn ^. _2) (methodsInFiles (dz ^. _3))) (mnc ^. overl)) | mnc <- mns, dz <- mfiles, (dz ^. _2) == mnc ^. clinf]
     let scope  = properScope ppdate
     let (env',ppdate') = addNewTriggerEntry env 0 entry' ppdate scope
     let env''  = addNewTriggerExit env' (length entry') exit scope     
     put env''
     return ppdate'

checkOverloading :: [(Type,MethodName,[String],MethodInvocations,Modifier)] -> Overriding -> (Type,MethodName,[String],MethodInvocations,Modifier)
checkOverloading [] _             = error "Problem with overriding.\n"
checkOverloading (val:xs) OverNil = val
checkOverloading (val:xs) ov      = 
 if Over (map (getBindTypeType.makeBind) (val ^. _3)) == ov
 then val
 else checkOverloading xs ov

--Filter methods associated to entry triggers defined at top-level
filterDefEntryTriggers :: [MethodCN] -> [TriggersInfo] -> [MethodCN]
filterDefEntryTriggers [] _                                = []
filterDefEntryTriggers (mnc@(MCN ci mn OverNil):mncs) ts   = 
 if null [ t | t <- ts , tiCI t == ci, tiMN t == mn, tiTrvar t == EVEntry]
 then mnc:filterDefEntryTriggers mncs ts
 else filterDefEntryTriggers mncs ts
filterDefEntryTriggers (mnc@(MCN ci mn (Over xs)):mncs) ts = 
 if null [ t | t <- ts , tiCI t == ci, tiMN t == mn, tiTrvar t == EVEntry, tiOver t == (Over xs)]
 then mnc:filterDefEntryTriggers mncs ts
 else filterDefEntryTriggers mncs ts

--Creates the info to be added in the environment
createTriggerEntry :: (MethodCN,(String,MethodName,[String],MethodInvocations,Modifier)) -> Int -> Scope -> TriggersInfo
createTriggerEntry (mnc,inf) n scope = 
 let mn  = mnc ^. mname
     cn  = mnc ^. clinf
     ov  = mnc ^. overl
     xs  = inf ^. _3
 in if (mn == inf ^. _2)
    then let trnm = mn ++ "_ppden"++ (show n)
             nvar = "cv" ++ "_" ++ (show n)
             cn'  = cn ++ " " ++ nvar
             cpe  = NormalEvent (BindingVar (BindType cn nvar)) mn (map ((\[x,y] -> BindId y).words.remGenerics') xs) EVEntry
             tr   = TriggerDef trnm (map ((\[x,y] -> BindType x y).words.remGenerics') xs) cpe ""
             bs   = map ((\[x,y] -> BindType x y).words.remGenerics') xs             
         in TI trnm mn cn nvar EVEntry bs (Just tr) scope ov
    else error $ "Problem when creating an entry trigger. Mismatch between method names " ++ mn ++ " and " ++ inf ^. _2 ++ ".\n"

addNewTriggerEntry :: Env -> Int -> [(MethodCN,(Type,MethodName,[String],MethodInvocations,Modifier))] -> PPDATE -> Scope -> (Env,PPDATE)
addNewTriggerEntry env _ [] ppd _         = (env,ppd)
addNewTriggerEntry env n (x:xs) ppd scope =
 let tinfo = createTriggerEntry x n scope
     ppd'  = addTrigger2ppDATE (fromJust (tiTrDef tinfo)) ppd
 in addNewTriggerEntry (env { allTriggers = tinfo:allTriggers env}) (n+1) xs ppd' scope


--Creates the info to be added in the environment
createTriggerExit:: (MethodCN,(String,MethodName,[String],MethodInvocations,Modifier)) -> Int -> Scope -> TriggersInfo
createTriggerExit (mnc,inf) n scope = 
 let mn   = mnc ^. mname
     cn   = mnc ^. clinf
     ov   = mnc ^. overl
     rt   = inf ^. _1
     xs'  = inf ^. _3
     trnm = mn ++ "_ppdex"
     nvar = "cv" ++ "_" ++ (show n)
     cn'  = cn ++ " " ++ nvar
     ret  = "ret_ppd" ++ (show n)
     xs   = map remGenerics' xs' in
 if (mn == inf ^. _2)
 then if (rt == "void")
      then let bs  = map ((\[x,y] -> BindType x y).words.remGenerics') xs
               cpe = NormalEvent (BindingVar (BindType cn nvar)) mn (map ((\[x,y] -> BindId y).words.remGenerics') xs) (EVExit [])
               tr  = TriggerDef trnm bs cpe ""
           in TI trnm mn cn nvar (EVExit []) bs (Just tr) scope ov
      else let bs  = (map ((\[x,y] -> BindType x y).words) xs ++ [BindType rt ret])
               cpe = NormalEvent (BindingVar (BindType cn nvar)) mn (map ((\[x,y] -> BindId y).words.remGenerics') xs) (EVExit [BindId ret]) 
               tr  = TriggerDef trnm bs cpe ""
           in TI trnm mn cn nvar (EVExit [BindId ret]) bs (Just tr) scope ov
 else error $ "Problem when creating an exit trigger. Mismatch between method names " ++ mn ++ " and " ++ inf ^. _2 ++ ".\n"

addNewTriggerExit :: Env -> Int -> [(MethodCN,(Type,MethodName,[String],MethodInvocations,Modifier))] -> Scope -> Env
addNewTriggerExit env _ [] _         = env
addNewTriggerExit env n (x:xs) scope =
 let tinfo  = createTriggerExit x n scope
 in addNewTriggerExit (env { allTriggers = tinfo:allTriggers env }) (n+1) xs scope


addTrigger2ppDATE :: TriggerDef -> PPDATE -> PPDATE
addTrigger2ppDATE tr (PPDATE imp (Global (Ctxt [] [] [] PNIL (f:fs))) temps ci consts ms) =
 PPDATE imp (Global (Ctxt [] [] [] PNIL (addTrigger2Foreach (f:fs) tr))) temps ci consts ms
addTrigger2ppDATE tr (PPDATE imp (Global (Ctxt vars ies trs p for)) temps ci consts ms) =
 PPDATE imp (Global (Ctxt vars ies (tr:trs) p for)) temps ci consts ms

addTrigger2Foreach :: Foreaches -> TriggerDef -> Foreaches
addTrigger2Foreach [Foreach [Args t id] (Ctxt vars ies trs p for) id'] tr = 
 [Foreach [Args t id] (Ctxt vars ies (trs ++ [updateWhereTr tr (Args t id)]) p for) id']

updateWhereTr :: TriggerDef -> Args -> TriggerDef
updateWhereTr (TriggerDef tn args (NormalEvent (BindingVar (BindType cn cl)) id' xs v) w) (Args t id) = 
 if t == cn
 then TriggerDef tn args (NormalEvent (BindingVar (BindType cn cl)) id' xs v) (id ++ " = " ++ cl ++ ";")
 else TriggerDef tn args (NormalEvent (BindingVar (BindType cn cl)) id' xs v) (id ++ " = null ;")
updateWhereTr (TriggerDef tn args (NormalEvent (BindingVar (BindTypeExec cn cl)) id' xs v) w) (Args t id) = 
 if t == cn
 then TriggerDef tn args (NormalEvent (BindingVar (BindTypeExec cn cl)) id' xs v) (id ++ " = " ++ cl ++ ";")
 else TriggerDef tn args (NormalEvent (BindingVar (BindTypeExec cn cl)) id' xs v) (id ++ " = null ;")
updateWhereTr (TriggerDef tn args (NormalEvent (BindingVar (BindTypeCall cn cl)) id' xs v) w) (Args t id) = 
 if t == cn
 then TriggerDef tn args (NormalEvent (BindingVar (BindTypeCall cn cl)) id' xs v) (id ++ " = " ++ cl ++ ";")
 else TriggerDef tn args (NormalEvent (BindingVar (BindTypeCall cn cl)) id' xs v) (id ++ " = null ;")


makeBind :: String -> Bind
makeBind [] = error "Cannot make bind\n."
makeBind s  = (\[x,y] -> BindType x y) $ words s

--Removes generics from the type of the arguments
remGenerics' :: String -> String
remGenerics' s = 
 let ys = splitAtIdentifier '<' s
 in if (not.null.snd) ys 
    then let xs = (splitAtIdentifier '>'.reverse.tail.snd) ys in
         if (not.null.snd) xs
         then fst ys ++ (reverse $ fst xs)
         else error "Problem with generics.\n"
    else s

--Returns the scope where the generated triggers should be placed
properScope :: PPDATE -> Scope
properScope ppd = 
 let vars   = ppd ^. (globalGet . ctxtGet . variables)
     actes  = ppd ^. (globalGet . ctxtGet . actevents)
     trs    = ppd ^. (globalGet . ctxtGet . triggers)
     props  = ppd ^. (globalGet . ctxtGet . property)
 in if and [null vars,null actes,null trs,PNIL == props]
    then InFor (ForId "TopLevel")
    else TopLevel

