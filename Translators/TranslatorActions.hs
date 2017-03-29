module TranslatorActions(translateAct) where

import AbsActions
import PrintActions
import UpgradePPDATE
import qualified Types as T
import Data.Maybe

translateAct :: Actions -> Env -> Actions
translateAct (Actions acts) env = Actions $ map (translateAction' env) acts



translateAction' :: Env -> Action -> Action
translateAction' env (ActCond conds act)                    = ActCond conds (translateAction' env act)
translateAction' env (ActBlock acts)                        = ActBlock (translateAct acts env)
translateAction' _ (ActBang (IdAct id))                     = ActProg (Prog (IdAct (id++".send")) [])
translateAction' _ (ActLog s parms)                         = ActProg (Prog (IdAct "System.out.printf") (ArgsS s:fromParm2Arg parms))
translateAction' env act@(ActCreate (Temp (IdAct id)) args) = 
 let creates = allCreateAct env    
     ch      = T.caiCh $ fromJust $ getChannel act creates
     args'   = head [xs | (id',xs) <- tempsInfo env, id == id']
     fargs   = map fst $ filterRefTypes $ zip args args'
 in ActProg (Prog (IdAct (ch++".send")) ([ArgsNew (Prog (IdAct ("Tmp_"++id)) fargs)]))
translateAction' _ act                                      = act

fromParm2Arg :: Params -> [Args]
fromParm2Arg ParamsNil   = []
fromParm2Arg (Params xs) = map (\(Param id) -> ArgsId id) xs

getChannel :: Action -> [T.CreateActInfo] -> Maybe T.CreateActInfo
getChannel act@(ActCreate (Temp (IdAct id)) args) []         = Nothing
getChannel act@(ActCreate (Temp (IdAct id)) args) (cai:acts) = 
 if act == (T.caiAct cai)
 then Just cai
 else getChannel act acts
getChannel _ _                                               = Nothing

filterRefTypes :: [(Args,T.Args)] -> [(Args,T.Args)]
filterRefTypes []         = []
filterRefTypes ((arg,arg'):args) = 
  case T.getArgsType arg' of
      "Action"     -> filterRefTypes args
      "Condition"  -> filterRefTypes args
      "Trigger"    -> filterRefTypes args
      "MethodName" -> filterRefTypes args
      "HTriple"    -> filterRefTypes args
      _            -> (arg,arg'):filterRefTypes args
