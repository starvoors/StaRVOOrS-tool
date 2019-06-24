module OperationalizationPP (operationalizeOldResultBind, operationalizeForall, operationalizeExists) where

import Types
import CommonFunctions
import Translators.DL2JML
import RefinementPPDATE (getClassVar)
import Data.Char
import UpgradePPDATE
import ErrM
import qualified Data.Map as Map
import Data.Maybe (fromJust)
import Data.List
import Control.Lens hiding(Context,pre)

-------------------------------------
-- Performs the operationalisation --
-------------------------------------

operationalizeOldResultBind :: UpgradePPD PPDATE -> Map.Map HTName [(String,Type)] -> UpgradePPD PPDATE
operationalizeOldResultBind ppd oldExprTypesM =
 let (ppdate, env) =  fromOK $ runStateT ppd emptyEnv
     global   = ppdate ^. globalGet
     consts   = ppdate ^. htsGet
     jinfo    = javaFilesInfo env
     methods  = map (\(x,y,z) -> (x,y,map (^. _2) (methodsInFiles z))) jinfo
     es       = getAllTriggers global env
     xs       = map (\ c -> operationalizePrePostORB c (javaFilesInfo env) es methods oldExprTypesM) consts
     xs'      = map (\(Bad s) -> s) $ filter isBad $ map (\x -> runStateT x env) xs
     oldExpT  = Map.unions $ map (snd.goo env) xs
     consts'  = map (fst.goo env) xs
 in if (not.null) xs'
    then error $ unlines xs'
    else ppd >>= (\x -> do put env { oldExpTypes = oldExpT } ; return $ ppdate & htsGet .~ consts')
                 where goo env = \ x -> fst $ fromOK $ runStateT x env


operationalizePrePostORB :: HT -> [(String, ClassInfo, JavaFilesInfo)] -> Triggers -> [(String, ClassInfo, [String])] -> Map.Map HTName [(String,Type)] -> UpgradePPD (HT,OldExprM)
operationalizePrePostORB c vars trigs methods oldExprTypesM = 
 do let cn             = c ^. htName
    let p              = c ^. pre
    let p'             = c ^. post
    (xsPost, oldExprl) <- operationalizeOld p' cn
    let ysPost         = operationalizeResult xsPost
    let oldExprl'      = addType2NewVars cn oldExprTypesM oldExprl
    let c'             = post .~ ysPost $ c
    let oldExprl''     = bindOldExp c vars trigs methods oldExprl'
    return (bindCV c' vars trigs methods, Map.singleton cn oldExprl'')


--------------------------
-- bind class variables --
--------------------------

bindCV :: HT -> [(String, ClassInfo, JavaFilesInfo)] -> Triggers -> [(String, ClassInfo, [String])] -> HT
bindCV c vars es methods =
 let bindEntry = getClassVar c es EVEntry
     bindExit  = getClassVar c es (EVExit [])
     varsc  = getVarsToControl (_methodCN c ^. clinf) vars
     mnames = getMethodsToControl (_methodCN c ^. clinf) methods
     pre'   = concat $ bindVars bindEntry varsc (c ^. pre)
     post'  = concat $ bindVars bindExit varsc (c ^. post)
     pre''  = concat $ bindMethods bindEntry mnames pre'
     post'' = concat $ bindMethods bindExit mnames post'
     npre   = map (replaceSelfWith bindEntry) (c ^. newPRe)
 in c & pre .~ pre''
      & post .~ post''
      & newPRe .~ npre
      & varThis .~ (bindEntry,bindExit)

bindOldExp :: HT -> [(String, ClassInfo, JavaFilesInfo)] -> Triggers -> [(String, ClassInfo, [String])] -> OldExprL -> OldExprL
bindOldExp c vars es _ []             = []
bindOldExp c vars es ms ((x,y,z):xss) = 
 let bindEntry = getClassVar c es (EVEntry)
     varsc     = getVarsToControl (_methodCN c ^. clinf) vars
     x'        = concat $ bindVars bindEntry varsc x
     ms'       = getMethodsToControl (_methodCN c ^. clinf) ms
     x''       = concat $ bindMethods bindEntry ms' x'
 in (x'',y,z):bindOldExp c vars es ms xss


bindMethods :: String -> [String] -> String -> [String]
bindMethods bindn mnames s = 
 let exps = getExpressions s
 in bindExpsM bindn mnames exps

getMethodsToControl :: ClassInfo -> [(String, ClassInfo, [String])] -> [String]
getMethodsToControl cl []       = []
getMethodsToControl cl (val:xs) = if (cl == (val ^. _2))
                                  then val ^. _3
                                  else getMethodsToControl cl xs

bindExpsM :: String -> [String] -> [String] -> [String]
bindExpsM bindn _ []           = []
bindExpsM bindn nms (exp:exps) = if (elem exp nms)
                                 then (bindn ++ "." ++ exp):bindExpsM bindn nms exps
                                 else exp : bindExpsM bindn nms exps


bindVars :: String -> [String] -> String -> [String]
bindVars bindn varsc s = 
 let exps = getExpressions s
 in bindExps bindn varsc exps

bindExps :: String -> [String] -> [String] -> [String]
bindExps bindn _ []            = []
bindExps bindn vars (exp:exps) = (bindExp bindn exp vars) : bindExps bindn vars exps

bindExp :: String -> String -> [String] -> String
bindExp bindn exp []     = exp
bindExp bindn exp (v:vs) = if ((exp == v) || (v == fst (splitAtIdentifier '.' exp)))
                           then bindn ++ "." ++ exp
                           else bindExp bindn exp vs

getExpressions :: String -> [String]
getExpressions s = let (exp, rest) = getExpression s
                   in if (exp == "" && rest == "")
                      then []
                      else exp : getExpressions' rest

getExpressions' :: String -> [String]
getExpressions' s = let (exp, rest) = getExpression' s
                     in if (exp == "" && rest == "")
                        then []
                        else exp : getExpressions rest

getExpression' :: String -> (String, String)
getExpression' s = (takeWhile (not.isCharExpression) s, dropWhile (not.isCharExpression) s)

getExpression :: String -> (String, String)
getExpression s = (takeWhile isCharExpression s, dropWhile isCharExpression s)

isCharExpression :: Char -> Bool
isCharExpression = (\c -> isIdentifierSymbol c || c == '.')

getVarsToControl :: ClassInfo -> [(String, ClassInfo, JavaFilesInfo)] -> [String]
getVarsToControl cl []       = []
getVarsToControl cl (val:xs) = if (cl == (val ^. _2))
                               then map (^. _3) $ varsInFiles (val ^. _3)
                               else getVarsToControl cl xs
----------
-- \old --
----------

-- returns the operationalized post and a map storing the expressions in old operators
operationalizeOld :: String -> HTName -> UpgradePPD (String, OldExprL)
operationalizeOld post cn = 
 let xs = splitOnIdentifier "\\old(" post
 in if (length xs == 1)
    then return (post, [])
    else let begin = head xs
             ys    = tail xs
             zs    = map ((\(x,y) -> (trim x, clean $ tail y)) . (splitAtClosingParen 0)) ys
             fszs  = foldr (\(x,y) xs -> (x,"","e" ++ show y):xs) [] $ zip (removeDuplicates (map fst zs)) [1..length zs]
         in do flat <- flattenOld zs cn fszs
               return (begin ++ flat,fszs)

flattenOld :: [(String, String)] -> HTName -> OldExprL -> UpgradePPD String
flattenOld [] cn _             = return ""
flattenOld ((xs,ys):xss) cn zs = 
 do xs' <- getExpName zs xs cn
    rec <- flattenOld xss cn zs
    return $ xs' ++ " " ++ ys ++ rec

getExpName :: OldExprL -> String -> HTName -> UpgradePPD String
getExpName [] exp _             = fail "Error: Cannot get type to operationalise \\old expresion"
getExpName ((a,_,c):xss) exp cn = if exp == a
                                  then return $ cn ++ "."  ++ c
                                  else getExpName xss exp cn

addType2NewVars :: HTName -> Map.Map HTName [(String,Type)] -> OldExprL -> OldExprL
addType2NewVars cn _ []                      = []
addType2NewVars cn mtypes oexpr@((v,t,e):vs) = 
 let typE  = getType v cn mtypes     
 in (v,typE,e):addType2NewVars cn mtypes vs

getType :: Id -> HTName -> Map.Map HTName [(String,Type)] -> Type
getType var cn oldExprTypesM = 
 let xs = fromJust $ Map.lookup cn oldExprTypesM 
     ys = [t | (y,t) <- xs, y==var]
 in if (null ys)
    then ""
    else head ys


-------------
-- \result --
-------------

operationalizeResult :: String -> String
operationalizeResult s =
 let xs = splitOnIdentifier "\\result" s
 in if (length xs == 1)
    then s
    else let begin = head xs
             ys = map ("ret"++) $ tail xs
         in begin ++ (concat ys)

-------------
-- \forall --
-------------

operationalizeForall :: HT -> Env -> OldExprM -> UpgradePPD ([Either (String, String) String], [Either (String, String) String])
operationalizeForall c env oldExpM = 
 do let mn             = _methodCN c ^. mname
    let cinfo          = _methodCN c ^. clinf
    let p              = c ^. pre
    (enargs, enargswt) <- lookForAllEntryTriggerArgs env c Nothing
    let p'             = c ^. post
    (exargs, exargswt) <- lookForAllExitTriggerArgs env c
    let xs             = splitInQuantifiedExpression p "\\forall"
    let ys             = splitInQuantifiedExpression p' "\\forall"
    let tnewvars       = getConstTnv c oldExpM 
    let xs_pre         = applyGenMethodForall xs (c ^. htName) 1 enargs enargswt "_pre" []
    let ys_post        = applyGenMethodForall ys (c ^. htName) 1 exargs exargswt "_post" tnewvars
    return (xs_pre, ys_post)


applyGenMethodForall :: [Either String String] -> HTName -> Int -> String -> String -> String -> Variables -> [Either (String, String) String]
applyGenMethodForall [] _ _ _ _ _ _                        = []
applyGenMethodForall ((Right x):xs) cn n args argswt s tnv = Right x:applyGenMethodForall xs cn n args argswt s tnv
applyGenMethodForall ((Left x):xs) cn n args argswt s  tnv = 
 let y  = splitQuantifiedExpression x
     z  = generateMethodForall cn n y args argswt s tnv
 in Left z:applyGenMethodForall xs cn (n+1) args argswt s tnv

generateMethodForall :: HTName -> Int -> (String, String, String) -> String -> String -> String -> Variables -> (String, String)
generateMethodForall cn n (var, range, body) args argswt s [] = 
 let mn = cn ++ s ++ "_opF_" ++ show n
 in (mn ++ "(" ++ argswt ++ ")", methodForall mn (var, range, body) args)
generateMethodForall cn n (var, range, body) args argswt s tnv = 
 let mn   = cn ++ s ++ "_opF_" ++ show n
     tnv' = auxNewVars tnv
     tnewvars = addComma tnv'
     newargs  = addComma $ map (last.words) tnv'
     argswt'  = if null newargs then argswt else argswt ++ "," ++ newargs
     args'    = if null tnewvars then args else args ++ "," ++ tnewvars
 in (mn ++ "(" ++ argswt' ++ ")", methodForall mn (var, range, body) args')


auxNewVars :: Variables -> [String]
auxNewVars []                          = []
auxNewVars (Var _ t [VarDecl id _]:xs) = (t ++ " " ++ id):auxNewVars xs

methodForall :: String -> (String, String, String) -> String -> String
methodForall mn (tvar, range, body) args = 
 let var   = last $ words tvar 
     low   = getLowBoundary range var
     top   = getTopBoundary range var
 in
    "public static boolean " ++ mn ++ "(" ++ args ++ ") {\n" 
 ++ "      boolean r = true;\n\n"
 ++ "      for (" ++ tvar ++ " = " ++ low ++ " ; " ++ var ++ " <= " ++ top ++ " ; " ++ var ++ "++) {\n"
 ++ "          if (true) {\n"
 ++ "             if (!(" ++ body ++ ")) {\n"
 ++ "                 r = false ; break;\n"
 ++ "             }\n"
 ++ "          }\n"
 ++ "      }\n"
 ++ "      return r;\n"          
 ++ "    }\n\n"

getLowBoundary :: String -> String -> String
getLowBoundary s var = 
 let xs = splitOnIdentifier "<" s
     ys = splitOnIdentifier "<=" s
     zs = splitOnIdentifier ">" s
     ts = splitOnIdentifier ">=" s
 in if (length ys > 1 && (auxTake.trim.head.tail) ys == var)
    then reverse.auxTake $ (clean.reverse.head) ys
    else if (length xs > 1 && (auxTake.trim.head.tail) xs == var)
         then (reverse.auxTake $ (clean.reverse.head) xs) ++ " + 1"
         else if (length ts > 1 && (auxTake.reverse.trim.head) ts == var)
              then auxTake $ (clean.head.tail) ts 
              else if (length zs > 1 && (auxTake.reverse.trim.head) zs == var)
                   then (auxTake $ (clean.head.tail) zs) ++ " + 1"
                   else ""

getTopBoundary :: String -> String -> String
getTopBoundary s var = 
 let xs = splitOnIdentifier "<" s
     ys = splitOnIdentifier "<=" s
     zs = splitOnIdentifier ">" s
     ts = splitOnIdentifier ">=" s
 in if (length ys > 1 && (auxTake.reverse.trim.head) ys == var)
    then auxTake $ (clean.head.tail) ys
    else if (length xs > 1 && (auxTake.reverse.trim.head) xs == var)
         then (auxTake $ (clean.head.tail) xs) ++ " - 1"
         else if (length ts > 1 && (auxTake.trim.head.tail) ts == var)
              then reverse.auxTake $ (clean.reverse.head) ts
              else if (length zs > 1 && (auxTake.trim.head.tail) zs == var)
                   then (reverse.auxTake $ (clean.reverse.head) zs) ++ " - 1"
                   else ""

auxTake :: String -> String
auxTake = takeWhile (not.isSpace)


splitQuantifiedExpression :: String -> (String, String, String)
splitQuantifiedExpression s = 
 let xs = splitOnIdentifier ";" s
 in (trim $ head xs, (trim.head.tail) xs, (trim.last) xs)

splitInQuantifiedExpression :: String -> String -> [Either String String]
splitInQuantifiedExpression s qexpident = 
 let xs = splitOnIdentifier qexpident s
 in if (length xs == 1)
    then [Right $ head xs]
    else let begin = Right $ init $ trim $ head xs
             ys    = map (lookforEnd 0 []) $ tail xs
             zs    = concatMap foo ys
          in begin:zs
                  where foo (a,b) = [Left a, Right b]

lookforEnd :: Int -> String -> String -> (String ,String)
lookforEnd _ acum []     = (acum, [])
lookforEnd n acum (x:xs) = if (x == ')')
                           then case n of 
                                     0 -> (acum, xs)
                                     n -> lookforEnd (n-1) (acum ++ [x]) xs
                           else if (x == '(')
                                then lookforEnd (n+1) (acum ++ [x]) xs
                                else lookforEnd n (acum ++ [x]) xs

------------
-- \exist --
------------

operationalizeExists :: HT -> Env -> OldExprM -> UpgradePPD ([Either (String, String) String], [Either (String, String) String])
operationalizeExists c es oldExpM = 
 do let mn             = _methodCN c ^. mname
    let cinfo          = _methodCN c ^. clinf
    let p              = c ^. pre
    (enargs, enargswt) <- lookForAllEntryTriggerArgs es c Nothing
    let p'             = c ^. post
    (exargs, exargswt) <- lookForAllExitTriggerArgs es c
    let xs             = splitInQuantifiedExpression p "\\exists"
    let ys             = splitInQuantifiedExpression p' "\\exists"
    let tnewvars       = getConstTnv c oldExpM
    let xs_pre         = applyGenMethodExists xs (c ^. htName) 1 enargs enargswt "_pre" []
    let ys_post        = applyGenMethodExists ys (c ^. htName) 1 exargs exargswt "_post" tnewvars
    return (xs_pre, ys_post)


applyGenMethodExists :: [Either String String] -> HTName -> Int -> String -> String -> String -> Variables -> [Either (String, String) String]
applyGenMethodExists [] _ _ _ _ _ _                        = []
applyGenMethodExists ((Right x):xs) cn n args argswt s tnv = Right x:applyGenMethodExists xs cn n args argswt s tnv
applyGenMethodExists ((Left x):xs) cn n args argswt s tnv  = 
 let y  = splitQuantifiedExpression x
     z  = generateMethodExists cn n y args argswt s tnv
 in Left z:applyGenMethodExists xs cn (n+1) args argswt s tnv

generateMethodExists :: HTName -> Int -> (String, String, String) -> String -> String -> String -> Variables -> (String, String)
generateMethodExists cn n (var, range, body) args argswt s []  = 
 let mn = cn ++ s ++ "_opE_" ++ show n
 in (mn ++ "(" ++ argswt ++ ")", methodExists mn (var, range, body) args "")
generateMethodExists cn n (var, range, body) args argswt s tnv = 
 let mn = cn ++ s ++ "_opE_" ++ show n
     tnv' = auxNewVars tnv
     tnewvars = addComma tnv'
     newargs  = addComma $ map (last.words) tnv'
     args'    = if null newargs then argswt else argswt ++ "," ++ newargs
 in (mn ++ "(" ++ args' ++ ")", methodExists mn (var, range, body) args tnewvars)


methodExists :: String -> (String, String, String) -> String -> String -> String
methodExists mn (tvar, range, body) args tnv = 
 let var = last $ words tvar 
     low = getLowBoundary range var
     top = getTopBoundary range var
     args' = if null tnv then args else args ++ "," ++ tnv
 in
    "public static boolean " ++ mn ++ "(" ++ args' ++ ") {\n" 
 ++ "      boolean r = false;\n\n"
 ++ "      for (" ++ tvar ++ " = " ++ low ++ " ; " ++ var ++ " <= " ++ top ++ " ; " ++ var ++ "++) {\n"
 ++ "          if (true) {\n"
 ++ "             if (" ++ body ++ ") {\n"
 ++ "                 r = true ; break;\n"
 ++ "             }\n"
 ++ "          }\n"
 ++ "      }\n"
 ++ "      return r;\n"
 ++ "    }\n\n"

