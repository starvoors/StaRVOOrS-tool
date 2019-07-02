module CommonFunctions where

import Data.Char
import Data.List
import Data.List.Split
import Data.Either
import Types
import ErrM
import qualified Data.Map as Map
import Data.Maybe (fromJust)
import System.FilePath
import System.Directory
import Data.Functor
import Control.Lens hiding(Context,pre)
import Java.JavaLanguage

lookForEntryTrigger :: [TriggersInfo] -> MethodCN -> Scope -> [Trigger]
lookForEntryTrigger [] _ _                 = []
lookForEntryTrigger tinfs mnc (InFor (ForId id)) = 
 if isInfixOf "pinit" id
 then lookForEntryTrigger' tinfs mnc TopLevel
 else lookForEntryTrigger' tinfs mnc (InFor (ForId id))
lookForEntryTrigger tinfs mnc (InTemp xs)  = 
 case lookForEntryTrigger' tinfs mnc (InTemp xs) of 
      [] -> lookForEntryTrigger' tinfs mnc TopLevel
      ys -> ys
lookForEntryTrigger tinfs mnc scope = lookForEntryTrigger' tinfs mnc scope


lookForEntryTrigger' :: [TriggersInfo] -> MethodCN -> Scope -> [Trigger]
lookForEntryTrigger' [] _ _               = []
lookForEntryTrigger' (tinfo:es) mnc scope = 
 let mn = mnc ^. mname
     ci = mnc ^. clinf
     ov = mnc ^. overl
 in case (tiTrvar tinfo) of
        EVEntry -> if (mn == (tiMN tinfo) && ci == (tiCI tinfo) && cmpScope scope (tiScope tinfo)
                      && (cmpOverloading ov (tiOver tinfo) || ov == OverNil))
                   then (tiTN tinfo):lookForEntryTrigger' es mnc scope
                   else lookForEntryTrigger' es mnc scope
        _       -> lookForEntryTrigger' es mnc scope

