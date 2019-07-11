module Translators.Translator2DATE(translate) where

import Types
import CommonFunctions
import ReplicatedAutomataGenerator
import RefinementPPDATE
import UpgradePPDATE hiding(getTrigger)
import ErrM
import qualified Data.Map as Map
import Data.Maybe
import Data.List
import qualified ParserActions.AbsActions as Act
import qualified JML.AbsJml as Jml
import qualified ParserActions.ParserAct as ParAct
import qualified JML.ParserJML as ParJML
import qualified ParserActions.PrintActions as PrintAct
import qualified JML.PrintJml as PrintJML
import Translators.TranslatorActions
import Optimisations.Optimisations
import Control.Lens hiding(Context,pre)


translate :: UpgradePPD PPDATE -> FilePath -> IO ()
translate ppd fpath =
 do let (ppdate, env) = (\(Ok x) -> x) $ runStateT ppd emptyEnv
    putStrLn "Translating ppDATE to DATE."
    writeFile fpath (writeImports (ppdate ^. importsGet) (ppdate ^. htsGet))
    let consts  = assocChannel2HTs 1 $ (ppdate ^. htsGet)
    let ppdate' = htsGet .~ consts $ ppdate
    appendFile fpath (writeGlobal ppdate' env)
    appendFile fpath (writeMethods (ppdate' ^. methodsGet))
    putStrLn $ "Translation completed."


assocChannel2HTs :: Int -> HTriples -> HTriples
assocChannel2HTs _ []     = []
assocChannel2HTs n (c:cs) = (chGet .~ n $ c):assocChannel2HTs (n+1) cs

---------------------
-- IMPORTS section --
---------------------

writeImports :: Imports -> HTriples -> String
writeImports xss const = let newImp = "import ppArtifacts.*;\n"
                         in "IMPORTS {\n" ++ getImports xss ++ newImp  ++ "}\n\n"

--------------------
-- GLOBAL section --
--------------------

writeGlobal :: PPDATE -> Env -> String
writeGlobal ppdate env = 
 let acts   = actes env
     consts = ppdate ^. htsGet
     temps  = ppdate ^. templatesGet
     vars   = ppdate ^. (globalGet . ctxtGet . variables)
     trs    = ppdate ^. (globalGet . ctxtGet . triggers)
     prop   = ppdate ^. (globalGet . ctxtGet . property)
     fors   = ppdate ^. (globalGet . ctxtGet . foreaches)
 in "GLOBAL {\n\n" 
    ++ writeVariables vars consts acts (allCreateAct env)
    ++ writeTriggers trs consts acts env
    ++ writeProperties prop consts env TopLevel
    ++ writeForeach fors consts env
    ++ generateReplicatedAutomata consts trs env  
    ++ writeTemplates temps env consts
    ++ "}\n" 
 
---------------
-- Variables --
---------------

writeVariables :: Variables -> HTriples -> [Id] -> [CreateActInfo] -> String
writeVariables vars [] [] [] = 
 if null vars
 then ""
 else "VARIABLES {\n" ++ writeVariables' vars ++ "}\n\n"
writeVariables vars consts acts creates = 
 let actChann    = if (null acts) then "" else concatMap makeChannelsAct (removeDuplicates acts) 
     createChann = if (null creates) then "" else makeChannels (length creates) "cact"
     constsChann = if (null consts) then "" else makeChannels (length consts) "hppd"
     extraChann  = actChann ++ createChann ++ constsChann
 in if (null vars) 
    then if (null extraChann)
         then ""
         else "VARIABLES {\n" ++ extraChann ++ "}\n\n"
    else "VARIABLES {\n" ++ extraChann ++ writeVariables' vars ++ "}\n\n"

writeVariables' :: Variables -> String
writeVariables' []     = ""
writeVariables' (v:vs) = writeVariable v ++ ";\n" ++ writeVariables' vs

writeVariable :: Variable -> String
writeVariable (Var vm t vdec) = writeVarModifier vm ++ " "
                                ++ t ++ " "
                                ++ flattenVariables (map writeVarDecl vdec)

writeVarModifier :: VarModifier -> String
writeVarModifier VarModifierNil   = ""
writeVarModifier VarModifierFinal = "final"

writeVarDecl :: VarDecl -> String
writeVarDecl (VarDecl id (VarInit ve)) = id ++ " = " ++ ve
writeVarDecl (VarDecl id VarInitNil)   = id

flattenVariables :: [String] -> String
flattenVariables []       = ""
flattenVariables [x]      = x
flattenVariables (x:y:xs) = x ++ "," ++ flattenVariables (y:xs)

makeChannels :: Int -> String -> String
makeChannels n s = generateChannels n s ++ "\n"

generateChannels :: Int -> String -> String
generateChannels 0 s = "\n"
generateChannels n s = generateChannels (n-1) s ++ " Channel " ++ s ++ show n ++ " = new Channel(\"" ++ s ++ show n ++ "\");\n"

makeChannelsAct :: String -> String
makeChannelsAct s = " Channel " ++ s ++ " = new Channel();\n"


--------------
-- Triggers --
--------------

writeTriggers :: Triggers -> HTriples -> [Id] -> Env -> String
writeTriggers [] _ _ _           = ""
writeTriggers es consts acts env = 
 "EVENTS {\n"
 ++ writeTriggersActs acts
 ++ writeAllTriggers (instrumentTriggers es consts env)
 ++ "}\n\n"

writeTriggersActs :: [Id] -> String
writeTriggersActs []         = "" 
writeTriggersActs (act:acts) =
 'r': act ++ "() = {" ++ act ++ ".receive()}" ++ "\n" ++ writeTriggersActs acts 


writeAllTriggers :: Triggers -> String
writeAllTriggers []     = ""
writeAllTriggers (e:es) = (getTrigger e) ++ writeAllTriggers es


getTrigger :: TriggerDef -> String
getTrigger (TriggerDef e arg cpe wc) =
 let wc' = if (wc == "") 
           then "" 
           else showWhere wc
 in e ++ "(" ++ getBindArgs' arg ++ ") = " ++ getCpe cpe ++ wc' ++ "\n"

getCpe :: CompoundTrigger -> String
getCpe (Collection (CECollection xs wc)) = "{" ++ getCollectionCpeCEElement xs ++ "}" 
                                           ++ showWhere wc
getCpe ce@(OnlyIdPar _)                  = getCpeCompoundTrigger ce
getCpe ce@(OnlyId _)                     = getCpeCompoundTrigger ce
getCpe ce@(ClockEvent _ _ _)             = getCpeCompoundTrigger ce
getCpe ce@(NormalEvent _ _ _ _)          = getCpeCompoundTrigger ce


getCollectionCpeCEElement :: [CEElement] -> String
getCollectionCpeCEElement []        = ""
getCollectionCpeCEElement [ce]      = getCpeCEElement ce
getCollectionCpeCEElement (ce:y:ys) = getCpeCEElement ce ++ " | " ++ getCollectionCpeCEElement (y:ys)

getCpeCEElement :: CEElement -> String
getCpeCEElement (CEct ct)    = getCpeCompoundTrigger ct
getCpeCEElement (CEid id)    = "{" ++ id ++ "}"
getCpeCEElement (CEidpar id) = "{" ++ id ++ "()" ++ "}"

getCpeCompoundTrigger :: CompoundTrigger -> String
getCpeCompoundTrigger (OnlyIdPar id)                 = "{" ++ id ++ "()" ++ "}"
getCpeCompoundTrigger (OnlyId id)                    = "{" ++ id ++ "}"
getCpeCompoundTrigger (ClockEvent id at n)           = "{" ++ id ++ show at ++ show n ++ "}"
getCpeCompoundTrigger (NormalEvent bind id bs ev)    = "{" ++ getBinding bind ++ id 
                                                        ++ "(" ++ getBindArgs bs ++ ")"
                                                        ++ getTriggerVariation' ev ++ "}"
getCpeCompoundTrigger _                              = ""

getBindArgs :: [Bind] -> String
getBindArgs []                     = ""
getBindArgs [BindId id]            = id
getBindArgs [BindIdExec id]        = id
getBindArgs [BindIdCall id]        = id
getBindArgs ((BindId id):y:ys)     = id ++ "," ++ getBindArgs (y:ys)
getBindArgs ((BindIdExec id):y:ys) = id ++ "," ++ getBindArgs (y:ys)
getBindArgs ((BindIdCall id):y:ys) = id ++ "," ++ getBindArgs (y:ys)
getBindArgs (BindStar:ys)          = "*," ++ getBindArgs ys
getBindArgs (BindStarExec:ys)      = "*," ++ getBindArgs ys
getBindArgs (BindStarCall:ys)      = "*," ++ getBindArgs ys

getBinding :: Binding -> String
getBinding (BindingVar bind) = show bind ++ "."

getTriggerVariation' :: TriggerVariation -> String
getTriggerVariation' EVEntry      = ""
getTriggerVariation' (EVExit xs)  = "uponReturning(" ++ auxGetTriggerVariation' xs ++ ")"
getTriggerVariation' (EVThrow xs) = "uponThrowing(" ++ auxGetTriggerVariation' xs ++ ")"
getTriggerVariation' (EVHadle xs) = "uponHandling(" ++ auxGetTriggerVariation' xs ++ ")"

auxGetTriggerVariation' :: [Bind] -> String
auxGetTriggerVariation' []           = ""
auxGetTriggerVariation' [BindId ret] = ret


----------------
-- Properties --
----------------

writeProperties :: Property -> HTriples -> Env -> Scope -> String
writeProperties PNIL _ _ _            = ""
writeProperties prop consts env scope = writeProperty prop consts env scope

writeProperty :: Property -> HTriples -> Env -> Scope -> String
writeProperty PNIL _ _ _                                       = ""
writeProperty (Property name states trans props) cs  env scope =
  "PROPERTY " ++ name ++ " \n{\n\n"
  ++ writeStates states
  ++ writeTransitions name trans cs states env scope
  ++ "}\n\n"
  ++ writeProperty props cs env scope

writeStates :: States -> String
writeStates (States start acc bad normal) =
 let acc'    = getStates acc
     bad'    = getStates bad
     normal' = getStates normal
     start'  = getStates start
 in "STATES \n{\n"
    ++ writeState "ACCEPTING" acc'
    ++ writeState "BAD" bad'
    ++ writeState "NORMAL" normal'
    ++ writeState "STARTING" start'
    ++ "}\n\n"

writeState :: String -> String -> String
writeState iden xs = if (clean xs == "")
                     then ""
                     else iden ++ " { " ++ xs ++ "}\n"

getStates :: [State] -> String
getStates []              = ""
getStates (State n ic _:xs) = n ++ " " ++ getInitCode' ic ++ " " ++ getStates xs

getInitCode' :: InitialCode -> String
getInitCode' InitNil         = ""
getInitCode' (InitProg java) = "{" ++ init java ++ "}"

--HTriples [] -> Replicated Automata
--HTriples non-empty -> Property transitions instrumentation
writeTransitions :: PropertyName -> Transitions -> HTriples -> States -> Env -> Scope -> String
writeTransitions _ ts [] _ env scope =
 "TRANSITIONS \n{ \n"
 ++ concat (map (getTransition env) ts)
 ++ "}\n\n"
writeTransitions pn ts (c:cs) states env scope =
 "TRANSITIONS \n{ \n"
  ++ (concat (map (getTransition env) (getTransitionsGeneral (c:cs) states ts env pn scope)))
  ++ "}\n\n"

getTransition :: Env -> Transition -> String
getTransition env (Transition q (Arrow e c act) q') =
 let e' = if elem e (map (\ a -> a ++ "?") $ actes env)
          then "r" ++ init e
          else e
 in q ++ " -> " ++ q' ++ " [" ++ e' ++ " \\ "  ++ c ++ " \\ " ++ (concat.lines) act ++ "]\n"

getTransitionsGeneral :: HTriples -> States -> Transitions -> Env -> PropertyName -> Scope -> Transitions
getTransitionsGeneral cs (States star acc bad nor) ts env pn scope =
 let ts1 = generateAllTransitions star cs ts env pn scope
     ts2 = generateAllTransitions acc cs ts1 env pn scope
     ts3 = generateAllTransitions bad cs ts2 env pn scope
     ts4 = generateAllTransitions nor cs ts3 env pn scope
 in ts4

generateAllTransitions :: [State] -> HTriples -> Transitions -> Env -> PropertyName -> Scope -> Transitions
generateAllTransitions [] _ ts _ _ _                                 = ts
generateAllTransitions ((State ns ic []):xs) cs ts env pn scope      = generateAllTransitions xs cs ts env pn scope
generateAllTransitions ((State ns ic l@(_:_)):xs) cs ts env pn scope = 
 let ts' = accumTransitions l ns cs ts env pn scope
 in generateAllTransitions xs cs ts' env pn scope

accumTransitions :: [HTName] -> NameState -> HTriples -> Transitions -> Env -> PropertyName -> Scope -> Transitions
accumTransitions [] _ _ ts _ _ _                    = ts
accumTransitions (cn:cns) ns consts ts env pn scope =
 if cn == "null"
 then accumTransitions cns ns consts ts env pn scope
 else let (nonlts,gentrans,lts) = generateTransitions cn ns consts ts env pn scope
          instrans = instrumentTransitions cn ns consts lts env pn scope
      in accumTransitions cns ns consts (nonlts++instrans) env pn scope ++ gentrans

generateTransitions :: HTName -> NameState -> HTriples -> Transitions -> Env -> PropertyName -> Scope -> (Transitions,Transitions,Transitions)
generateTransitions p ns cs ts env pn scope = 
 let c             = lookForHT p cs ns
     mn            = _methodCN c ^. mname
     entrs         = lookForEntryTrigger (allTriggers env) (_methodCN c) (normaliseScope scope)
     entrs'        = [tr | tr <- entrs, not(isInfixOf (mn ++ "_ppden") tr)]
     (lts, nonlts) = foldr (\x xs -> (fst x ++ fst xs,snd x ++ snd xs)) ([],[]) $ map (\e -> lookForLeavingTransitions e ns ts) entrs'
 in if (null entrs)
    then error $ "Translation: Missing entry trigger for method " ++ mn ++ ".\n"
    else if (null lts)
         then (ts,makeTransitionAlg1 ns c env pn mn entrs,[])
         else let ext  = map (\e -> makeExtraTransitionAlg2 lts c e ns env pn) entrs'
                  ext' = map fromJust $ filter (\c -> c /= Nothing) ext
              in (nonlts,ext',lts)

-- Implementation of Algorithm 1 --

makeTransitionAlg1 :: NameState -> HT -> Env -> PropertyName -> MethodName -> [Trigger] -> Transitions
makeTransitionAlg1 ns c env pn mn entrs = 
 let entrs' = [tr | tr <- entrs, isInfixOf (mn++"_ppden") tr]
 in if null entrs'
    then map (\e -> makeTransitionAlg1Cond ns e c env pn) entrs
    else map (\e -> makeTransitionAlg1Cond ns e c env pn) entrs'


makeTransitionAlg1Cond :: NameState -> Trigger -> HT -> Env -> PropertyName -> Transition
makeTransitionAlg1Cond ns e c env pn =
 let cn      = c ^. htName
     oldExpM = oldExpTypes env
     (_,arg) = getValue $ lookForAllEntryTriggerArgs env c 
     arg'    = if tempScope scp
               then var
               else arg
     c'      = "HoareTriplesPPD." ++ cn ++ "_pre(" ++ arg' ++ ")"
     zs      = getExpForOld oldExpM cn
     act     = " hppd" ++ show (_chGet c) ++ ".send(" ++ msg ++ ");"
     type_   = if null zs then "PPD" else "Old<Old_" ++ cn ++ ">"
     old     = if null zs then "" else "," ++ zs
     ident   = lookforClVar pn (propInForeach env)
     ident'  = if null ident then "(id" else "(" ++ ident ++ "::id"
     trs     = [tr | tr <- allTriggers env, tiTN tr == e]
     var     = head $ map tiCVar trs
     scp     = head $ map tiScope trs
     old'    = if tempScope scp
               then replaceWith ((c ^. varThis ^. _1) ++".") (var++".") old
               else old
     msg     = "new Messages" ++ type_ ++ ident' ++ old' ++ ")"
 in Transition ns (Arrow e c' act) ns

getExpForOld :: OldExprM -> HTName -> String
getExpForOld oldExpM cn = 
 case Map.lookup cn oldExpM of
      Nothing -> ""
      Just xs -> if null xs 
                 then ""
                 else initOldExpr xs cn

initOldExpr :: OldExprL -> HTName -> String
initOldExpr oel cn = 
 "new Old_" ++ cn ++ "(" ++ addComma (map (\(x,_,_) -> x) oel) ++ ")"


-- Implementation of Algorithm 2 --

makeExtraTransitionAlg2 :: Transitions -> HT -> Trigger -> NameState -> Env -> PropertyName -> Maybe Transition
makeExtraTransitionAlg2 [] _ _ _ _ _     = Nothing
makeExtraTransitionAlg2 ts c e ns env pn = 
 let oldExpM = oldExpTypes env
     cn      = c ^. htName
     zs      = getExpForOld oldExpM cn
     (_,arg) = getValue $ lookForAllEntryTriggerArgs env c 
     arg'    = if tempScope scp
               then var
               else arg
     pre'    = "HoareTriplesPPD." ++ (c ^. htName) ++ "_pre(" ++ arg' ++ ")"
     type_   = if null zs then "PPD" else "Old<Old_" ++ cn ++ ">"
     old     = if null zs then "" else "," ++ zs
     ident   = lookforClVar pn (propInForeach env)
     ident'  = if null ident then "(id" else "(" ++ ident ++ "::id"
     trs     = [tr | tr <- allTriggers env, tiTN tr == e]
     var     = head $ map tiCVar trs
     scp     = head $ map tiScope trs
     old'    = if tempScope scp
               then replaceWith ((c ^. varThis ^. _1) ++".") (var++".") old
               else old
     msg     = "new Messages" ++ type_ ++ ident' ++ old' ++ ")"
     act     = " hppd" ++ show (_chGet c) ++ ".send(" ++ msg ++ ");"
     c'      = makeExtraTransitionAlg2Cond ts 
 in case c' of
         Nothing  -> Nothing 
         Just c'' -> Just $ Transition ns (Arrow e (c''++ pre') act) ns

makeExtraTransitionAlg2Cond :: Transitions -> Maybe String
makeExtraTransitionAlg2Cond ts = 
 case avoidTriviallyFalseCond ts of 
      [] -> Nothing 
      xs -> Just $ getConditionsInTransitions xs

getConditionsInTransitions :: Transitions -> String
getConditionsInTransitions []     = ""
getConditionsInTransitions (t:ts) =
 let cond'  = cond $ arrow t
     cond'' = if (null $ clean cond') then "true" else cond'
 in "!("++ cond'' ++ ") && " ++ getConditionsInTransitions ts

--Method used to avoid generating transitions with conditions trivially false
avoidTriviallyFalseCond :: Transitions -> Transitions
avoidTriviallyFalseCond = filter (check.trim.cond.arrow)
                                    where check = \ t -> t /= "true" && (not.null.trim) t

instrumentTransitions :: HTName -> NameState -> HTriples -> Transitions -> Env -> PropertyName -> Scope -> Transitions
instrumentTransitions p ns cs ts env pn scope = 
 let c             = lookForHT p cs ns
     mn            = _methodCN c ^. mname
     entrs         = lookForEntryTrigger (allTriggers env) (_methodCN c) (normaliseScope scope)
     entrs'        = [tr | tr <- entrs, not(isInfixOf (mn++"_ppden") tr)]
     (lts, nonlts) = foldr (\x xs -> (fst x ++ fst xs,snd x ++ snd xs)) ([],[]) $ map (\e -> lookForLeavingTransitions e ns ts) entrs'
 in if null entrs
    then error $ "Translation: Missing entry trigger for method " ++ mn ++ ".\n"
    else if (null lts)
         then []
         else concat [map (\x -> instrumentTransitionAlg2 c x tr env pn) lts | tr <- entrs']

instrumentTransitionAlg2 :: HT -> Transition -> Trigger -> Env -> PropertyName -> Transition
instrumentTransitionAlg2 c t@(Transition q (Arrow e' c' act) q') e env pn =
 let cn      = c ^. htName
     oldExpM = oldExpTypes env
     (_,arg) = getValue $ lookForAllEntryTriggerArgs env c 
     arg'    = if tempScope scp
               then var
               else arg
     zs      = getExpForOld oldExpM cn
     type_   = if null zs then "PPD" else "Old<Old_" ++ cn ++ ">"
     old     = if null zs then "" else "," ++ zs
     ident   = lookforClVar pn (propInForeach env)
     ident'  = if null ident then "(id" else "(" ++ ident ++ "::id"
     trs     = [tr | tr <- allTriggers env, tiTN tr == e]
     var     = head $ map tiCVar trs
     scp     = head $ map tiScope trs
     old'    = if tempScope scp
               then replaceWith ((c ^. varThis ^. _1) ++".") (var++".") old
               else old
     msg     = "new Messages" ++ type_ ++ ident' ++ old' ++ ")"
     act'    = " if (HoareTriplesPPD." ++ cn ++ "_pre(" ++ arg' ++ ")) { hppd" ++ show (_chGet c) ++ ".send(" ++ msg ++ "); " ++ "} ;"
 in Transition q (Arrow e' c' (act ++ act')) q'


lookForHT :: PropertyName -> HTriples -> NameState -> HT
lookForHT p []     ns = error $ "Error: Could not find property "++ p ++ " on state " ++ ns ++ ".\n"
lookForHT p (c:cs) ns =
 if (c ^. htName == p)
 then c
 else lookForHT p cs ns

lookForLeavingTransitions :: Trigger -> NameState -> Transitions -> (Transitions, Transitions)
lookForLeavingTransitions e ns []                                        = ([],[])
lookForLeavingTransitions e ns (t@(Transition q (Arrow e' c act) q'):ts) = 
 if (e == e')
 then if (ns == q)
      then (t:a, b)
      else (a, t:b)
 else (a,t:b)
     where (a, b) = lookForLeavingTransitions e ns ts

-------------
-- Foreach --
-------------

writeForeach :: Foreaches -> HTriples -> Env -> String
writeForeach [] _ _                    = ""
writeForeach (foreach:fors) consts env =
 let ctxt   = foreach ^. getCtxtForeach
     args   = foreach ^. getArgsForeach
     ForId id = foreach ^. getIdForeach
     vars   = foreach ^. (getCtxtForeach . variables)
     trigg  = foreach ^. (getCtxtForeach . triggers)
     prop   = foreach ^. (getCtxtForeach . property)
     acts   = foreach ^. (getCtxtForeach . actevents)
     fors'  = foreach ^. (getCtxtForeach . foreaches)    
 in "FOREACH (" ++ getForeachArgs args ++ ") {\n\n"
    ++ writeVariables vars [] [] []
    ++ writeTriggers trigg consts [] env
    ++ writeProperties prop consts env (InFor $ foreach ^. getIdForeach)
    ++ writeForeach fors' consts env
    ++ "}\n\n"
    ++ writeForeach fors consts env

getForeachArgs :: [Args] -> String
getForeachArgs []               = ""
getForeachArgs [Args t id]      = t ++ " " ++ id
getForeachArgs (Args t id:y:ys) = t ++ " " ++ id ++ "," ++ getForeachArgs (y:ys)


---------------------
-- Methods section --
---------------------

writeMethods :: Methods -> String
writeMethods methods = "\n" ++  methods

-------------------------
-- Replicated Automata --
-------------------------

generateReplicatedAutomata :: HTriples -> Triggers -> Env -> String
generateReplicatedAutomata cs es env = 
 let n        = length cs
     ys       = zip cs [1..n]
 in generateProp es ys env

generateProp :: Triggers -> [(HT,Int)] -> Env -> String
generateProp _ [] _            = ""
generateProp es ((c,n):ys) env = 
 let ra = genRA c n es env
 in ra ++ generateProp es ys env

-- Included to interact with optimisation OptRecAway.hs --
genRA :: HT -> Int -> Triggers -> Env -> String
genRA c n es env = generateRAPost c n es env

--Generates automaton to control a postcondition
generateRAPost :: HT -> Int -> Triggers -> Env -> String
generateRAPost c n es env = 
 let tr      = generateTriggerRA env c n ("idPPD = msgPPD.id;","idPPD = id;")
     prop    = generateRAString es env c n
     cn      = snd prop
     oldExpM = oldExpTypes env
     zs      = getOldExpr oldExpM cn
     nvar    = if null zs then "" else "Old_" ++ cn ++ " oldExpAux = new " ++ "Old_" ++ cn ++ "();\n" 
 in "FOREACH (Integer idPPD) {\n\n"
    ++ "VARIABLES {\n" ++ " Integer idAuxPPD = new Integer(0);\n" ++ nvar ++ "}\n\n"
    ++ "EVENTS {\n" ++ tr ++ "}\n\n"
    ++ fst prop
    ++ "}\n\n"

generateTriggerRA :: Env -> HT -> Int -> (String,String) -> String
generateTriggerRA env c n w =
 let cn       = c ^. htName
     mnc      = _methodCN c
     mn       = mnc ^. mname
     ci       = mnc ^. clinf
     ov       = mnc ^. overl
     oldExpM  = oldExpTypes env
     zs       = getOldExpr oldExpM cn
     nvar     = if null zs then "PPD" else "Old<Old_" ++ cn ++ ">"     
     wtr      = if null (snd w) then "" else " where { " ++ snd w ++ "}\n"
     ntr      = getTriggerDef ov c (allTriggers env)
 in "rh" ++ show n ++ "(Messages" ++ nvar  
    ++ " msgPPD) = {hppd"++ show n ++ ".receive(msgPPD)} where {" ++ fst w ++  "}\n"
    ++ init (concatMap getTrigger (instrumentTriggers [ntr] [c] env)) ++ wtr


generateRAString :: Triggers -> Env -> HT -> Int -> (String,HTName)
generateRAString es env c n =
  let ra = generateRA c n env
      cn = pName ra
  in ("PROPERTY " ++ cn ++ "\n{\n\n"
     ++ writeStates (pStates ra)
     ++ writeTransitions cn (pTransitions ra) [] (States [] [] [] []) emptyEnv (InFor (ForId cn))
     ++ "}\n\n",cn)

-- Checks if the trigger to control has to be the auxiliary one (in case of optimisation by key) --

instrumentTriggers :: Triggers -> HTriples -> Env -> Triggers
instrumentTriggers [] cs _       = []
instrumentTriggers (e:es) cs env = 
 let (b,mn,bs) = lookupHTForTrigger e (getClassInfo e env) cs 
 in if b
    then let e'  = updateMethodCallName e (mn++"Aux")             
             e'' = args %~ (\ arg -> arg ++ [BindType "Integer" "id"]) $ e'
         in updateMethodCallBody e'' (bs++[BindId "id"]):instrumentTriggers es cs env
    else e:instrumentTriggers es cs env

lookupHTForTrigger :: TriggerDef -> ClassInfo -> HTriples -> (Bool, MethodName, [Bind])
lookupHTForTrigger _ _ []      = (False,"", [])
lookupHTForTrigger e ci (c:cs) = case e ^. compTrigger of
                                      NormalEvent _ id bs _ -> if (id == (_methodCN c ^. mname) && (_methodCN c ^. clinf) == ci)
                                                               then (True, id, bs)
                                                               else lookupHTForTrigger e ci cs
                                      _                     -> lookupHTForTrigger e ci cs

getClassInfo :: TriggerDef -> Env -> ClassInfo
getClassInfo e env = 
 let trs  = [tr | tr <- allTriggers env, tiTN tr == e ^. tName]
     cinf = head $ map tiCI trs
 in case cinf of
         "not a channel" -> (getClassInfoTrDef e) ^. _2
         _               -> cinf

--Mainly used to instantiate triggers of template stored in the environment
getClassInfoTrDef :: TriggerDef -> (ClassInfo,Id,MethodName)
getClassInfoTrDef tr = 
 case tr ^. compTrigger of 
      NormalEvent (BindingVar bind) mn _ _ -> 
          case bind of
               BindType t id     -> (t,id,mn) 
               BindTypeExec t id -> (t,id,mn)
               BindTypeCall t id -> (t,id,mn)
               BindId   id      -> let xs = words id in
                                   if length xs == 2
                                   then (head xs, (head.tail) xs,mn)
                                   else head $ [ (getBindType x,id,mn) | x <- tr ^. args, getIdBind x == id
                                                                    , (not.null) $ getBindType x]
                                               ++ [("no-class-info","no-var-info",mn)]
               BindIdExec id    -> let xs = words id in
                                   if length xs == 2
                                   then (head xs, (head.tail) xs,mn)
                                   else head $ [ (getBindType x,id,mn) | x <- tr ^. args, getIdBind x == id
                                                                    , (not.null) $ getBindType x]
                                               ++ [("no-class-info","no-var-info",mn)]
               BindIdCall id    -> let xs = words id in
                                   if length xs == 2
                                   then (head xs, (head.tail) xs,mn)
                                   else head $ [ (getBindType x,id,mn) | x <- tr ^. args, getIdBind x == id
                                                                    , (not.null) $ getBindType x]
                                               ++ [("no-class-info","no-var-info,",mn)]
               _                -> ("no-class-info","no-var-info",mn)
      _                                    -> ("no-class-info","no-var-info","no-method-name")



---------------
-- Templates --
---------------

writeTemplates :: Templates -> Env -> HTriples -> String
writeTemplates TempNil _ _             = ""
writeTemplates (Temp temps) env consts = 
 let creates = removeDuplicates $ allCreateAct env
     skell   = map generateRAtmp temps
     ys      = [ instantiateTemp for id args cai env | (id,args,for) <- skell , cai <- creates, id == cai ^. caiId ] 
     xs      = map fst ys
     env'    = env { allTriggers = instantiateTrEnv (allTriggers env) (concatMap snd ys)}
 in writeForeach xs consts env'

--Instantiates templates triggers stored in the environment
instantiateTrEnv :: [TriggersInfo] -> Triggers -> [TriggersInfo]
instantiateTrEnv [] _            = []
instantiateTrEnv (tr:alltrs) trs =  
 let xs   = [e | e <- trs, tiTN tr == e ^. tName]
     e'   = head xs
     tinf = getClassInfoTrDef $ e'
     tr'  = tr { tiCI = tinf ^. _1, tiTrDef = Just e', tiCVar = tinf ^. _2, tiMN = tinf ^. _3}
 in if null xs
    then tr : instantiateTrEnv alltrs trs
    else tr' : instantiateTrEnv alltrs trs

--Generates an abstract Foreach for the template
generateRAtmp :: Template -> (Id, [Args], Foreach)
generateRAtmp temp = (temp ^. tempId, temp ^. tempBinds, Foreach (filterRefTypes $ temp ^. tempBinds) (generateCtxtForTemp temp) (ForId (temp ^. tempId)))

generateCtxtForTemp :: Template -> Context
generateCtxtForTemp temp = Ctxt (temp ^. tempVars) (temp ^. tempActEvents) (temp ^. tempTriggers) (temp ^. tempProp) []

--Creates an instance of the abstract Foreach
instantiateTemp :: Foreach -> Id -> [Args] -> CreateActInfo -> Env -> (Foreach, Triggers)
instantiateTemp for id args cai env = 
 let ch     = cai ^. caiCh
     targs  = splitTempArgs (zip args (cai ^. caiArgs)) emptyTargs  
     mp     = Map.union (makeRefTypeMap $ targRef targs) (makeMap $ targMN targs)
     trs    = addTriggerDef args cai env mp
     ctxt   = for ^. getCtxtForeach
     aux    = instantiateTrs (ctxt ^. triggers) mp
     trs'   = (genTriggerForCreate id ch args): aux
     ctxt'  = triggers .~ (trs' ++ trs) $ ctxt
     ctxt'' = over property (\ p -> instantiateProp p args cai id) ctxt'
 in (Foreach (for ^. getArgsForeach) ctxt'' (ForId (show (for ^. getIdForeach) ++ "_"++ch))
    , aux)

instantiateTrs :: Triggers -> Map.Map Id String -> Triggers
instantiateTrs [] _        = []
instantiateTrs (tr:trs) mp = 
 let ce   = instantiateCE (tr ^. compTrigger) mp
     tr'  = compTrigger .~ fst ce $ tr
     tr'' = if (snd ce) == Nothing then tr' else tr' & whereClause %~ (\ wc -> wc ++ newWhereClause (fromJust $ snd ce))
 in tr'' : instantiateTrs trs mp

instantiateCE :: CompoundTrigger -> Map.Map Id String -> (CompoundTrigger, Maybe String)
instantiateCE (NormalEvent (BindingVar (BindId id')) id bs tv) mp = 
 let nid = instantiateArg mp id'
 in if nid == id' 
    then (NormalEvent (BindingVar (BindId nid)) (instantiateArg mp id) bs tv,Nothing)
    else (NormalEvent (BindingVar (BindId (nid++"_tmpPPD"))) (instantiateArg mp id) bs tv, Just $ nid++"_tmpPPD")
instantiateCE (NormalEvent (BindingVar (BindIdExec id')) id bs tv) mp = 
 let nid = instantiateArg mp id'
 in if nid == id' 
    then (NormalEvent (BindingVar (BindIdExec nid)) (instantiateArg mp id) bs tv,Nothing)
    else (NormalEvent (BindingVar (BindIdExec (nid++"_tmpPPD"))) (instantiateArg mp id) bs tv, Just $ nid++"_tmpPPD")
instantiateCE (NormalEvent (BindingVar (BindIdCall id')) id bs tv) mp = 
 let nid = instantiateArg mp id'
 in if nid == id' 
    then (NormalEvent (BindingVar (BindIdCall nid)) (instantiateArg mp id) bs tv,Nothing)
    else (NormalEvent (BindingVar (BindIdCall (nid++"_tmpPPD"))) (instantiateArg mp id) bs tv, Just $ nid++"_tmpPPD")
instantiateCE (NormalEvent bind id bs tv) mp = (NormalEvent bind (instantiateArg mp id) bs tv, Nothing)
instantiateCE (ClockEvent id at n) mp        = (ClockEvent (instantiateArg mp id) at n, Nothing)
instantiateCE (OnlyId id) mp                 = (OnlyId (instantiateArg mp id),Nothing)
instantiateCE (OnlyIdPar id) mp              = (OnlyIdPar (instantiateArg mp id),Nothing)

newWhereClause :: String -> WhereClause
newWhereClause s = 
 let xs = words $ head $ splitOnIdentifier "_tmpPPD" s
     ys = (head.tail) xs
 in ys ++ " = " ++ ys ++ "_tmpPPD" ++ " ;"

--Adds existing triggers definition to an instance of a template
addTriggerDef :: [Args] -> CreateActInfo -> Env -> Map.Map Id String -> Triggers
addTriggerDef args cai env mp = 
 let refs  = targRef $ splitTempArgs (zip args (cai ^. caiArgs)) emptyTargs
     targs = targTr $ splitTempArgs (zip args (cai ^. caiArgs)) emptyTargs
     scope = cai ^. caiScope
     trs   = allTriggers env 
 in [ adaptTrigger (fromJust $ tiTrDef tr) refs mp (tiCI tr) | tr <- trs, tiScope tr == scope, targ <- targs, (showActArgs $ snd targ) == tiTN tr, tiTrDef tr /= Nothing]
    
adaptTrigger :: TriggerDef -> [(Args,Act.Args)] -> Map.Map Id String -> ClassInfo -> TriggerDef
adaptTrigger tr [] _ _      = tr & whereClause .~ ""
adaptTrigger tr targs mp ci = 
 case tr ^. compTrigger of
      NormalEvent bind _ _ _ -> 
         case bind of 
              BindingVar (BindId id)     -> 
                   let xs = [ arg | arg <- tr ^. args, ci == getBindType arg, id == getIdBind arg]
                       ys = [ arg | arg <- tr ^. args, not (elem arg xs) ]
                       zs = [ getArgsId (fst targ) | arg <- xs, targ <- targs, getArgsType (fst targ) == getBindType arg ]
                   in if null zs 
                      then tr & whereClause .~ ""
                      else let tr' = tr & args .~ ys 
                                        & compTrigger %~ \ ct -> updCEne ct (BindingVar (BindId (head zs)))
                           in head $ instantiateTrs [tr'] mp
              BindingVar (BindIdExec id)     -> 
                   let xs = [ arg | arg <- tr ^. args, ci == getBindType arg, id == getIdBind arg]
                       ys = [ arg | arg <- tr ^. args, not (elem arg xs) ]
                       zs = [ getArgsId (fst targ) | arg <- xs, targ <- targs, getArgsType (fst targ) == getBindType arg ]
                   in if null zs 
                      then tr & whereClause .~ ""
                      else let tr' = tr & args .~ ys 
                                        & compTrigger %~ \ ct -> updCEne ct (BindingVar (BindIdExec (head zs)))
                           in head $ instantiateTrs [tr'] mp
              BindingVar (BindIdCall id)     -> 
                   let xs = [ arg | arg <- tr ^. args, ci == getBindType arg, id == getIdBind arg]
                       ys = [ arg | arg <- tr ^. args, not (elem arg xs) ]
                       zs = [ getArgsId (fst targ) | arg <- xs, targ <- targs, getArgsType (fst targ) == getBindType arg ]
                   in if null zs 
                      then tr & whereClause .~ ""
                      else let tr' = tr & args .~ ys 
                                        & compTrigger %~ \ ct -> updCEne ct (BindingVar (BindIdCall (head zs)))
                           in head $ instantiateTrs [tr'] mp
              BindingVar (BindType t id) -> 
                   let xs = [ getArgsId arg | arg <- map fst targs, t == getArgsType arg]
                   in if null xs 
                      then tr & whereClause .~ ""
                      else let tr' = tr & compTrigger %~ \ ct -> updCEne ct (BindingVar (BindId (head xs)))
                           in head $ instantiateTrs [tr'] mp      
              BindingVar (BindTypeExec t id) -> 
                   let xs = [ getArgsId arg | arg <- map fst targs, t == getArgsType arg]
                   in if null xs 
                      then tr & whereClause .~ ""
                      else let tr' = tr & compTrigger %~ \ ct -> updCEne ct (BindingVar (BindIdExec (head xs)))
                           in head $ instantiateTrs [tr'] mp                           
              BindingVar (BindTypeCall t id) -> 
                   let xs = [ getArgsId arg | arg <- map fst targs, t == getArgsType arg]
                   in if null xs 
                      then tr & whereClause .~ ""
                      else let tr' = tr & compTrigger %~ \ ct -> updCEne ct (BindingVar (BindIdCall (head xs)))
                           in head $ instantiateTrs [tr'] mp                                                
              BindingVar _               -> tr & whereClause .~ ""
      _                      -> tr & whereClause .~ ""

instantiateProp :: Property -> [Args] -> CreateActInfo -> Id -> Property
instantiateProp PNIL _ _ _                                 = PNIL
instantiateProp (Property id sts trans props) args cai id' =  
 let ch      = cai ^. caiCh
     sts'    = addNewInitState sts
     trans'  = (Transition "start" (Arrow ("r"++ch) "" "") (head $ map (^. getNS) $ getStarting sts)):trans
     targs   = splitTempArgs (zip args (cai ^. caiArgs)) emptyTargs
     sts''   = instantiateHT (makeMap $ targHT targs) sts'
     aux     = makeMap $ (targTr targs ++ targCond targs ++ targAct targs)
     trans'' = instantiateTrans aux trans' (map (^. getNS) $ getBad sts) ch id'
 in Property (id++"_"++ch) sts'' trans'' props

genTriggerForCreate :: Id -> Channel -> [Args] -> TriggerDef
genTriggerForCreate id ch args = 
 let tr    = "r"++ch
     args' = BindType ("Tmp_"++id) "obj"
     ce    = NormalEvent (BindingVar (BindId ch)) "receive" [BindId "obj"] EVEntry
     w     = concat [ getArgsId arg ++ " = obj." ++ getArgsId arg ++ "; " | arg <- filterRefTypes args ] 
 in TriggerDef tr [args'] ce w

addNewInitState :: States -> States
addNewInitState (States start accep bad norm) = States [State "start" InitNil []] accep bad (norm++start)

instantiateTrans :: Map.Map Id String -> Transitions -> [NameState] -> Channel -> Id -> Transitions
instantiateTrans mp trans sts ch id = 
 if Map.null mp
 then trans
 else map (instantiateTran mp sts ch id) trans

instantiateTran :: Map.Map Id String -> [NameState] -> Channel -> Id -> Transition -> Transition
instantiateTran mp bads ch id tran = 
 if elem (toState tran) bads
 then Transition (fromState tran) (refineArrow ch id $ instantiateArrow mp $ arrow tran) (toState tran)
 else Transition (fromState tran) (instantiateArrow mp $ arrow tran) (toState tran)

refineArrow :: Channel -> Id -> Arrow -> Arrow
refineArrow ch id (Arrow tr cond act) = 
 Arrow tr cond (act ++ "; " ++ ch ++ ".flare = true; " ++ ch ++ ".send(new Tmp_" ++ id ++ "(null));")

instantiateArrow :: Map.Map Id String -> Arrow -> Arrow
instantiateArrow mp arrow = 
 Arrow (instantiateArg mp (trigger arrow)) 
       (prepareCond mp $ cond arrow) 
       (prepareAct mp $ action arrow)

prepareCond :: Map.Map Id String -> Cond -> Cond
prepareCond _ []    = []
prepareCond mp cond = PrintJML.printTree $ instantiateCond mp $ fromOK . ParJML.parse $ cond

instantiateCond :: Map.Map Id String -> Jml.JML -> Jml.JML
instantiateCond mp cond = 
 case cond of
      Jml.JMLAnd jml jml'       -> Jml.JMLAnd (instantiateCond mp jml) (instantiateCond mp jml')
      Jml.JMLOr jml jml'        -> Jml.JMLOr (instantiateCond mp jml) (instantiateCond mp jml')
      Jml.JMLImp jml jml'       -> Jml.JMLImp (instantiateCond mp jml) (instantiateCond mp jml')
      Jml.JMLIff jml jml'       -> Jml.JMLIff (instantiateCond mp jml) (instantiateCond mp jml')
      Jml.JMLForallRT t id body -> Jml.JMLForallRT t id body
      Jml.JMLExistsRT t id body -> Jml.JMLExistsRT t id body
      Jml.JMLPar jml            -> Jml.JMLPar (instantiateCond mp jml)
      Jml.JMLExp exps           -> Jml.JMLExp $ map (instantiateExps mp) exps

instantiateExps :: Map.Map Id String -> Jml.Expression -> Jml.Expression
instantiateExps mp (Jml.Exp (Jml.IdJml id)) = Jml.Exp (Jml.IdJml (instantiateArg mp id))
instantiateExps mp (Jml.ExpPar exps)        = Jml.ExpPar (map (instantiateExps mp) exps)
instantiateExps mp jml                      = jml

prepareAct :: Map.Map Id String -> Action -> Action
prepareAct mp []  = []
prepareAct mp act = PrintAct.printTree $ instantiateActs mp $ fromOK . ParAct.parse $ act

instantiateActs :: Map.Map Id String -> Act.Actions -> Act.Actions
instantiateActs mp (Act.Actions acts) = Act.Actions (map (instantiateAct mp) acts)

instantiateAct :: Map.Map Id String -> Act.Action -> Act.Action
instantiateAct mp act =
 case act of
      Act.ActBlock acts                       -> Act.ActBlock $ instantiateActs mp acts
      Act.ActCond xs act'                     -> Act.ActCond xs $ instantiateAct mp act'
      Act.ActArith (Act.Arith (Act.IdAct id)) -> Act.ActArith (Act.Arith (Act.IdAct (checkAct $ instantiateArg mp id)))
      _                                       -> act

checkAct :: String -> String
checkAct []  = []
checkAct act = init.cleanBack $ PrintAct.printTree $ (\act -> translateAct act emptyEnv) $ fromOK . ParAct.parse $ (act++";")

instantiateHT :: Map.Map Id String -> States -> States
instantiateHT mp sts = 
 if Map.null mp
 then sts
 else States (instantiateStates (getStarting sts) mp) 
             (instantiateStates (getAccepting sts) mp)
             (instantiateStates (getBad sts) mp) 
             (instantiateStates (getNormal sts) mp)  

instantiateStates :: [State] -> Map.Map Id String -> [State]
instantiateStates [] _      = []
instantiateStates (s:ss) mp = (getCNList %~ map (instantiateArg mp) $ s) : instantiateStates ss mp

instantiateArg :: Map.Map Id String -> Id -> String
instantiateArg mp id = 
 case Map.lookup id mp of
      Nothing -> id
      Just s  -> s

makeMap :: [(Args,Act.Args)] -> Map.Map Id String
makeMap = Map.fromList . map (\(x,y) -> (getArgsId x, showActArgs y))

makeRefTypeMap :: [(Args,Act.Args)] -> Map.Map Id String
makeRefTypeMap args = Map.fromList [ (getArgsId x,show x) | (x,y) <- args]
