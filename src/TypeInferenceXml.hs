module TypeInferenceXml(inferTypesOldExprs) where

import Types
import Text.XML.HaXml hiding(path,Modifier)
import Text.XML.HaXml.Parse
import Text.XML.HaXml.Posn
import CommonFunctions
import UpgradePPDATE
import System.Directory
import System.Environment
import System.Process
import System.FilePath
import qualified Data.Map as Map
import Data.List
import Control.Lens hiding(Context,pre)


inferTypesOldExprs :: UpgradePPD PPDATE -> FilePath -> FilePath -> IO (Map.Map HTName [(String,Type)])
inferTypesOldExprs ppd jpath output_add = 
 let ppdate  = getValue ppd
     env     = getEnvVal ppd
     toXml   = generateOldExpr (_htsGet ppdate) jpath
 in if null toXml
    then return Map.empty
    else let jinfo   = javaFilesInfo env
             types   = removeDuplicates [(c ^. classInf, getTypes (c ^. classInf) jinfo) | c <- toXml]
             toXml'  = map (\oexpr -> addType oexpr types jinfo) toXml
             xml_add = output_add ++ "tmp.xml"
         in if (null [y | x <- toXml', y <- x ^. oldExprs, inferType y == ""])
            then do let oldExpTypes = foldr (\x xs -> Map.insert (x ^. htID) (map toTuple $ x ^. oldExprs) xs) Map.empty toXml'
                    generateXmlFile toXml' jpath xml_add
                    return oldExpTypes
            else do generateXmlFile toXml' jpath xml_add
                    javaExprReader xml_add output_add
                    let new_xml_add = output_add ++ "tmp2.xml"
                    oldExpsJER <- parse new_xml_add
                    let oldExpTypes = foldr (\x xs -> Map.insert (x ^. htID) (map toTuple $ x ^. oldExprs) xs) Map.empty oldExpsJER
                    return oldExpTypes
                       where getTypes c jinfo    = filterMod $ getListOfTypesAndVars c jinfo ++ getListOfTypesAndMethods c jinfo
                             toTuple (OExpr e t) = (e,t)
                             filterMod           = map (\ val -> (val ^. _2,val ^. _3))


--------------------
-- Type inference --
--------------------

--Runs the API which infers the types of \old expressions
javaExprReader xml_add out_add = 
 do expath <- getExecutableDir
    rawSystem "java" ["-jar",expath++"/jer.jar",xml_add, out_add]

addType :: OldExpr -> [(ClassInfo,[(Type,String)])] -> [(String, ClassInfo, JavaFilesInfo)] -> OldExpr
addType oexpr ts minfs = oldExprs %~ map (\(OExpr e t) -> OExpr e (checkType ts minfs oexpr e)) $ oexpr

checkType :: [(ClassInfo,[(Type,String)])] -> [(String, ClassInfo, JavaFilesInfo)] -> OldExpr -> String -> String
checkType xs ys oexpr s = 
 let cinf = oexpr ^. classInf
 in if (checkTypeArgs ys oexpr s == "") 
    then checkTypeClass xs cinf s
    else checkTypeArgs ys oexpr s

checkTypeArgs :: [(String, ClassInfo, JavaFilesInfo)] -> OldExpr -> String -> String
checkTypeArgs [] _ s                   = ""
checkTypeArgs ((_,cinf,ys):xs) oexpr s = 
 let cinf'  = oexpr ^. classInf
     mn     = oexpr ^. methoD
     mfiles = methodsInFiles ys
 in if cinf' == cinf
    then if (null $ getListOfArgs mn mfiles)
         then ""
         else let zs = [ t | [t,s'] <- map words $ getListOfArgs mn mfiles, s' == s]
              in if null zs
                 then ""
                 else head zs
    else checkTypeArgs xs oexpr s

checkTypeClass :: [(ClassInfo,[(Type,String)])] -> ClassInfo -> String -> Type
checkTypeClass [] cn s             = ""
checkTypeClass ((cn',ts):xss) cn s = 
 if (cn == cn')
 then let ys = [ t | (t,s') <- ts, s == s' || isPrefixOf (s'++"(") s]
      in if null ys 
         then ""
         else head ys
 else checkTypeClass xss cn s

-------------------------
-- Generating XML file --
-------------------------

generateXmlFile :: [OldExpr] -> FilePath -> FilePath -> IO ()
generateXmlFile xs jpath output_add = 
 do writeFile output_add "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    appendFile output_add "<result>\n"
    appendFile output_add (concat $ map oldExpr2Xml xs)
    appendFile output_add "</result>" 


oldExpr2Xml :: OldExpr -> String
oldExpr2Xml oldExpr = 
 let xs = map oExpr2Xml (oldExpr ^. oldExprs) in
 twoSpaces ++ "<contract Id=" ++ "\"" ++ oldExpr ^. htID ++ "\"" 
 ++ " class=" ++ "\"" ++ oldExpr ^. classInf ++ "\"\n" 
 ++ " path=" ++ "\"" ++ oldExpr ^. path ++ "\"\n" 
 ++ " target=" ++ "\"" ++ oldExpr ^. targ ++ "\""
 ++ " method=" ++ "\"" ++ oldExpr ^. methoD ++ "\">\n" 
 ++ concat xs
 ++ twoSpaces ++ "</contract>\n\n"
 

oExpr2Xml :: OExpr -> String
oExpr2Xml oexpr = 
 fourSpaces ++"<oldExpr expr=" ++ "\"" ++ expr oexpr ++ "\"" 
 ++ " type=" ++ "\"" ++ inferType oexpr ++ "\">\n" 
 ++ fourSpaces ++ "</oldExpr>\n\n"


generateOldExpr :: HTriples -> FilePath ->  [OldExpr]
generateOldExpr [] _         = []
generateOldExpr (c:cs) jpath = 
 let cn     = c ^. htName
     p      = c ^. post
     classI = _methodCN c ^. clinf
     path   = jpath
     tar    = c ^. path2it
     mn     = _methodCN c ^. mname
     xs     = splitOnIdentifier "\\old(" p
 in if (length xs == 1)
    then generateOldExpr cs jpath
    else let ys    = tail xs
             zs    = removeDuplicates $ map (trim . fst . (splitAtClosingParen 0)) ys
             xs'   = foldr (\x xs -> (OExpr x ""):xs) [] zs
         in (OldExpr cn classI tar path mn xs'):generateOldExpr cs jpath

twoSpaces :: String
twoSpaces = "  "

fourSpaces :: String
fourSpaces = "    "

----------------------
-- Reading XML file --
----------------------

parse :: XML -> IO [OldExpr]
parse xml_fn = 
  do r <- readFile xml_fn
     let xml = xmlParse "(No Document)" r
     let (Document _ _ root _) = xml
     let rootElem = CElem root noPos
     let xs = (tag "result" /> tag "contract" $ rootElem)
     let ys = map (tag "contract" /> tag "oldExpr") xs
     let oldExpr_info = map getHTInfo xs
     let oldExpr_expr = map (map getExpr) ys
     let oldExpr_type = map (map getType) ys
     let components   = zip oldExpr_expr oldExpr_type
     let oldExpr      = map (foldr (\p xs -> (makeOldExpr p):xs) [].(\(x, y) -> zip x y)) components
     let proof        = foldr foo [] $ zip oldExpr_info oldExpr
     return proof
          where foo (x,oexpr) xs  = (OldExpr { _htID     = x ^. _1
                                             , _classInf = x ^. _4 
                                             , _path     = fifth x
                                             , _methoD   = x ^. _2
                                             , _targ     = x ^. _3
                                             , _oldExprs = oexpr
                                             }) : xs
                fifth (_,_,_,_,u) = u

getHTInfo :: Content i -> (ContractId, ClassInfo, Target,Type, FilePath)
getHTInfo (CElem (Elem name as _) _) =
  if (getFromQN name == "contract")
  then let cid  = lookForVal "Id" as
           cinf = lookForVal "class" as
           mn   = lookForVal "method" as 
           tar  = lookForVal "target" as
           fp   = lookForVal "path" as  
       in (cid, mn, tar,cinf,fp)
  else ("","","","","")


getExpr :: Content i -> String
getExpr (CElem (Elem name attributes _) _) =
  if (getFromQN name == "oldExpr")
  then lookForVal "expr" attributes
  else ""

getType :: Content i -> String
getType (CElem (Elem name attributes _) _) = 
  if (getFromQN name == "oldExpr")
  then lookForVal "type" attributes
  else ""


getFromQN :: QName -> Name
getFromQN (N s) = s 

lookForVal :: String -> [Attribute] -> String
lookForVal s []             = ""
lookForVal s ((an, ref):as) = if (getFromQN an == s) 
                              then show ref
                              else lookForVal s as

makeOldExpr :: (String, String) -> OExpr
makeOldExpr (a, b) = OExpr a b