cmpScope :: Scope -> Scope -> Bool
cmpScope (InFor (ForId id')) (InTemp id) = isInfixOf id id' 
cmpScope (InTemp id') (InFor (ForId id)) = cmpScope (InFor (ForId id)) (InTemp id')
cmpScope scope scope'                    = scope == scope'

cmpOverloading :: Overriding -> Overriding -> Bool
cmpOverloading ov ov' = ov == ov' || ov == OverNil

openingBracket :: String -> Bool
openingBracket "" = False
openingBracket s  = null (clean s) && elem '{' s

args2Str :: [Bind] -> String
args2Str []       = ""
args2Str (bn:bns) = case bn of
                         BindType t id -> t ++ " " ++ id ++ "," ++ args2Str bns
                         _ -> error "argst2Str: A trigger has a wrongly defined argument.\n"

getDuplicates :: Eq a => [a] -> [a]
getDuplicates []     = []
getDuplicates (x:xs) = if elem x xs 
                       then x:getDuplicates xs
                       else getDuplicates xs   

removeDuplicates :: Eq a => [a] -> [a]
removeDuplicates []     = []
removeDuplicates (x:xs) = if (elem x xs)
                          then removeDuplicates xs
                          else x:removeDuplicates xs

removeDuplicates' :: Eq a => [(a,a)] -> [(a,a)]
removeDuplicates' []            = []
removeDuplicates' (p@(xs,ys):xss) = 
 let zs = map fst xss
 in if (elem xs zs)
    then removeDuplicates' xss 
    else p:removeDuplicates' xss

getListOfTypesAndVars :: ClassInfo -> [(String, ClassInfo, JavaFilesInfo)] -> [(Modifier,Type, Id)]
getListOfTypesAndVars cl []                  = []
getListOfTypesAndVars cl ((main, cl',ts):xs) = if (cl == cl') 
                                               then varsInFiles ts
                                               else getListOfTypesAndVars cl xs

getListOfTypesAndMethods :: ClassInfo -> [(String, ClassInfo, JavaFilesInfo)] -> [(Type, Id,Modifier)]
getListOfTypesAndMethods cl []                  = []
getListOfTypesAndMethods cl ((main, cl',ts):xs) = 
 if (cl == cl') 
 then [(xy ^. _1, xy ^. _2, xy ^. _5) | xy <- methodsInFiles ts]
 else getListOfTypesAndMethods cl xs

getMethodInvocations :: MethodCN -> [(String, ClassInfo, JavaFilesInfo)] -> MethodInvocations
getMethodInvocations _ []                    = []
getMethodInvocations mnc ((main, cl',ts):xs) = 
 let mn  = mnc ^. mname
     cl  = mnc ^. clinf
     ov  = mnc ^. overl
 in if (cl == cl') 
    then let ys = [ val | val <- methodsInFiles ts, val ^. _2==mn]
         in if (not.null) ys
            then case ov of 
                 OverNil  -> (\x -> x ^. _4) $ head ys 
                 Over ovs -> let zs = [ y ^. _4 | y <- ys, map (head.words) (y ^. _3) == ovs]
                             in if null zs
                                then getMethodInvocations mnc xs
                                else head zs
            else getMethodInvocations mnc xs
    else getMethodInvocations mnc xs

getListOfArgs :: MethodName -> [(Type, Id,[String],MethodInvocations,Modifier)] -> [String]
getListOfArgs mn []                  = []
getListOfArgs mn ((t,mn',ts,_,_):xs) = if (mn == mn') 
                                       then ts
                                       else getListOfArgs mn xs

getConstTnv :: HT -> OldExprM -> Variables
getConstTnv c oldExpM = 
  if Map.null oldExpM 
  then []
  else case Map.lookup (c ^. htName) oldExpM of
            Nothing -> []
            Just xs -> let cn    = c ^. htName
                           vdec  = VarDecl cn VarInitNil
                           typE  = "Old_" ++ cn
                       in if null xs
                          then []
                          else [Var VarModifierNil typE [vdec]]

getOldExpr :: OldExprM -> HTName -> String
getOldExpr oldExpM cn = 
 case Map.lookup cn oldExpM of
      Nothing -> ""
      Just xs -> if null xs 
                 then ""
                 else "," ++ cn

getBindArgs' :: [Bind] -> String
getBindArgs' []                     = ""
getBindArgs' [BindType t id]        = t ++ " " ++ id
getBindArgs' ((BindType t id):y:ys) = t ++ " " ++ id ++ "," ++ getBindArgs' (y:ys)
getBindArgs' _                      = ""


getInfoTrigger :: [TriggersInfo] -> Trigger -> HT -> Maybe TriggersInfo
getInfoTrigger [] _ _          = Nothing
getInfoTrigger (tinfo:ts) tr c = 
 let mnc = _methodCN c
     cl  = mnc ^. clinf
     mn  = mnc ^. mname
     ov  = mnc ^. overl
 in if (tiTN tinfo == tr) && (tiCI tinfo == cl) && (tiMN tinfo == mn)
    then if (cmpOverloading ov (tiOver tinfo))
         then Just tinfo
         else getInfoTrigger ts tr c
    else getInfoTrigger ts tr c


getTriggerDef :: Overriding -> HT -> [TriggersInfo] -> TriggerDef 
getTriggerDef OverNil c xs = 
 let mnc = _methodCN c
     cl  = mnc ^. clinf
     tr  = mn ++ "_ppdex"
     mn  = mnc ^. mname
     xs'  = [ tiTrDef tinfo | tinfo <- xs, isInfixOf tr (tiTN tinfo), cl == (tiCI tinfo), tiTrDef tinfo /= Nothing ]
 in case xs' of
         []     -> error $ "Error: Problem when generating the exit trigger for the Hoare triple " ++ c ^. htName ++ ".\n"
         tdef:_ -> fromJust tdef
getTriggerDef (Over ts) c xs = 
 let mnc  = _methodCN c
     cl   = mnc ^. clinf
     tr   = mn ++ "_ppdex"
     mn   = mnc ^. mname
     xs'  = [ tiTrDef tinfo | tinfo <- xs, isInfixOf tr (tiTN tinfo), cl == (tiCI tinfo), tiTrDef tinfo /= Nothing, Over ts == tiOver tinfo ]
 in if length xs' == 1
    then case head xs' of
         Nothing   -> error $ "Error: Problem when generating the exit trigger for the Hoare triple " ++ c ^. htName ++ ".\n"
         Just tdef -> tdef
    else let xs'' = map fromJust xs'
         in case [ x | (ts',x) <- zip (map (map getBindType.getCTArgs.(^. compTrigger)) xs'') xs'', ts == ts'] of
                 []   -> error $ "Error: Problem when generating the exit trigger for the Hoare triple " ++ c ^. htName ++ ".\n"
                 x:xs -> x

lookfor :: [(Trigger, [String])] -> Trigger -> [String]
lookfor [] _     = []
lookfor (x:xs) e = if (fst x==e)
                   then snd x
                   else lookfor xs e

lookforClVar :: PropertyName -> [(PropertyName, ClassInfo, String)] -> String
lookforClVar pn []              = ""
lookforClVar pn ((pn',_,cl):xs) = if pn == pn'
                                  then cl
                                  else lookforClVar pn xs

flattenArgs :: [Args] -> String
flattenArgs []               = ""
flattenArgs [(Args t id)]    = t ++ " " ++ id
flattenArgs ((Args t id):xs) = t ++ " " ++ id ++ "," ++ flattenArgs xs

getImports :: Imports -> String
getImports []            = ""
getImports (Import s:xs) = "import " ++ s ++ ";\n" ++ getImports xs

filterRefTypes :: [Args] -> [Args]
filterRefTypes []         = []
filterRefTypes (arg:args) = 
 case getArgsType arg of
      "Action"     -> filterRefTypes args
      "Condition"  -> filterRefTypes args
      "Trigger"    -> filterRefTypes args
      "MethodName" -> filterRefTypes args
      "HTriple"    -> filterRefTypes args
      xs           -> if elem xs primitiveJavaTypes
                      then filterRefTypes args
                      else arg:filterRefTypes args

replaceWith :: String -> String -> String -> String
replaceWith pattern with s = 
 let xs = splitOnIdentifier pattern s
 in head xs ++ concat (map (with ++) (tail xs))

--Maps translated template scope in Date to the scope of the template in the ppDATE
normaliseScope :: Scope -> Scope
normaliseScope (InFor xs) = 
 if (isInfixOf "_cact" (show xs))
 then case splitOn "_cact" (show xs) of
           [] -> error $ "Error when normalising a scope " ++ show (InFor xs)
           ys -> InTemp (head ys)           
 else InFor xs
normaliseScope scope      = scope

-------------------------
-- Methods for parsing --
-------------------------

readIdentifier :: String -> Err (String, String)
readIdentifier text 
  | identifier == "" = fail "Error Parsing: Expecting identifier, but none was found.\n"
  | otherwise        = return (identifier, text')
  where
    (identifier, text') = break (\c -> c == '}' || c == '{') text

isIdentifierSymbol :: Char -> Bool
isIdentifierSymbol c = isAlphaNum c || c == '_'

clean :: String -> String
clean = dropWhile (\ c -> isSpace c || c == '{' || c == '}')

trim :: String -> String
trim = reverse . clean . reverse . clean

cleanBack :: String -> String
cleanBack = reverse . clean . reverse

splitAtIdentifier :: Char -> String -> (String, String)
splitAtIdentifier iden s = (takeWhile (\c -> not (c == iden)) s, dropWhile (\c -> not (c == iden)) s)

splitAtClosingParen :: Int -> String -> (String, String)
splitAtClosingParen _ ""       = ("","")
splitAtClosingParen n ('(':xs) = 
 let (a,b) = splitAtClosingParen (n+1) xs
 in ('(':a,b)
splitAtClosingParen n (')':xs) = 
 if n > 0
 then let (a,b) = splitAtClosingParen (n-1) xs
      in (')':a,b)
 else ("",xs)
splitAtClosingParen n (x:xs) = 
 let (a,b) = splitAtClosingParen n xs
 in (x:a,b)

splitOnIdentifier :: String -> String -> [String]
splitOnIdentifier = splitOn

checkIfParseErrors :: [Either a b] -> Either [a] [b]
checkIfParseErrors es = let (ls, rs) = partitionEithers es
                        in if ((not.null) ls)
                           then Left ls
                           else Right rs

addComma :: [String] -> String
addComma = intercalate ","

---------------------------------------
-- Manipulating the parsed .xml file --
---------------------------------------

removeNoneHTs :: [Proof] -> [HTName] -> [Proof]
removeNoneHTs [] _       = []
removeNoneHTs (p:ps) cns = let cn = getHTNameErrConst (contractText p) (typee p) in
                                 if ((cn /= "") && elem cn cns)
                                 then p:removeNoneHTs ps cns
                                 else removeNoneHTs ps cns


getInfoFromProof :: Proof -> (MethodName, HTName, [String],String)
getInfoFromProof proof = let mn    = getMethodName' (target proof)
                             path  = typee proof
                             cn    = getHTNameErrConst (contractText proof) (typee proof)
                             npres = getNewPreConds (executionPath proof)
                             aoft  = length $ filter (=="true") npres
                         in if (aoft >= 1)
                            then if (aoft == 1) 
                                 then if (length npres == 1)
                                      then (mn, cn, npres,path) -- KeY has nothing to say about the proof
                                      else (mn, cn, filter (not.(=="true")) npres,path)
                                 else if (aoft == length npres)
                                      then (mn, cn, ["true"],path) -- KeY has nothing to say about the proof
                                      else (mn, cn, filter (not.(=="true")) npres,path)
                            else (mn, cn, npres,path)

getMethodName' :: Target -> MethodName
getMethodName' t = fst $ splitAtIdentifier '(' t                   

getHTNameErrConst :: ContractText -> Type -> HTName
getHTNameErrConst ctext t = let (_, xs) = splitAtIdentifier ':' ctext
                                ys      = splitOnIdentifier t (tail xs)
                            in if (length ys == 1)
                               then ""
                               else trim $ fst $ splitAtIdentifier '=' $ (tail.head.tail) ys

getHTNameErrVar :: ContractText -> HTName
getHTNameErrVar ctext = 
 let (_, xs) = splitAtIdentifier ':' ctext
     (_, ys) = splitAtIdentifier '.' $ tail xs
 in if (null ys)
    then ""
    else let (cn, _) = splitAtIdentifier '=' $ tail ys 
         in trim cn

getNewPreConds :: [EPath] -> [String]
getNewPreConds []       = []
getNewPreConds (ep:eps) = if (verified ep == "false") 
                          then pathCondition ep:getNewPreConds eps
                          else getNewPreConds eps

introduceOr :: [String] -> String
introduceOr [x]    = x
introduceOr (x:xs) = x ++ " || " ++ introduceOr xs

getTriggersFors :: Foreaches -> Triggers
getTriggersFors []     = []
getTriggersFors (f:fs) = getTriggersCtxt (f ^. getCtxtForeach) ++ getTriggersFors fs

getTriggersCtxt :: Context -> Triggers
getTriggersCtxt ctxt = ctxt ^. triggers ++ getTriggersFors (ctxt ^. foreaches)


makeAddFile :: Import -> IO (String, ClassInfo)
makeAddFile (Import s) = let xs = splitOnIdentifier "." s
                         in if (length xs == 1)
                            then return ("", head xs)
                            else let val = last xs
                                     ys = (init $ foldr (\ xs xss -> xs ++ "/" ++ xss) "" (init xs))
                                 in return (ys, val)

--------------------------------------------------------------
-- Copy all the files within a Directory to a new directory --
--------------------------------------------------------------

copyFiles source dest =
 do
    createDirectoryIfMissing True dest
    subItems <- getSubitems' source
    mapM_ (copyItem' source dest) subItems


getSubitems' :: FilePath -> IO [(Bool, FilePath)]
getSubitems' path = getSubitemsRec ""
  where
    getChildren path =  (\\ [".", ".."]) <$> getDirectoryContents path

    getSubitemsRec relPath = do
        let absPath = path </> relPath
        isDir <- doesDirectoryExist absPath
        children <- if isDir then getChildren absPath else return []
        let relChildren = [relPath </> p | p <- children]
        ((isDir, relPath) :) . concat <$> mapM getSubitemsRec relChildren

copyItem' baseSourcePath baseTargetPath (isDir, relativePath) =
 do
    let sourcePath = baseSourcePath </> relativePath
    let targetPath = baseTargetPath </> relativePath
    if isDir
    then createDirectoryIfMissing False targetPath
    else copyFile sourcePath targetPath

