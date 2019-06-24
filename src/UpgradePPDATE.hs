{-# LANGUAGE TemplateHaskell #-}

module UpgradePPDATE where

import Types
import CommonFunctions
import Control.Monad
import Control.Monad.Writer
import qualified Control.Monad.State as CM
import qualified Data.Map.Strict as Map
import qualified ParserPPDATE.AbsPpdate as Abs
import qualified ParserActions.AbsActions as Act
import ErrM
import ParserPPDATE.PrintPpdate
import qualified ParserActions.PrintActions as PrintAct
import qualified JML.PrintJml as PrintJML
import ParserPPDATE.Parser
import qualified ParserActions.ParserAct as ParAct
import qualified JML.ParserJML as ParJML
import Data.List
import Data.Either
import Data.Maybe
import Translators.PPDATE2Script
import Control.Lens hiding(Context,pre)
import Java.JavaLanguage


upgradePPD :: Abs.AbsPPDATE -> UpgradePPD PPDATE
upgradePPD (Abs.AbsPPDATE imports global temps cinvs consts methods) =
 chainExec (imports, global, temps, cinvs, consts, methods) (PPDATE [] nilGlobal TempNil [] [] []) emptyEnv [] 1
          where nilGlobal = undefined --Hack. This should not affect the execution of the tool.
                              
chainExec :: (Abs.Imports, Abs.Global, Abs.Templates, Abs.CInvariants, Abs.HTriples, Abs.Methods) -> PPDATE -> Env -> [String] -> Int -> UpgradePPD PPDATE
chainExec ppdatep ppd env errs 6 = 
 if null errs
 then do put env
         return ppd
 else fail $ concat errs
chainExec ppdatep ppd env errs n = 
 case n of
      1 -> let ppd'  = importsGet .~ genImports (ppdatep ^. _1) $ ppd
               ppd'' = methodsGet .~ genMethods (ppdatep ^. _6) $ ppd' 
           in let imps  = ppd' ^. importsGet
                  imps' = getDuplicates imps
              in if (null imps') 
                 then chainExec ppdatep ppd'' env errs 2
                 else chainExec ppdatep ppd'' env (errs ++ (duplicateImps imps')) 2
      2 -> case runWriter (genHTs (ppdatep ^. _5) (ppd ^. importsGet)) of
                (consts', []) -> let dcs  = getDuplicate $ map (^. htName) consts'
                                     env' = env { htsNames = map (^. htName) consts' }
                                 in if not (null dcs)
                                    then chainExec ppdatep (htsGet .~ consts' $ ppd) env' (duplicateHT dcs:errs) 3
                                    else chainExec ppdatep (htsGet .~ consts' $ ppd) env' errs 3
                (consts', err) -> let dcs  = getDuplicate $ map (^. htName) consts'
                                      env' = env { htsNames = map (^. htName) consts' }
                                  in if not (null dcs)
                                     then chainExec ppdatep (htsGet .~ consts' $ ppd) env' (duplicateHT dcs:err:errs) 3
                                     else chainExec ppdatep (htsGet .~ consts' $ ppd) env' (err:errs) 3
      3 -> case runStateT (genTemplates (ppdatep ^. _3)) env of
                Bad s            -> chainExec ppdatep ppd env (s:errs) 4
                Ok (temps',env') -> chainExec ppdatep (templatesGet .~ temps' $ ppd) env' errs 4
      4 -> case runStateT (genGlobal (ppdatep ^. _2)) env of
                Bad s              -> chainExec ppdatep ppd env (s:errs) 5
                Ok (global', env') -> chainExec ppdatep (globalGet .~ global' $ ppd) env' errs 5
      5 -> case runStateT (genClassInvariants (ppdatep ^. _4)) env of
                Bad s            -> chainExec ppdatep ppd env (s:errs) 6
                Ok (cinvs',env') -> chainExec ppdatep (cinvariantsGet .~ cinvs' $ ppd) env' errs 6

-------------
-- Imports --
-------------

genImports :: Abs.Imports -> Imports
genImports (Abs.ImportsNil)   = []
genImports (Abs.Imports imps) =
 let jfss = map getImportAbs imps
 in map (Import . joinImport . map (getIdAbs.getJFAbs)) jfss

duplicateImps :: Imports -> [String]
duplicateImps = map (\imp -> "Error: Multiple imports for " ++ (\(Import s) -> s) imp ++ ".\n")                    

------------
-- Global --
------------

genGlobal :: Abs.Global -> UpgradePPD Global
genGlobal (Abs.Global ctxt) =
 do ctxt' <- getCtxt ctxt TopLevel    
    return (Global ctxt')

-- Context --

getCtxt :: Abs.Context -> Scope -> UpgradePPD Context
getCtxt (Abs.Ctxt _ _ _ Abs.PropertiesNil Abs.ForeachesNil) _ = fail $ "Error: No properties were defined in section GLOBAL\n."
getCtxt (Abs.Ctxt Abs.VarNil Abs.ActEventsNil Abs.TriggersNil Abs.PropertiesNil foreaches@(Abs.ForeachesDef _ _ _)) TopLevel = getForeaches foreaches (Ctxt [] [] [] PNIL []) (InFor (ForId "TopLevel"))
getCtxt (Abs.Ctxt vars ies Abs.TriggersNil prop foreaches) scope =
 getCtxt (Abs.Ctxt vars ies (Abs.TriggersDef []) prop foreaches) scope
getCtxt (Abs.Ctxt vars ies trigs prop foreaches) scope =
 do vars' <- getVars vars
    trigs' <- getTriggers trigs scope []
    checkCollectionTrPPD trigs'
    env <- get
    let prop' = getProperty prop (map tiTN (allTriggers env)) env scope
    let ies'  = getActEvents ies ++ map ActEvent (actes env)
    case runWriter prop' of
         ((PNIL,env'),_)                    -> do put env'
                                                  getForeaches foreaches (Ctxt vars' ies' trigs' PNIL []) scope
         ((PINIT pname id xs props,env'),s) -> 
                  let trs = (addComma.removeDuplicates) [tr | tr <- s ^. _1
                                                              , not (elem tr (map ((\x -> x ++ "?").show) ies'))]
                      s'  = if (not.null) trs
                            then "Error: Trigger(s) [" ++ trs 
                                 ++ "] is(are) used in the transitions, but is(are) not defined in section TRIGGERS.\n" 
                                 ++ s ^. _2
                            else s ^. _2
                      s'' = if elem id (map fst $ tempsInfo env)
                            then ""
                            else "Error: In the definition of property " ++ pname
                                 ++ ". The template " ++ id ++ " does not exist\n."
                      s''' = s ^. _3
                      alls = s' ++ s'' ++ s'''
                  in if (null alls)
                     then do put env' 
                             getForeaches foreaches (Ctxt vars' ies' trigs' (PINIT pname id xs props) []) scope
                     else fail alls
         ((Property pname states trans props,env'),s) -> 
                  let trs    = (addComma.removeDuplicates) [tr | tr <- s ^. _1
                                                                 , not (elem tr (map ((\x -> x ++ "?").show) ies'))]
                      s'     = if (not.null) trs
                               then "Error: Trigger(s) [" ++ trs ++ "] is(are) used in the transitions, but is(are) not defined in section TRIGGERS.\n" 
                                    ++ s ^. _2 ++ s ^. _3 ++ s ^. _4
                               else s ^. _2 ++ s ^. _3 ++ s ^. _4 
                  in if (null s')
                     then do put env' 
                             getForeaches foreaches (Ctxt vars' ies' trigs' (Property pname states trans props) []) scope
                     else fail s'

-- Variables --

getVars :: Abs.Variables -> UpgradePPD Variables
getVars Abs.VarNil        = return []
getVars (Abs.VarDef vars) = sequence $ map getVariable vars

getVariable :: Abs.Variable -> UpgradePPD Variable
getVariable (Abs.Var varm t vdecls) =
 let varm' = getVarModif varm
     t'    = getTypeAbs t
     vs    = map getVarDecl vdecls
 in do env <- get
       put env { varsInPPD = Var varm' t' vs:varsInPPD env}
       return $ Var varm' t' vs

getVarModif :: Abs.VarModifier -> VarModifier
getVarModif Abs.VarModifierFinal = VarModifierFinal
getVarModif Abs.VarModifierNil   = VarModifierNil

getVarDecl :: Abs.VarDecl -> VarDecl
getVarDecl (Abs.VarDecl id varinit) = VarDecl (getIdAbs id) (getVarInitAbs varinit)

-- ActEvents --

getActEvents :: Abs.ActEvents -> ActEvents
getActEvents Abs.ActEventsNil       = []
getActEvents (Abs.ActEventsDef ies) = map (\(Abs.ActEvent ie) -> ActEvent (getIdAbs ie)) ies

-- Triggers --

getTriggers :: Abs.Triggers -> Scope -> [Args] -> UpgradePPD Triggers
getTriggers Abs.TriggersNil _ _             = return []
getTriggers (Abs.TriggersDef es) scope args =
 do env <- get
    let xs = map (\ tr -> getTrigger' scope tr args) es
    let (ls, rs) = partitionErr (map (\e -> CM.evalStateT e env) xs)
    if (null ls)
    then sequence xs
    else fail $ foldr joinBad "" ls 

joinBad :: Err a -> String -> String
joinBad (Bad s1) s2 = s1 ++ s2
joinBad _ _         = error "ppDATE refinement failure: joinBad \n"

getTrigger' :: Scope -> Abs.Trigger -> [Args] -> UpgradePPD TriggerDef
getTrigger' scope (Abs.Trigger id binds ce wc) args =
 do env  <- get
    let id'' = getIdAbs id
    let xs   = [ x | x <- allTriggers env, id'' == tiTN x, tiScope x == scope ]
    let err  = if (not.null) xs
               then "Error: Multiple definitions for trigger " 
                    ++ id'' ++ ".\n" ++ show scope ++ "\n" 
               else ""
    let (bs, s) = runWriter $ getBindsArgs binds
    let err0    = if (not.null) s 
                  then err ++ "Error: Trigger declaration [" ++ id'' 
                       ++ "] uses wrong argument(s) [" ++ s ++ "].\n"
                  else err
    let (ce',s') = runWriter (getCompTriggers ce env)
    let err1 = if (not.null) s'
               then err0 ++ ("Error: Trigger declaration [" ++ id'' 
                    ++ "] uses wrong argument(s) [" ++ s' ++ "] in the method component.\n")
               else err0
    let argss = map getIdBind bs
    case ce' of
         NormalEvent (BindingVar bind) mn args' eventv
            -> let allArgs = map getIdBind (filter (\ c -> not (isBindStar c)) args') in
               case eventv of
                    EVEntry  ->
                       let id  = getIdBind bind
                           wcs = [x | x <- argss, not(elem x allArgs)]
                           vs  = filter (\ x -> x /= id) $ checkVarsInitialisation wcs (getVarsWC wc)
                       in if ((not.null) vs) 
                          then fail $ err1 ++ "Error: Missing Initialization of variable(s) " 
                                      ++ show vs ++  " in trigger declaration [" ++ id'' ++ "].\n"
                          else do let (b,zs)   = runWriter ((checkAllArgs argss allArgs bind))
                                  let (b',s'') = runWriter (checkSpecialCases b mn bind bs [] zs id'' env scope)
                                  if b' 
                                  then if (not.null) err1 
                                       then fail err1 
                                       else do let ov = generateOverloading bs (getCTArgs ce')
                                               (ci,cinm) <- getClassVarName id'' mn bs bind s'' scope args
                                               let tr = TriggerDef { _tName = id''
                                                                   , _args  = bs
                                                                   , _compTrigger = ce'
                                                                   , _whereClause = getWhereClause wc
                                                                   }
                                               let ti = TI id'' mn ci cinm EVEntry bs (Just tr) scope ov
                                               put env { allTriggers = ti : allTriggers env }
                                               return tr
                                  else fail (err1 ++ s'')
                    EVExit rs ->
                       let id  = getIdBind bind
                           wcs = [x | x <- argss, not(elem x allArgs)]
                           rs' = map getIdBind rs
                           vs  = filter (\ x -> (not (elem x rs')) && (x /= id)) $ checkVarsInitialisation wcs (getVarsWC wc)
                       in if ((not.null) vs) 
                          then fail $ err1 ++ "Error: Missing Initialization of variable(s) " 
                                      ++ show vs ++ " in trigger declaration [" ++ id'' ++ "].\n"
                          else do let (b,zs)   = runWriter ((checkAllArgs argss allArgs bind))
                                  let (b',s'') = runWriter (checkSpecialCases b mn bind bs rs zs id'' env scope)
                                  if (b' && (checkRetVar rs argss))
                                  then if (not.null) err1 
                                       then fail err1 
                                       else do (ci,cinm) <- getClassVarName id'' mn bs bind s'' scope args
                                               let ov = generateOverloading bs (getCTArgs ce')
                                               let tr = TriggerDef { _tName = id''
                                                                   , _args  = bs
                                                                   , _compTrigger = ce'
                                                                   , _whereClause = getWhereClause wc
                                                                   }
                                               let ti = TI id'' mn ci cinm (EVExit rs) bs (Just tr) scope ov
                                               put env { allTriggers = ti : allTriggers env }
                                               return tr
                                  else fail (err1 ++ s'')
                    _        -> return TriggerDef { _tName = id''
                                                  , _args  = bs
                                                  , _compTrigger = ce'
                                                  , _whereClause = getWhereClause wc
                                                  }
         _  -> if (not.null) err1 then fail err1 else
               do put env { allTriggers = TI id'' "" "" "" EVNil bs Nothing scope OverNil: allTriggers env }
                  return TriggerDef { _tName = id''
                                    , _args  = bs
                                    , _compTrigger = ce'
                                    , _whereClause = getWhereClause wc
                                    }

generateOverloading :: [Bind] -> [Bind] -> Overriding
generateOverloading bs [] = Over []
generateOverloading bs ms = Over $ map (getTypeForOverLoading bs) (map getIdBind ms)

getTypeForOverLoading :: [Bind] -> Id -> Type
getTypeForOverLoading [] _                     = ""
getTypeForOverLoading ((BindType t id):bs) id' = if id == id' then t else getTypeForOverLoading bs id'


isBindStar :: Bind -> Bool
isBindStar BindStar     = True
isBindStar BindStarExec = True
isBindStar BindStarCall = True
isBindStar _            = False

--Method handling the special cases of the use of new and channels
checkSpecialCases :: Bool -> MethodName -> Bind -> [Bind] -> [Bind] -> [String] -> Trigger -> Env -> Scope -> Writer String Bool
checkSpecialCases b mn bind bs rs zs id env scope = 
 if b
 then return b
 else case runWriter (checkMNforNew mn bind bs rs id zs) of
           (True,_)  -> return True
           (False,s) -> if null s
                        then case runWriter (checkForChannel bind env) of
                                  (True,s)  -> writer (True,s)
                                  (False,s) -> if tempScope scope
                                               then writer (True,s)
                                               else if s == "not a channel"
                                                    then writer (False, "Error: In trigger declaration [" ++ id 
                                                                   ++ "], the bind [" 
                                                                   ++ show bind ++ "] is not recognised.\n")
                                                    else writer (False, "Error: Trigger declaration [" ++ id 
                                                                        ++ "] uses wrong argument(s) [" 
                                                                        ++ addComma zs ++ "] in the method component.\n")
                        else writer (False, s)

--Method handling new
checkMNforNew :: MethodName -> Bind -> [Bind] -> [Bind] -> Trigger ->  [String] -> Writer String Bool
checkMNforNew mn bind bs rs id zs = 
 case bind of
      BindId id -> if (mn /= "new")
                   then return False
                   else if null rs
                        then writer (False,"Error: new cannot be associated to an entry trigger.\n")
                        else if elem (BindType id (getIdBind (head rs))) bs
                             then if null zs 
                                  then return True
                                  else writer (False, "Error: Trigger declaration [" ++ id 
                                                      ++ "] uses wrong argument(s) [" ++ addComma zs 
                                                      ++ "] in the method component.\n")
                             else writer (False, "Error: Wrong exit object in trigger " ++ id ++ "\n.")
      _         -> return False

--Method handling channels
checkForChannel :: Bind -> Env -> Writer String Bool
checkForChannel bind env = 
 case bind of
      BindId id -> let vars = map varDecId $ concatMap getVarDeclVar 
                              $ filter (\v -> getTypeVar v == "Channel") $ varsInPPD env
                   in if elem id vars
                      then writer (True,id)
                      else do tell "not a channel"
                              return False
      _         -> do tell "Not BindId"
                      return False

properBind :: Bind -> [Bind]
properBind (BindType t id) = [BindType t id]
properBind _               = []

checkAllArgs :: [Id] -> [Id] -> Bind -> Writer [String] Bool
checkAllArgs argss allArgs bind =
 case bind of
      BindId id -> if (elem id argss)
                   then checkArgs argss allArgs
                   else case runWriter (checkArgs argss allArgs) of
                             (b,zs) -> writer (False,zs)
      _         -> checkArgs argss allArgs


checkArgs :: [Id] -> [Id] -> Writer [String] Bool
checkArgs _ []              = return True
checkArgs argss (a:allArgs) =
 do b <- checkArgs argss allArgs
    let s = if not(elem a argss) then [a] else []
    writer ((elem a argss && b),s)

checkRetVar :: [Bind] -> [Id] -> Bool
checkRetVar xs ids = case length xs of
                          0 -> True
                          1 -> elem (getIdBind (head xs)) ids
                          _ -> False

getVarsWC :: Abs.WhereClause -> [Id]
getVarsWC Abs.WhereClauseNil      = []
getVarsWC (Abs.WhereClauseDef xs) = map (\ (Abs.WhereExp bind _) -> (getIdBind.getBind_) bind) xs

checkVarsInitialisation :: [Id] -> [Id] -> [Id]
checkVarsInitialisation [] _      = []
checkVarsInitialisation (x:xs) wc = if (elem x wc)
                                    then checkVarsInitialisation xs wc
                                    else x:checkVarsInitialisation xs wc

getCompTrigger :: Abs.CompoundTrigger -> Writer String CompoundTrigger
getCompTrigger ce =
 case ce of
     Abs.NormalEvent (Abs.BindingVar bind) id binds trv ->
        case runWriter (getBindsBody (map getVarsAbs binds)) of
             (bs, s) -> do let id'  = getIdAbs id
                           let trv' = getTriggerVariation trv
                           tell s
                           return (NormalEvent (BindingVar (getBind_ bind)) id' bs trv')
     Abs.ClockEvent id at int -> do let id' = getIdAbs id
                                    let at' = getTimeout at 
                                    return (ClockEvent id' at' int)
     Abs.OnlyId id         -> do let id' = getIdAbs id
                                 return (OnlyId id')
     Abs.OnlyIdPar id      -> do let id' = getIdAbs id
                                 return (OnlyIdPar id')

getCompTriggers :: Abs.CompoundTrigger -> Env -> Writer String CompoundTrigger
getCompTriggers (Abs.Collection (Abs.CECollection esl wc)) env = 
 do let xs = map (getCEElement env) esl
    let wc' = getWhereClause wc
    ce <- writer $ _2 %~ (addComma . filter (not.null)) $ unzip $ map runWriter xs
    return (Collection (CECollection ce wc'))
getCompTriggers ce _                                           = getCompTrigger ce

getCEElement :: Env -> Abs.CEElement -> Writer String CEElement
getCEElement env (Abs.CEct ct)    = 
 do ct' <- getCompTriggers ct env
    return (CEct ct')
getCEElement env (Abs.CEid id)   = 
 let id' = getIdAbs id
 in return (CEid id')
getCEElement env (Abs.CEidpar id) = 
 let id' = getIdAbs id
 in return (CEidpar id')

getTimeout :: Abs.Timeout -> Timeout
getTimeout Abs.At = At
getTimeout Abs.AtRep = AtRep

--Checks if the triggers in the collections are defined
checkCollectionTrPPD :: Triggers -> UpgradePPD ()
checkCollectionTrPPD trs = 
 do env <- get
    case runWriter (checkCollectionTr trs env) of
         (trs', s) -> if null s
                      then return ()
                      else fail s

checkCollectionTr :: Triggers -> Env -> Writer String [Trigger]
checkCollectionTr [] _         = return []
checkCollectionTr (tr:trs) env = 
 case tr ^. compTrigger of
      Collection (CECollection ces wc) 
                    -> do trs' <- checkCollectionTr trs env
                          case runWriter (checkTriggerCE tr env) of
                               (tr',s) -> do pass $ return ((), \s' -> s ++ s') 
                                             return (tr'++trs') 
      _             -> do trs' <- checkCollectionTr trs env
                          return (tr ^. tName:trs')

checkTriggerCE :: TriggerDef -> Env -> Writer String [Trigger]
checkTriggerCE tr env = 
 case (tr ^. compTrigger) of
      Collection (CECollection ces wc) -> do let xs = getTriggersInCE ces
                                             let ys = [y | y <- xs, not (elem y (map tiTN $ allTriggers env))]
                                             if (not.null) ys
                                             then writer (xs,"Error: In trigger collection " ++ tr ^. tName 
                                                             ++ ", the trigger(s) [" ++ addComma ys
                                                             ++ "] is(are) used, but not previously defined.\n")
                                             else return xs
      _                                -> return []

getTriggersInCE :: [CEElement] -> [Trigger]
getTriggersInCE []     = []
getTriggersInCE (x:xs) = getTriggerInCE x ++ getTriggersInCE xs

getTriggerInCE :: CEElement -> [Trigger]
getTriggerInCE (CEid id)    = [id]
getTriggerInCE (CEidpar id) = [id]
getTriggerInCE (CEct ct)    = getTriggerCompoundCE ct

getTriggerCompoundCE :: CompoundTrigger ->[Trigger]
getTriggerCompoundCE (Collection (CECollection ces wc)) = getTriggersInCE ces
getTriggerCompoundCE (OnlyIdPar id)                     = [id]
getTriggerCompoundCE (OnlyId id)                        = [id]
getTriggerCompoundCE _                                  = []
 

--Checks if the arguments in the triggers have the right form
getBindsArgs :: [Abs.Bind] -> Writer String [Bind]
getBindsArgs []     = return []
getBindsArgs (b:bs) =
 case runWriter (getBindsArgs bs) of
      (bs', s) -> case b of
                       Abs.BindType t id -> do tell s
                                               return ((BindType (getTypeAbs t) (getIdAbs id)):bs')
                       Abs.BindTypeExec t id -> do tell s
                                                   return ((BindTypeExec (getTypeAbs t) (getIdAbs id)):bs')
                       Abs.BindTypeCall t id -> do tell s
                                                   return ((BindTypeCall (getTypeAbs t) (getIdAbs id)):bs')
                       _                 -> do tell (mAppend (printTree b) s)
                                               return bs'

--Checks if the arguments in the method call on a trigger have the right form
getBindsBody :: [Abs.Bind] -> Writer String [Bind]
getBindsBody []     = return []
getBindsBody (b:bs) =
 case runWriter (getBindsBody bs) of
      (xs, s) -> case b of
                       Abs.BindId id -> do tell s
                                           return ((BindId (getIdAbs id)):xs)
                       Abs.BindStar  -> do tell s
                                           return (BindStar:xs)
                       _             -> do tell (mAppend (printTree b) s)
                                           return xs

getBind_ :: Abs.Bind -> Bind
getBind_ Abs.BindStar            = BindStar
getBind_ (Abs.BindType t id)     = BindType (getTypeAbs t) (getIdAbs id)
getBind_ (Abs.BindId id)         = BindId (getIdAbs id)
getBind_ Abs.BindStarExec        = BindStarExec
getBind_ Abs.BindStarCall        = BindStarCall
getBind_ (Abs.BindTypeExec t id) = BindTypeExec (getTypeAbs t) (getIdAbs id)
getBind_ (Abs.BindTypeCall t id) = BindTypeCall (getTypeAbs t) (getIdAbs id)
getBind_ (Abs.BindIdExec id)     = BindIdExec (getIdAbs id)
getBind_ (Abs.BindIdCall id)     = BindIdCall (getIdAbs id)


getTriggerVariation :: Abs.TriggerVariation -> TriggerVariation
getTriggerVariation Abs.EVEntry        = EVEntry
getTriggerVariation (Abs.EVExit vars)  = EVExit (map (getBind_.getVarsAbs) vars)
getTriggerVariation (Abs.EVThrow vars) = EVThrow (map (getBind_.getVarsAbs) vars)
getTriggerVariation (Abs.EVHadle vars) = EVHadle (map (getBind_.getVarsAbs) vars)

-- Removes white spaces added by printTree after ';'
getWhereClause :: Abs.WhereClause -> WhereClause
getWhereClause Abs.WhereClauseNil        = ""
getWhereClause (Abs.WhereClauseDef wexp) = (concat.lines.printTree) wexp

--
-- Properties --
--

getProperty :: Abs.Properties -> [Id] -> Env -> Scope -> Writer ([String],String,String,String) (Property,Env)
getProperty Abs.PropertiesNil _ env _                                               = return (PNIL,env)
getProperty (Abs.ProperiesDef id (Abs.PropKindPinit id' id'') props) enms env scope = 
 do (p,env') <- getProperty props enms env scope
    return (PINIT { piName  = getIdAbs id
                  , tmpId   = getIdAbs id'
                  , bounds  = getIdAbs id''
                  , piProps = p
                  }, env')
getProperty (Abs.ProperiesDef id (Abs.PropKindNormal states trans) props) enms env scope =
 case runWriter (getTransitions (getIdAbs id) trans env scope) of
      ((t,env'),s') ->
           do let ts = map (trigger.arrow) t
              (p,env'') <- getProperty props enms env' scope
              let xs      = [x | x <- ts, not (elem x enms)]
              let pname   = getIdAbs id
              let states' = getStates' states
              let s''     = execWriter $ checkStatesWF states' pname t
              let cns    = htsNames env
              let accep  = checkAllHTsExist (getAccepting states') cns pname scope
              let bad    = checkAllHTsExist (getBad states') cns pname scope
              let normal = checkAllHTsExist (getNormal states') cns pname scope
              let start  = checkAllHTsExist (getStarting states') cns pname scope
              let errs   = concat $ start ++ accep ++ bad ++ normal
              pass $ return ((), \s -> mkErrTuple s xs s' s'' errs)
              return (Property { pName        = pname
                               , pStates      = states'
                               , pTransitions = t
                               , pProps       = p },env'')

mkErrTuple :: ([String], String,String,String) -> [String] -> String -> String -> String -> ([String],String,String,String)
mkErrTuple s xs s' s'' s''' = (s ^. _1 ++ xs, s' ++ s ^. _2, s ^. _3 ++ s'', s ^. _4 ++ s''')

mAppend :: String -> String -> String
mAppend [] []         = ""
mAppend xs []         = xs
mAppend [] ys         = ys
mAppend (x:xs) (y:ys) = (x:xs) ++ "," ++ y:ys

getStates' :: Abs.States -> States
getStates' (Abs.States start accep bad norm) = States { getStarting = getStarting' start
                                                      , getAccepting = getAccepting' accep 
                                                      , getBad = getBad' bad
                                                      , getNormal = getNormal' norm
                                                      }

getAccepting' :: Abs.Accepting -> Accepting
getAccepting' Abs.AcceptingNil      = []
getAccepting' (Abs.AcceptingDef ss) = map getState ss

getBad' :: Abs.Bad -> Bad
getBad' Abs.BadNil      = []
getBad' (Abs.BadDef ss) = map getState ss

getNormal' :: Abs.Normal -> Normal
getNormal' Abs.NormalNil      = []
getNormal' (Abs.NormalDef ss) = map getState ss

getStarting' :: Abs.Starting -> Starting
getStarting' (Abs.StartingDef ss) = map getState ss

getState :: Abs.State -> State
getState (Abs.State (Abs.NameState id) ic Abs.CNSNil)    = State (getIdAbs id) (getInitCode ic) []
getState (Abs.State (Abs.NameState id) ic (Abs.CNS cns)) = State (getIdAbs id) (getInitCode ic) (map (getIdAbs.getConstNameAbs) cns)

getInitCode :: Abs.InitialCode -> InitialCode
getInitCode Abs.InitNil      = InitNil
getInitCode (Abs.InitProg p) = InitProg (getJava p)

--Check if the states are well-formed
checkStatesWF :: States -> PropertyName -> Transitions -> Writer String ()
checkStatesWF sts pn trans =
 do oneStarting sts pn
    stateTransE trans sts pn
    uniqueNamesStates sts pn

--Checks if there is one (and only one) starting state
oneStarting :: States -> PropertyName -> Writer String ()
oneStarting sts pn = 
 case length (getStarting sts) of
      0 -> tell ("Error: There is no starting state " ++ "in property " ++ pn ++ ".\n")
      1 -> return ()
      otherwise -> tell ("Error: There is more than one starting state " ++ "in property " ++ pn ++ ".\n")

--Checks if all the states used in the transitions exist
stateTransE :: Transitions -> States -> PropertyName -> Writer String ()
stateTransE trans sts pn = 
 let all  = map (^. getNS) $ allStates sts
     stsT = concatMap (\ t -> [fromState t,toState t]) trans
     xs   = [y | y <- stsT , not (elem y all)]
 in if null xs
    then return ()
    else tell (msg xs) 
               where msg xs = if length xs > 1
                              then "Error: In property " ++ pn 
                                   ++ ", the following state names used in the transitions do not exist: " 
                                   ++ show xs ++ ".\n"
                              else "Error: In property " ++ pn
                                   ++ ", the following state name used in the transitions do not exist: "
                                   ++ show xs ++ ".\n"

--Checks if the names of the states are unique.
uniqueNamesStates :: States -> PropertyName -> Writer String ()
uniqueNamesStates sts pn = 
 let all = uniqueNames $ allStates sts
 in if null all
    then return ()
    else tell (msg all) 
               where msg xs = if length xs > 1
                              then "Error: In property " ++ pn
                                   ++ ", the following state names are not unique: " ++ show xs ++ ".\n"
                              else "Error: In property " ++ pn
                                   ++ ", the following state name is not unique: " ++ show xs ++ ".\n"

allStates :: States -> [State]
allStates sts =
 let accp = getAccepting sts
     bad  = getBad sts
     norm = getNormal sts
     star = getStarting sts
 in star ++ accp ++ bad ++ norm

uniqueNames :: [State] -> [NameState]
uniqueNames sts = removeDuplicates $ map (^.getNS) $ sameNameStates sts

sameNameStates :: [State] -> [State]
sameNameStates []     = []
sameNameStates (x:xs) = getSameNameStates x xs ++ sameNameStates xs

getSameNameStates :: State -> [State] -> [State]
getSameNameStates st []     = []
getSameNameStates st (x:xs) = 
 if (stateEq st x)
 then x:getSameNameStates st xs
 else getSameNameStates st xs

stateEq :: State -> State -> Bool
stateEq st st' = st == st' || st ^. getNS == st' ^. getNS

getTransitions :: PropertyName -> Abs.Transitions -> Env -> Scope -> Writer String (Transitions,Env)
getTransitions id (Abs.Transitions ts) env scope = 
 do xs <- sequence $ map (getTransition' id env scope) ts
    let trans = map fst xs
    let envs  = map snd xs
    let env'  = joinEnvsCreate envs emptyEnv
    return (trans,env')

getTransition' :: PropertyName -> Env -> Scope -> Abs.Transition -> Writer String (Transition,Env)
getTransition' id env scope (Abs.Transition (Abs.NameState q1) (Abs.NameState q2) ar) = 
 case runWriter (getArrow ar env scope) of
      ((xs,env'),s) -> 
          do let err = "Error: Parsing error in an action of a transition from state " 
                        ++ getIdAbs q1 ++ " to state " 
                        ++ getIdAbs q2 ++ " in property " ++ id ++ ".\n"
             let s' = if null s then "" else err ++ s
             tell s'                  
             return (Transition { fromState = getIdAbs q1
                                , arrow = xs
                                , toState = getIdAbs q2
                                },env')

getArrow :: Abs.Arrow -> Env -> Scope -> Writer String (Arrow,Env)
getArrow (Abs.Arrow id mark Abs.Cond1) env scope        = 
 return $ (Arrow { trigger = getIdAbs id ++ addQuestionMark mark, cond = "", action = "" },env)
getArrow (Abs.Arrow id mark (Abs.Cond2 cond)) env scope = 
 case cond of
      Abs.CondExpDef cexp     -> return $ (Arrow { trigger = getIdAbs id ++ addQuestionMark mark, cond = printTree cexp, action = "" },env)
      Abs.CondAction cexp act -> 
        let act' = (trim.printTree) act in
        case ParAct.parse act' of 
             Bad s -> do tell s
                         return $ (Arrow { trigger = getIdAbs id ++ addQuestionMark mark, cond = printTree cexp, action = "Parse error" },env)
             Ok (Act.Actions ac) -> 
                      case runWriter $ sequence (map (\a -> checkTempInCreate a env) ac) of
                           (ac',s') -> do tell s'
                                          let ac'' = filter isCreateAct ac'
                                          let acts = [CAI y z "" x scope | (y,z,x) <- concatMap getIdAndArgs ac'']
                                          let env' = env { allCreateAct = acts ++ (allCreateAct env)}
                                          return $ (Arrow { trigger = getIdAbs id ++ addQuestionMark mark, cond = printTree cexp, action = act' },env')
      

isCreateAct :: Act.Action -> Bool
isCreateAct (Act.ActCreate _ _) = True
isCreateAct (Act.ActCond _ act) = isCreateAct act
isCreateAct (Act.ActBlock (Act.Actions acts)) = or $ map isCreateAct acts
isCreateAct _                   = False

getIdAndArgs :: Act.Action -> [(Id,[Act.Args],Act.Action)]
getIdAndArgs ac@(Act.ActCreate (Act.Temp (Act.IdAct id)) args) = [(id,args,ac)]
getIdAndArgs (Act.ActCond _ act)                               = getIdAndArgs act
getIdAndArgs (Act.ActBlock (Act.Actions acts))                 = concatMap getIdAndArgs acts
getIdAndArgs _                                                 = []

joinEnvsCreate :: [Env] -> Env -> Env
joinEnvsCreate [] env          = env
joinEnvsCreate (env:envs) env' = joinEnvsCreate envs (join env env')
                                      where join env env' = env { allCreateAct = (allCreateAct env) ++ (allCreateAct env')}


addQuestionMark :: Abs.Actmark -> String
addQuestionMark Abs.ActMarkNil  = ""
addQuestionMark Abs.ActMark     = "?"
            
checkTempInCreate :: Act.Action -> Env -> Writer String Act.Action
checkTempInCreate ac@(Act.ActCreate (Act.Temp (Act.IdAct id) ) _) env = 
 let tmpids = map fst $ tempsInfo env
 in if not (elem id tmpids)
    then do tell $ "Template " ++ id ++ ", which is used in an action create does not exist.\n"
            return ac
    else return ac
checkTempInCreate (Act.ActCond conds act) env = 
 case runWriter $ checkTempInCreate act env of
      (ac,s) -> do tell s
                   return $ Act.ActCond conds ac
checkTempInCreate (Act.ActBlock (Act.Actions acts)) env     = 
 case runWriter $ sequence $ map (\act -> checkTempInCreate act env) acts of
      (ac,s) -> do tell s
                   return $ Act.ActBlock (Act.Actions ac)
checkTempInCreate act env                     = return act

---------------
-- Foreaches --
---------------

getForeaches :: Abs.Foreaches -> Context -> Scope -> UpgradePPD Context
getForeaches Abs.ForeachesNil ctxt _ = 
 do env <- get    
    put env { actes = actes env ++ map show (ctxt ^. actevents)} 
    return ctxt
getForeaches (Abs.ForeachesDef _ (Abs.Ctxt _ _ _ _ (Abs.ForeachesDef args actxt fors)) afors) _ _ = 
 fail "Error: StaRVOOrS does not support nested Foreaches.\n"
getForeaches afors@(Abs.ForeachesDef _ (Abs.Ctxt _ _ _ _ Abs.ForeachesNil) _) ctxt scope = 
 let afors' = prepareForeaches afors
 in do env <- get
       put env { actes = actes env ++ map show (ctxt ^. actevents)}
       fors <- sequence $ map (uncurry getForeach) (zip afors' (createIds scope afors'))
       env' <- get
       return (foreaches .~ fors $ ctxt)

prepareForeaches :: Abs.Foreaches -> [Abs.Foreaches]
prepareForeaches Abs.ForeachesNil                  = []
prepareForeaches (Abs.ForeachesDef args ctxt fors) = 
 (Abs.ForeachesDef args ctxt Abs.ForeachesNil):prepareForeaches fors

createIds :: Scope -> [Abs.Foreaches] -> [ForId]
createIds TopLevel afors          = map (ForId . show) [1..length afors]
createIds (InFor (ForId s)) afors = 
 if s == "TopLevel" 
 then [ForId s]
 else map (ForId . (s++) . show) [1..length afors]

getForeach :: Abs.Foreaches -> ForId -> UpgradePPD Foreach
getForeach (Abs.ForeachesDef args ctxt Abs.ForeachesNil) id = 
 do ctxt' <- getCtxt ctxt (InFor id)
    env <- get    
    case ctxt' ^. foreaches of
      [] -> do let args'     = map getArgs args
               let propn     = pName $ ctxt' ^. property
               let Args t cl = head $ args'               
               put env { propInForeach = (propn,t,cl):propInForeach env }               
               return $ Foreach args' ctxt' id
      _  -> fail $ "Error: StaRVOOrS does not support nested Foreaches.\n"


---------------
-- Templates --
---------------

getTemplate :: Templates -> Id -> Template  
getTemplate (Temp tmps) id = getTemplate' tmps id

getTemplate' :: [Template] -> Id -> Template
getTemplate' [x] _     = x
getTemplate' (x:xs) id = if (x ^. tempId) == id then x else getTemplate' xs id

genTemplates :: Abs.Templates -> UpgradePPD Templates
genTemplates Abs.TempsNil   = return TempNil
genTemplates (Abs.Temps xs) = 
 do xs <- sequence $ map genTemplate xs
    env <- get
    put env { tempsInfo = tempsInfo env ++ foldr (\ x xs -> (x ^. tempId, x ^. tempBinds) : xs) [] xs}
    return $ Temp xs 


genTemplate :: Abs.Template -> UpgradePPD Template
genTemplate (Abs.Temp id args (Abs.Body vars ies trs prop)) = 
 do args' <- hasReferenceType (map ((uncurry makeArgs).getArgsAbs) args) (getIdAbs id)
    trigs' <- getTriggers trs (InTemp (getIdAbs id)) args'
    env <- get
    let prop' = getProperty prop (map (^. tName) trigs') env (InTemp (getIdAbs id))
    let extrs = getExitTrsInfo trigs'
    case runWriter prop' of
         ((PNIL,env'),_)                      -> fail $ "Error: The template " ++ getIdAbs id 
                                                        ++ " does not have a PROPERTY section.\n"
         ((PINIT pname id' xs props,env'),s)  -> 
                  let temptrs = s ^. _1
                      s'      = s ^. _2 ++ s ^. _3
                                ++ if props /= PNIL 
                                   then "Error: In template " ++ getIdAbs id 
                                        ++ ", a template should describe only one property.\n"
                                   else "" 
                  in if ((not.null) s')
                     then fail s'
                     else do put env' { actes = actes env' ++ map show (getActEvents ies)}
                             return $ Template { _tempId        = getIdAbs id
                                               , _tempBinds     = args'
                                               , _tempVars      = getValue $ getVars vars
                                               , _tempActEvents = getActEvents ies
                                               , _tempTriggers  = trigs'
                                               , _tempProp      = PINIT pname id' xs props
                                               }
         ((Property pname states trans props, env'), s) -> 
                  let s'      = s ^. _2 ++ s ^. _4 ++ s ^. _3
                                ++ if props /= PNIL 
                                   then "Error: In template " ++ getIdAbs id 
                                        ++ ", it should describe only one property.\n"
                                   else ""
                      temptrs = s ^. _1
                  in if ((not.null) s')
                     then fail s'
                     else do put env' { actes = actes env' ++ map show (getActEvents ies)}
                             return $ Template { _tempId        = getIdAbs id
                                               , _tempBinds     = args'
                                               , _tempVars      = getValue $ getVars vars
                                               , _tempActEvents = getActEvents ies
                                               , _tempTriggers  = trigs'
                                               , _tempProp      = Property pname states trans props
                                               }

getExitTrsInfo :: Triggers -> [(ClassInfo,MethodName)]
getExitTrsInfo [] = []
getExitTrsInfo ((TriggerDef tr args (NormalEvent (BindingVar (BindId id)) id' _ (EVExit _)) _):ts) = 
 case runStateT (getClassVarArgs args id) emptyEnv of
      Bad s    -> error $ "Error: In trigger " ++ tr ++ ", " ++ s
      Ok (t,_) -> (t,id'):getExitTrsInfo ts
getExitTrsInfo ((TriggerDef tr args (NormalEvent (BindingVar (BindIdExec id)) id' _ (EVExit _)) _):ts) = 
 case runStateT (getClassVarArgs args id) emptyEnv of
      Bad s    -> error $ "Error: In trigger " ++ tr ++ ", " ++ s
      Ok (t,_) -> (t,id'):getExitTrsInfo ts
getExitTrsInfo ((TriggerDef tr args (NormalEvent (BindingVar (BindIdCall id)) id' _ (EVExit _)) _):ts) = 
 case runStateT (getClassVarArgs args id) emptyEnv of
      Bad s    -> error $ "Error: In trigger " ++ tr ++ ", " ++ s
      Ok (t,_) -> (t,id'):getExitTrsInfo ts
getExitTrsInfo ((TriggerDef _ _ (NormalEvent (BindingVar (BindType t _)) id _ (EVExit _)) _):ts) = 
 (t,id):getExitTrsInfo ts
getExitTrsInfo ((TriggerDef _ _ (NormalEvent (BindingVar (BindTypeCall t _)) id _ (EVExit _)) _):ts) = 
 (t,id):getExitTrsInfo ts
getExitTrsInfo ((TriggerDef _ _ (NormalEvent (BindingVar (BindTypeExec t _)) id _ (EVExit _)) _):ts) = 
 (t,id):getExitTrsInfo ts
getExitTrsInfo (_:ts) = getExitTrsInfo ts


getClassVarArgs :: [Bind] -> Id -> UpgradePPD ClassInfo
getClassVarArgs [] id                    = fail $ id ++ " is not associated to any argument.\n" 
getClassVarArgs (BindType t id':args) id = 
 if id == id'
 then return t
 else getClassVarArgs args id
getClassVarArgs (_:args) id              = getClassVarArgs args id


--Check for the arguments used in the create actions
wellFormedActions :: UpgradePPD PPDATE -> String
wellFormedActions ppd = 
 let env = getEnvVal ppd in
 case runWriter $ sequence $ map (wellFormedAction env) (allCreateAct env) of
      (b,s) -> if and b
               then ""
               else s 

wellFormedAction:: Env -> CreateActInfo -> Writer String Bool
wellFormedAction env cai = 
 let xs = [ tmp | tmp <- tempsInfo env, fst tmp == (cai ^. caiId)]
 in if null xs
    then writer (False, "Error: In an action create, the template " ++ cai ^. caiId ++ " does not exist.\n")
    else let tempArgs = snd $ head $ xs
             ys       = splitTempArgs (zip tempArgs (cai ^. caiArgs)) emptyTargs
         in if length tempArgs /= length (cai ^. caiArgs)
            then writer (False, "Error: In an action create, the amount of arguments does not match the arguments in template "
                                ++ cai ^. caiId ++ ".\n")
            else case runWriter $ checkTempArgs ys env (cai ^. caiScope) of
                      (xs,s) -> if and xs
                                then return True
                                else writer (False,s)

splitTempArgs :: [(Args,Act.Args)] -> TempArgs -> TempArgs
splitTempArgs [] targs         = targs
splitTempArgs (arg:args) targs = 
 case getArgsType (fst arg) of
      "Action"     -> splitTempArgs args (targs {targAct = arg : targAct targs})
      "Condition"  -> splitTempArgs args (targs {targCond = arg : targCond targs})
      "Trigger"    -> splitTempArgs args (targs {targTr = arg : targTr targs})
      "MethodName" -> splitTempArgs args (targs {targMN = arg : targMN targs})
      "HTriple"    -> splitTempArgs args (targs {targHT = arg : targHT targs})
      _            -> splitTempArgs args (targs {targRef = arg : targRef targs})

checkTempArgs :: TempArgs -> Env -> Scope -> Writer String [Bool]
checkTempArgs targs env scope = 
 sequence [ checkTempArgsActions (map snd $ targAct targs)
          , checkTempArgsHTriples (map snd $ targHT targs) (htsNames env)
          , checkTempArgsConditions (map snd $ targCond targs)
          , checkTempArgsTriggers (map snd $ targTr targs) (allTriggers env) scope
          , checkMethodNames (map snd $ targMN targs) (javaFilesInfo env)
          ]

checkTempArgsActions :: [Act.Args] -> Writer String Bool
checkTempArgsActions []    = return True
checkTempArgsActions targs = 
 let (xs,ys) = partitionErr $ map (ParAct.parse . (\xs -> xs ++ ";") . showActArgs) targs
 in if null xs 
    then return True
    else writer (False, "Error: In an action create: " ++ (unlines $ map fromBad xs))

checkTempArgsHTriples :: [Act.Args] -> [HTName] -> Writer String Bool
checkTempArgsHTriples [] _      = return True
checkTempArgsHTriples targs hts = 
 let xs = [ h | h <- map showActArgs targs, not (elem h hts)]
 in if null xs
    then return True 
    else writer (False, "Error: In an action create, the Hoare triple(s) [" ++ addComma xs ++ "] do(es) not exist.\n")

showActArgs :: Act.Args -> String
showActArgs (Act.ArgsId (Act.IdAct id))                        = id
showActArgs (Act.ArgsS s)                                      = s
showActArgs (Act.ArgsNew (Act.Prog (Act.IdAct id) args inner)) = "new " ++ id ++ PrintAct.printTree args ++ PrintAct.printTree inner
showActArgs act                                                = PrintAct.printTree act

checkTempArgsConditions :: [Act.Args] -> Writer String Bool 
checkTempArgsConditions targs = 
 let (xs,ys) = partitionErr $ map (ParJML.parse . showActArgs) targs
 in if null xs 
    then return True
    else writer (False, "Error: In an action create, syntax error(s) on the condition(s) [" ++ addComma (map fromBad xs) ++ "].\n")

checkTempArgsTriggers :: [Act.Args] -> [TriggersInfo] -> Scope -> Writer String Bool
checkTempArgsTriggers targs tinfs scope = 
 let xs = [ tr | tr <- map showActArgs targs, tinf <- tinfs, tiScope tinf == scope, tiTN tinf == tr]
 in if length xs == length targs
    then return True 
    else writer (False, "Error: In an action create, the trigger(s) [" ++ addComma xs ++ "] do(es) not exist.\n") 

checkMethodNames :: [Act.Args] -> [(String, ClassInfo, JavaFilesInfo)] -> Writer String Bool
checkMethodNames targs minfs =
 let xs = removeDuplicates [ mn | mn <- map showActArgs targs, xs <- minfs, mn' <- methodsInFiles (xs ^. _3), mn == (mn' ^. _2) ]
 in if length xs == length targs
    then return True 
    else writer (False, "Error: In an action create, the method(s) [" 
                        ++ addComma [ x | x <- map showActArgs targs, not (elem x xs)] ++ "] do(es) not exist.\n") 

hasReferenceType :: [Args] -> String -> UpgradePPD [Args]
hasReferenceType xs id = 
 case filterReferenceTypes xs of
      [] -> fail $ "Error: The template " ++ id ++ " does not have any reference type as argument.\n"
      _  -> return xs

filterReferenceTypes :: [Args] -> [Args]
filterReferenceTypes []         = []
filterReferenceTypes (arg:args) = 
 case getArgsType arg of
      "Action"     -> filterReferenceTypes args
      "Condition"  -> filterReferenceTypes args
      "Trigger"    -> filterReferenceTypes args
      "MethodName" -> filterReferenceTypes args
      "HTriple"    -> filterReferenceTypes args
      xs           -> if elem xs primitiveJavaTypes
                      then filterRefTypes args
                      else arg:filterRefTypes args

-----------------
-- CInvariants --
-----------------

genClassInvariants :: Abs.CInvariants -> UpgradePPD CInvariants
genClassInvariants absinvs =
 case runWriter (genClassInvariants' absinvs) of
      (cinvs,s) -> if null s
                   then return cinvs
                   else fail s

genClassInvariants' :: Abs.CInvariants -> Writer String CInvariants
genClassInvariants' Abs.CInvempty           = return []
genClassInvariants' (Abs.CInvariants cinvs) = sequence $ map getCInv cinvs

getCInv :: Abs.CInvariant -> Writer String CInvariant
getCInv (Abs.CI cn jml) = 
 case runWriter (getJML jml "") of
      (jml',s) -> if null s 
                  then return $ CI (getIdAbs cn) jml'
                  else do tell $ "Error: Parse on error on class invariant [" ++ printTree jml ++ "] for the class " ++ getIdAbs cn ++ ".\n"
                          return CInvNil

-------------------
-- Hoare Triples --
-------------------

genHTs :: Abs.HTriples -> Imports -> Writer String HTriples
genHTs Abs.HTempty _          = return []
genHTs (Abs.HTriples cs) imps = checkOverl $ sequence $ map (getHT imps) cs

getHT :: Imports -> Abs.HT -> Writer String HT
getHT imps (Abs.HT id pre' method post' ass) =
 do let mcn = MCN { _clinf = getMethodClassInfo method
                  , _mname = getMethodMethodName method
                  , _overl = getMethodOverloading method }
    case checkImports (mcn ^. clinf) imps of
         []    -> do tell $ "Error: Hoare triple " ++ getIdAbs id ++ " is associated to class the " 
                            ++ mcn ^. clinf ++ ", but it is not imported.\n"
                     let ys  = map checkJML $ [getPre pre',getPost post'] ++ checkAssig ass
                     case runWriter (joinErrorJML' ys (getIdAbs id)) of
                         (_,s) -> if not (null s)
                                  then do tell s 
                                          return (HT { _htName     = getIdAbs id
                                                     , _methodCN   = mcn
                                                     , _pre        = ""
                                                     , _post       = ""
                                                     , _assignable = ""
                                                     , _newPRe     = []
                                                     , _chGet      = 0
                                                     , _path2it    = ""
                                                     , _varThis    = ("","")
                                                     })
                                  else return (HT { _htName       = getIdAbs id
                                                  , _methodCN     = mcn
                                                  , _pre          = genPre pre'
                                                  , _post         = genPost post'
                                                  , _assignable   = genAssig ass
                                                  , _newPRe       = []
                                                  , _chGet        = 0
                                                  , _path2it      = ""
                                                  , _varThis      = ("","")
                                                  })
         (x:_) -> do let ys  = map checkJML $ [getPre pre',getPost post'] ++ checkAssig ass
                     case runWriter (joinErrorJML' ys (getIdAbs id)) of
                          (_,s) -> if not (null s)
                                   then do tell s 
                                           return (HT { _htName     = getIdAbs id
                                                      , _methodCN   = mcn
                                                      , _pre        = ""
                                                      , _post       = ""
                                                      , _assignable = ""
                                                      , _newPRe     = []
                                                      , _chGet      = 0
                                                      , _path2it    = ""
                                                      , _varThis    = ("","")
                                                      })
                                   else return (HT { _htName       = getIdAbs id
                                                   , _methodCN     = mcn
                                                   , _pre          = genPre pre'
                                                   , _post         = genPost post'
                                                   , _assignable   = genAssig ass
                                                   , _newPRe       = []
                                                   , _chGet        = 0
                                                   , _path2it      = ""
                                                   , _varThis      = ("","")
                                                   })

genPre :: Abs.Pre -> Pre
genPre Abs.PreNil = "true"
genPre pre        = filter (/='\n') $ getJMLExp $ getPre pre

genPost :: Abs.Post -> Post
genPost Abs.PostNil = "true"
genPost post        = filter (/='\n') $ getJMLExp $ getPost post

genAssig :: Abs.Assignable -> Assignable
genAssig Abs.AssigNil         = "\\everything"
genAssig (Abs.Assignable ass) = joinAssignable $ map (getJMLExp.assig) ass

checkJML :: Writer String JMLExp -> Either JMLExp String
checkJML wjml =
 case runWriter wjml of
      (jml', s) -> if null s
                   then Left jml'
                   else Right s

getJMLExp :: Writer String JMLExp -> JMLExp
getJMLExp wjml = 
 case runWriter wjml of
      (jml', s) -> jml'
                   
joinErrorJML :: [Either JMLExp String] -> String -> UpgradePPD ()
joinErrorJML xs str = 
 do let ys = rights xs 
    if null ys 
    then return ()
    else fail $ concatMap (\s -> s ++ " of Hoare triple " ++ str ++ ".\n") ys 

joinErrorJML' :: [Either JMLExp String] -> String -> Writer String ()
joinErrorJML' xs str = 
 do let ys = rights xs 
    if null ys 
    then return ()
    else writer ((),concatMap (\s -> s ++ " of Hoare triple " ++ str ++ ".\n") ys)

checkAssig :: Abs.Assignable -> [Writer String JMLExp]
checkAssig Abs.AssigNil         = [return "\\everything"]
checkAssig (Abs.Assignable ass) = map assig ass

assig :: Abs.Assig -> Writer String JMLExp
assig (Abs.AssigJML jml) = return $ printTree jml
assig Abs.AssigE         = return "\\everything"
assig Abs.AssigN         = return "\\nothing"

joinAssignable [x]    = x
joinAssignable (x:xs) = x ++ "," ++ joinAssignable xs

checkImports :: ClassInfo -> Imports -> Imports
checkImports _ []             = []
checkImports cn (Import s:xs) = 
 let ys = splitOnIdentifier "." s
 in if (trim $ last ys) == cn
    then (Import s):checkImports cn xs
    else checkImports cn xs

checkOverl :: Writer String HTriples -> Writer String HTriples
checkOverl hts = 
 case runWriter hts of      
      (hts',s) -> let ys  = zip (map (^. htName) hts') (map _methodCN hts')
                      ys' = [(htn,mnc') | (htn,mnc') <- ys, (mnc' ^. overl) /= OverNil]
                  in if null ys'
                     then hts
                     else case runWriter $ sequence $ map (checkOV ys') [p | p <- ys, not (elem p ys')] of
                               (b,s') -> if and b
                                         then hts
                                         else writer (hts', s' ++ s)


checkOV :: [(HTName,MethodCN)] -> (HTName,MethodCN) -> Writer String Bool
checkOV xs (htn,mnc) =
 let ys = [ mnc' | (_,mnc') <- xs, (mnc ^. mname) == (mnc' ^. mname), (mnc ^. clinf) == (mnc' ^. clinf)]
 in if null ys
    then return True
    else do tell $ "Error: Type missing for the method " ++ mnc ^. mname ++ " of the class "
                   ++ mnc ^. clinf ++ " in the Hoare triple " ++ htn ++ ".\n"
            return False
    

-------------
-- Methods --
-------------

genMethods :: Abs.Methods -> Methods
genMethods m = printTree m

--------------------
-- PINIT property --
--------------------

replacePInit :: UpgradePPD PPDATE -> UpgradePPD PPDATE
replacePInit ppd = 
 let env    = getEnvVal ppd
     ppdate = getValue ppd
     ctxt   = ppdate ^. (globalGet . ctxtGet)
 in if or $ map checkPInitForeach $ ctxt ^. foreaches 
    then fail "Error: It is not possible to define a PINIT property within a FOREACH.\n"
    else case getPInit (ctxt ^. property) of
              (p:ps) ->  
                  let templates = ppdate ^. templatesGet
                      prop'     = removePInit (ctxt ^. property)
                      tmpFors   = map (\pi -> pinit2foreach pi templates) (p:ps)
                      fors'     = tmpFors ++ (ctxt ^. foreaches)
                      ctxt'     = ctxt & property .~ prop' & foreaches .~ fors'
                      ppdate'   = (globalGet . ctxtGet) .~ ctxt' $ ppdate
                      propns    = map piName (p:ps)
                      pif       = map (\(x,Args t cl) -> (x,t,cl)) $ zip propns (map (head.(^. getArgsForeach)) tmpFors)
                  in do put env { propInForeach = pif ++ propInForeach env  }
                        return ppdate'
              []     -> ppd

getPInit :: Property -> [Property]
getPInit PNIL                        = []
getPInit (PINIT id temp bound props) = (PINIT id temp bound PNIL):getPInit props
getPInit (Property _ _ _ props)      = getPInit props

removePInit :: Property -> Property
removePInit PNIL                         = PNIL
removePInit (PINIT _ _ _ props)          = removePInit props
removePInit (Property name st trs props) = Property name st trs (removePInit props)

checkPInitForeach :: Foreach -> Bool
checkPInitForeach foreach = 
 (not.null) $ getPInit $ foreach ^. (getCtxtForeach . property)

pinit2foreach :: Property -> Templates -> Foreach
pinit2foreach (PINIT id tempid bound PNIL) templates = 
 let temp = getTemplate templates tempid
     args = temp ^. tempBinds
     ctxt = Ctxt (temp ^. tempVars) (temp ^. tempActEvents) (temp ^. tempTriggers) (temp ^. tempProp) []
 in Foreach args ctxt (ForId "pinit")

------------------------
-- Selector functions --
------------------------

getArgs :: Abs.Args -> Args
getArgs (Abs.Args t id) = Args (getTypeAbs t) (getIdAbs id)

getArgsAbs :: Abs.Args -> (Type,Id)
getArgsAbs (Abs.Args t id) = (getTypeAbs t, getIdAbs id)

getSymbolsAbs :: Abs.Symbols -> String
getSymbolsAbs (Abs.Symbols s) = s

getIdAbs :: Abs.Id -> String
getIdAbs (Abs.Id s) = s

getTypeAbs :: Abs.Type -> String
getTypeAbs (Abs.Type (Abs.TypeDef (Abs.Id id))) = id
getTypeAbs (Abs.Type (Abs.TypeGen (Abs.Id id) (Abs.Symbols s1) xs (Abs.Symbols s2))) = id ++ s1 ++ addComma (map getIdAbs xs) ++ s2
getTypeAbs (Abs.Type (Abs.TypeArray (Abs.Id id))) = id

getJFAbs :: Abs.JavaFiles -> Abs.Id
getJFAbs (Abs.JavaFiles id) = id

getImportAbs :: Abs.Import -> [Abs.JavaFiles]
getImportAbs (Abs.Import jfs) = jfs

getVarInitAbs :: Abs.VariableInitializer -> VariableInitializer
getVarInitAbs Abs.VarInitNil     = VarInitNil
getVarInitAbs (Abs.VarInit vexp) = VarInit (printTree vexp)

getVarsAbs :: Abs.Vars -> Abs.Bind
getVarsAbs (Abs.Vars bind) = bind

getConstNameAbs :: Abs.HTName -> Abs.Id
getConstNameAbs (Abs.CN id) = id

getJML :: Abs.JML -> String -> Writer String JMLExp
getJML jml str = 
 let jml' = printTree jml in
 case ParJML.parse jml' of
      Bad s -> do tell $ "Error: Parse error on the " ++ str
                  return "Error: Parse error "
      Ok _  -> return jml' 

getJava :: Abs.Java -> Java
getJava java = printTree java

getMethodClassInfo :: Abs.Method -> ClassInfo
getMethodClassInfo (Abs.Method ci _ _) = getIdAbs ci

getMethodMethodName :: Abs.Method -> MethodName
getMethodMethodName (Abs.Method _ mn _) = getIdAbs mn

getMethodOverloading :: Abs.Method -> Overriding
getMethodOverloading (Abs.Method _ _ over) = getOverloading over

getOverloading :: Abs.Overriding -> Overriding 
getOverloading Abs.OverNil = OverNil
getOverloading (Abs.Over xs) = Over $ map getTypeAbs xs

getPre :: Abs.Pre -> Writer String JMLExp
getPre Abs.PreNil    = return "true"
getPre (Abs.Pre pre) = getJML pre "precondition"

getPost :: Abs.Post -> Writer String JMLExp
getPost Abs.PostNil     = return "true"
getPost (Abs.Post post) = getJML post "postcondition"

-------------------------
-- Auxiliary functions --
-------------------------

checkAllHTsExist :: [State] -> [HTName] -> PropertyName -> Scope -> [String]
checkAllHTsExist [] _ _ _            = []
checkAllHTsExist (s:ss) cns pn scope = 
 let ns   = s ^. getNS
     cns' = s ^. getCNList
     aux  = [x | x <- cns' , not (elem x cns)]
 in if (null aux || (tempScope scope))
    then checkAllHTsExist ss cns pn scope
    else ("Error: On property " ++ pn
         ++ ", in state " ++ ns ++ ", the Hoare triple(s) ["
         ++ addComma aux
         ++ "] do(es) not exist.\n") : checkAllHTsExist ss cns pn scope

duplicateHT :: [HTName] -> String
duplicateHT []     = ""
duplicateHT (c:cs) = "Error: In section HTRIPLES, multiple definitions for Hoare triple " ++ c ++ ".\n" ++ duplicateHT cs

getDuplicate :: [HTName] -> [HTName]
getDuplicate []     = []
getDuplicate (c:cs) = if elem c cs
                      then c:getDuplicate cs
                      else getDuplicate cs

-- Imports are considered to be separated by '.'
joinImport :: [String] -> String
joinImport []     = ""
joinImport [ys]   = ys
joinImport (xs:ys:iss) = xs ++ "." ++ joinImport (ys:iss)


lookForAllEntryTriggerArgs :: Env -> HT -> Maybe Scope -> UpgradePPD (String, String)
lookForAllEntryTriggerArgs env c scope =
 do let trs = allTriggers env
    tinfo <- getEntryTriggers (_methodCN c) trs scope
    let args  = map (\(BindType t id) -> Args t id) (tiBinds tinfo)
    return (getArgsGenMethods (tiCI tinfo,tiCVar tinfo, args))   

getEntryTriggers :: MethodCN -> [TriggersInfo] -> Maybe Scope -> UpgradePPD TriggersInfo
getEntryTriggers mnc [] _             = fail $ "Error: Could not find an entry trigger associated to method "
                                               ++ mnc ^. mname ++ show (mnc ^. overl) 
                                               ++ " of the class " ++ mnc ^. clinf ++ ".\n"
getEntryTriggers mnc (tinfo:ts) (Just scope) =
 if (mnc ^. mname) == (tiMN tinfo) && (mnc ^. clinf) == (tiCI tinfo) 
    && (cmpOverloading (mnc ^. overl) (tiOver tinfo))
    && tiTrvar tinfo == EVEntry
    && cmpScope scope (tiScope tinfo)
 then return tinfo
 else getEntryTriggers mnc ts (Just scope)
getEntryTriggers mnc (tinfo:ts) Nothing =
 if (mnc ^. mname) == (tiMN tinfo) && (mnc ^. clinf) == (tiCI tinfo) 
    && (cmpOverloading (mnc ^. overl) (tiOver tinfo))
    && tiTrvar tinfo == EVEntry
 then return tinfo
 else getEntryTriggers mnc ts Nothing


lookForAllExitTriggerArgs :: Env -> HT -> UpgradePPD (String, String)
lookForAllExitTriggerArgs env c =
 let tr    = getTriggerDef (_methodCN c ^. overl) c (allTriggers env)
     tinfo = head [ t | t <- allTriggers env , Just tr == tiTrDef t]
     args  = map (\(BindType t id) -> Args t id) (tiBinds tinfo)
 in return (getArgsGenMethods (tiCI tinfo, tiCVar tinfo, args))

getArgsGenMethods :: (ClassInfo, String, [Args]) -> (String,String)
getArgsGenMethods (ci, cvar, args) = 
 let varClass' = ci ++ " " ++ cvar
     argswt    = map getArgsId args
     argswt'   = addComma argswt
     argswt''  = if (elem cvar argswt) 
                 then argswt'
                 else if null argswt' then cvar else cvar ++ "," ++ argswt'
     flatArgs  = flattenArgs args
     args'     = if (elem cvar argswt)
                 then flatArgs
                 else if (null flatArgs)
                      then trim varClass'
                      else (trim varClass') ++ if null args then "" else "," ++ flattenArgs args
 in (args', argswt'')

getAllTriggers :: Global -> Env -> Triggers
getAllTriggers (Global (Ctxt vars ies trigs prop fors)) env = 
 let trs = trigs ++ getTriggersFors fors 
 in trs ++ [ fromJust (tiTrDef t) | t <- allTriggers env, tiTrDef t /= Nothing, not (elem (fromJust $ tiTrDef t) trs)]


----------------------------------------------
-- Environment with ppDATE spec information --
----------------------------------------------

data Env = Env
 { allTriggers     :: [TriggersInfo]
 , htsNames        :: [HTName]
 , javaFilesInfo   :: [(JPath, ClassInfo, JavaFilesInfo)]
 , varsInPPD       :: Variables                    
 , oldExpTypes     :: OldExprM --types of the old expressions
 , tempsInfo       :: [(Id,[Args])]--[(name_template, args_of_template)]
 , propInForeach   :: [(PropertyName, ClassInfo, String)]-- is used to avoid ambigous reference to variable id in foreaches
 , actes           :: [Id] --list of all defined action events
 , allCreateAct    :: [CreateActInfo]--list of all actions \create used in the transitions of the ppDATE
 }
  deriving (Show)

type UpgradePPD a = CM.StateT Env Err a

emptyEnv :: Env
emptyEnv = Env { allTriggers     = []
               , htsNames        = []
               , javaFilesInfo   = []
               , varsInPPD       = []
               , oldExpTypes     = Map.empty
               , tempsInfo       = []
               , propInForeach   = []
               , actes           = []
               , allCreateAct    = []
               }

getClassVarName :: Trigger -> MethodName -> [Bind] -> Bind -> String -> Scope -> [Args] -> UpgradePPD (ClassInfo,String)
getClassVarName _ _ args BindStar _ _ _                     = return ("*","")
getClassVarName _ _ args BindStarExec _ _ _                 = return ("*","")
getClassVarName _ _ args BindStarCall _ _ _                 = return ("*","")
getClassVarName _ _ args (BindType t id) _ _ _              = return (t,id)
getClassVarName _ _ args (BindTypeExec t id) _ _ _          = return (t,id)
getClassVarName _ _ args (BindTypeCall t id) _ _ _          = return (t,id)
getClassVarName tr mn args bindid s scope argsTemp = 
 let id  = getIdBind bindid 
     ts' = [getBindType arg | arg <- args, getIdBind arg == id ]
     ts  = if (null ts') then prepareValUpd mn s id s else ts'
 in if (length ts /= 1)
    then if tempScope scope
         then let xs = [ getArgsType arg | arg <- argsTemp, getArgsId arg == id]
              in if null xs 
                 then return ("",id)
                 else return (head xs,id)
         else fail $ "The trigger " ++ tr ++ " does not include a class variable declaration.\n" 
    else return (head ts,id)
 
prepareValUpd :: MethodName -> String -> String -> String -> [String]
prepareValUpd mn s id chan = 
 if mn == "new"
 then [id]
 else if null s
      then []
      else [chan]

updateInfo :: Map.Map MethodName [(Id, String, [Args],Scope)] -> MethodName -> (Id, String, [Args],Scope) -> Map.Map MethodName [(Id, String, [Args],Scope)]
updateInfo m mn einfo = 
 case Map.lookup mn m of
      Nothing -> Map.insert mn [einfo] m
      Just xs -> Map.insert mn (einfo:xs) m


----------------------------
-- Monad State operations --
----------------------------

get = CM.get
put = CM.put
runStateT = CM.runStateT

getValue :: UpgradePPD a -> a
getValue uppd = fst . fromOK $ runStateT uppd emptyEnv

getEnvVal :: UpgradePPD a -> Env
getEnvVal uppd = snd . fromOK $ runStateT uppd emptyEnv

getHTNamesEnv :: UpgradePPD a -> [HTName]
getHTNamesEnv ppd = let env = CM.execStateT ppd emptyEnv
                    in case env of
                            Bad _ -> []
                            Ok fs -> htsNames fs

