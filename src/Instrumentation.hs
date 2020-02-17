module Instrumentation (methodsInstrumentation) where

import Types
import CommonFunctions
import Java.JavaParser
import System.Directory
import UpgradePPDATE
import ErrM
import Java.JavaLanguage
import Control.Lens hiding(Context,pre)
import System.Directory
import Control.Lens
import Data.List

--------------------------
-- Code Instrumentation --
--------------------------

-- creates new files with methods instrumented
methodsInstrumentation :: UpgradePPD PPDATE -> FilePath -> FilePath -> [Flag] -> IO ()
methodsInstrumentation ppd jpath output_add flags =
 do let (ppdate, env) = fromOK $ runStateT ppd emptyEnv
    let consts        = ppdate ^. htsGet
    if (null consts)
    then return ()
    else methodsInstrumentation' ppd jpath output_add (elem OnlyRV flags)

methodsInstrumentation' :: UpgradePPD PPDATE -> FilePath -> FilePath -> Bool -> IO ()
methodsInstrumentation' ppd jpath output_add flagRV =
  do let (ppdate, env) = fromOK $ runStateT ppd emptyEnv
     let consts        = ppdate ^. htsGet
     let imp           = ppdate ^. importsGet
     sequence [ instrumentFile i consts jpath output_add flagRV
              | i <- imp, not (elem ((\ (Import s) -> s) i) importsInKeY)
              ]
     putStrLn "Java files generation completed."


instrumentFile :: Import -> HTriples -> FilePath -> FilePath -> Bool -> IO ()
instrumentFile i consts jpath output_add flagRV =
 do (main, cl) <- makeAddFile i
    let file_add = jpath ++ main ++ "/" ++ (cl ++ ".java")
    b <- doesFileExist file_add
    if b   
    then do r <- readFile file_add
            let java = (\(Right x) -> x) $ parseJavaFile r
            let mns  = removeDuplicates $ getMethodsNames cl consts
            let java_aux = lookForCTD cl $ map getClassDecls $ getClassTypeDecls java
            let decls  = (getDecls.getClassBody) java_aux
            let decls' = instrumentMethodMemberDecl decls (zip mns [0..length mns-1])
            let output_add' = output_add ++ main
            let r'  = unlines $ addInstrumentedMethodsInFile (lines r) decls'
            let r'' = addNewImportInfo r' decls' cl (map fst mns)
            createDirectoryIfMissing True output_add'
            writeFile (output_add' ++ "/" ++ (cl ++ ".java")) r''
    else if flagRV
         then return ()
         else error $ "StaRVOOrS: The file " ++ file_add ++ " does not exist.\n"

addNewImportInfo :: String -> [(String,String,String,Overriding)] -> ClassInfo -> [MethodName] -> String
addNewImportInfo s [] _ _       = s
addNewImportInfo s (_:_) cl mns =
  let xs = splitOnIdentifier "package" (clean s)
      ys = map (\ (x,y) -> x ++ show y) $ zip mns [0..length mns-1]
  in if (length xs == 1)
     then let s'    = lines s
          in unlines $ addFidDec (lines s) cl ys
     else let s'    = lines ((head.tail) xs)
              begin = (head xs) ++ "package" ++ (head s') ++ "\n"
          in begin ++ "\nimport ppArtifacts.IdHT;\n" ++ unlines (addFidDec (tail s') cl ys)

addFidDec :: [String] -> ClassInfo -> [MethodName] -> [String]
addFidDec [] _ _          = []
addFidDec (xs:xss) cl mns = 
 if (clean xs == "")
 then xs:addFidDec xss cl mns
 else let ys = splitOnIdentifier ("class " ++ cl) xs
      in if (length ys == 1)
         then xs:addFidDec xss cl mns
         else xs:addFidDec' xss mns

addFidDec' :: [String] -> [MethodName] -> [String]
addFidDec' [] _         = []
addFidDec' (xs:xss) mns = 
 if (clean xs == "")
 then let fids  = concatMap (genFid.("fid_"++)) mns 
          fids' = fids ++ genFid "objPPD"
      in (xs ++ fids'):xss 
 else xs:addFidDec' xss mns

genFid :: String -> String
genFid fid = "\n  public IdHT " ++ fid ++ " = new IdHT();\n"

-- Added due to bug in the java library
addInstrumentedMethodsInFile :: [String] -> [(String, String, String,Overriding)] -> [String]
addInstrumentedMethodsInFile xss []     = xss
addInstrumentedMethodsInFile xss (y:ys) = addInstrumentedMethodsInFile (addMethodInFile y xss) ys

-- Added due to bug in the java library
addMethodInFile :: (String,String,String,Overriding) -> [String] -> [String]
addMethodInFile _ []                                = []
addMethodInFile (id,methodaux,method,over) (xs:xss) = 
 let ys = splitOnIdentifier id xs
 in if (length ys == 1)
    then xs:addMethodInFile (id,methodaux,method,over) xss
    else let zs     = (clean.head.tail) ys 
             beginl = (words.head) ys 
         in if ((head zs) == '(')
            then if (length beginl == 1)
                 then xs:addMethodInFile (id,methodaux,method,over) xss
                 else let ws = (clean.head) beginl in
                      if (elem ws javaModifiers)
                      then if over == OverNil
                           then if ((clean $ fst $ break (=='{') $ reverse xs) == "")
                                then (methodaux ++ "\n"):method:xss
                                else (methodaux ++ "\n"):(head $ lines method):xss
                           else if checkOverArgs zs over
                                then if ((clean $ fst $ break (=='{') $ reverse xs) == "")
                                     then (methodaux ++ "\n"):method:xss
                                     else (methodaux ++ "\n"):(head $ lines method):xss
                                else xs:addMethodInFile (id,methodaux,method,over) xss
                      else xs:addMethodInFile (id,methodaux,method,over) xss
            else xs:addMethodInFile (id,methodaux,method,over) xss

checkOverArgs :: String -> Overriding -> Bool
checkOverArgs xs over = 
 let zs = clean $ fst $ break (==')') (tail xs)
     ys = splitOnIdentifier "," zs
 in if (length ys == 1)
    then if null (head ys) 
         then null (getOverr over)
         else if null (getOverr over)
              then False
              else if length (getOverr over) == length ys
                   then (head.words.head) ys == (head.getOverr) over
                   else False
    else if (null (getOverr over))
         then False
         else getOverr over == map (head.words.clean) ys
                           where getOverr (Over xs) = xs
