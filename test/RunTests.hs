{-# LANGUAGE TemplateHaskell #-}

module Main where

import System.Directory
import System.Environment as SE
import System.Console.GetOpt
import Control.Monad.Writer
import System.Process
import Control.Lens hiding(Context)
import TestSuite
import Data.List.Split


main :: IO ()
main =
 do args <- SE.getArgs    
    case getOpt Permute [] args of
      ([],[starvoors_add,test],[]) -> run starvoors_add test
      (_,_,[]) -> do name <- getProgName
                     putStrLn ("Usage: " ++ name ++ " <starvoors_bin_add> <test_name>")
      (_,_,errs) -> sequence_ $ map putStrLn errs

run :: FilePath -> String -> IO ()
run starvoors_add test =  
 do putStrLn $ "\nStaRVOOrS Test Suite\n"
    current_dir <- getCurrentDirectory
    bin    <- checkFile starvoors_add
    source <- checkDirectory current_dir "CoffeeBrew"
    specs  <- checkDirectory current_dir "Specs"
    let base = appendWriter specs (appendWriter bin source)
    case runWriter base of
     (b,s) ->
      if not b 
      then putStrLn s
      else if (elem test (map (^. name) testSuite) || test == "all")
           then runTest starvoors_add current_dir test
           else putStrLn $ "Error: Test '" ++ test ++ "' does not exist." 

---------------
-- Runs test --
---------------

runTest :: FilePath -> FilePath -> String -> IO ()
runTest starvoors_add current_dir test = 
 case test of 
      "all"     -> sequence_ $ map (runTest starvoors_add current_dir) (map (^. specification) testSuite)
      _         -> runChecks starvoors_add current_dir (getTest test)

runChecks :: FilePath -> FilePath -> Test -> IO ()
runChecks starvoors_add current_dir test = 
 do let out    = current_dir ++ "/Test_" ++ test ^. name
    test2run (test ^. name) 
    checkOutputDirectory out
    createDirectoryIfMissing False out
    testSpec starvoors_add current_dir test
    testTranslation starvoors_add current_dir test
    testPPDRefinement starvoors_add current_dir test
    testMonitorExec starvoors_add current_dir test

getTest :: String -> Test
getTest test = head [ t | t <- testSuite, t ^. name == test]

test2run :: String -> IO ()
test2run test  = 
 do putStrLn $ "***************" ++ stars test ++ "*"
    putStrLn $ "* Running test " ++ test ++ " *"
    putStrLn $ "***************" ++ stars test ++ "*\n"

stars :: String -> String
stars test = ['*' | _ <- [0..length test]]

---
-- Checks
---

testSpec :: FilePath -> FilePath -> Test -> IO ()
testSpec starvoors_add current_dir test =
 if test ^. parsing == Yes
 then do let spec = current_dir ++ "/Specs/" ++ test ^. specification
         putStrLn "*** Testing the parsing of the specification\n"
         rawSystem starvoors_add ["-p",spec] --Only parsing mode
         return ()
 else putStrLn "*** Not testing the parsing of the specification\n"

testTranslation :: FilePath -> FilePath -> Test -> IO ()
testTranslation starvoors_add current_dir test = 
 if test ^. translation == Yes
 then do putStrLn "*** Testing the translation of the specification\n"
         runStarvoors starvoors_add current_dir test
         let file1 = current_dir ++ "/Test_" ++ test ^. name ++ "/out/" 
                     ++ generateLarvaFileName (test ^. specification)
         let file2 = current_dir ++ "/ExpOut/Test_" ++ test ^. name ++ "/" 
                     ++ generateLarvaFileName (test ^. specification)
         b <- fileComparison current_dir test file1 file2
         if b
         then putStrLn "* Check was succesfull.\n"
         else putStrLn "* Check has failed.\n"
 else putStrLn "*** Not testing the translation of the specification\n"

testPPDRefinement :: FilePath -> FilePath -> Test -> IO ()
testPPDRefinement starvoors_add current_dir test = 
 if test ^. ppdRefinement == Yes
 then do putStrLn "*** Testing the refinement of the specification\n"
         runStarvoors starvoors_add current_dir test
         let file1 = current_dir ++ "/Test_" ++ test ^. name ++ "/out/" 
                     ++ generateRefinementFileName (test ^. specification)
         let file2 = current_dir ++ "/ExpOut/Test_" ++ test ^. name ++ "/" 
                     ++ generateRefinementFileName (test ^. specification)
         b <- fileComparison current_dir test file1 file2
         if b
         then putStrLn "* Check was succesfull.\n"
         else putStrLn "* Check has failed.\n"
 else putStrLn "*** Not testing the refinement of the specification\n"

testMonitorExec :: FilePath -> FilePath -> Test -> IO ()
testMonitorExec starvoors_add current_dir test = 
 if fst (test ^. monitorExec) == Yes
 then do putStrLn "***  Testing the monitor generated from the translation\n"
         runStarvoors starvoors_add current_dir test
         let mainfile     = mainFile $ snd (test ^. monitorExec)
         let mainfile_add = current_dir ++ "/Test_" ++ test ^. name ++ "/out/CoffeeBrew/main/Main.java"
         let out          = current_dir ++ "/Test_" ++ test ^. name ++ "/out"
         writeFile mainfile_add mainfile
         analyseMonitor current_dir test
         putStrLn $ "* Check the log file generated by the monitor in " ++ current_dir ++ "/Test_" 
                    ++ test ^. name ++ "/out" ++ ", to analyse whether the monitor behave as expected."
 else putStrLn "*** Not testing the refinement of the specification\n"

-------------------------
-- Auxiliary Functions --
-------------------------

runStarvoors :: FilePath -> FilePath -> Test -> IO ()
runStarvoors starvoors_add current_dir test = 
 do b <- doesDirectoryExist (current_dir ++ "/Test_" ++ test ^. name ++ "/out")
    if not b
    then do let spec   = current_dir ++ "/Specs/" ++ test ^. specification
            let source = current_dir ++ "/CoffeeBrew"
            let out    = current_dir ++ "/Test_" ++ test ^. name
            putStrLn "* Running StaRVOOrS."
            rawSystem starvoors_add [source,spec,out]
            return ()
    else do putStrLn "* Using previous run of StaRVOOrS for this check.\n"
            return ()

analyseMonitor :: FilePath -> Test -> IO ()
analyseMonitor current_dir test =
 do let source  = current_dir ++ "/Test_" ++ test ^. name ++ "/out/CoffeeBrew/"
    let ppartif = current_dir ++ "/Test_" ++ test ^. name ++ "/out/ppArtifacts/"
    let larva   = current_dir ++ "/Test_" ++ test ^. name ++ "/out/larva/"
    let bin     = current_dir ++ "/Test_" ++ test ^. name ++ "/out/bin"
    let aspects = current_dir ++ "/Test_" ++ test ^. name ++ "/out/aspects/"
    checkOutputDirectory bin
    createDirectoryIfMissing False bin
    putStrLn "* Compiling and running java files.\n"
    system $ "cd " ++ current_dir ++ "/Test_" ++ test ^. name
             ++ " ; javac $(find " ++ source ++ " -name *.java)" 
             ++ " $(find " ++ ppartif ++ " -name *.java)"
             ++ " $(find " ++ larva ++ " -name *.java) -d " ++ bin
             ++ " ; jar cfe test.jar main.Main -C " ++ bin ++ " ."
             ++ " ; ajc -1.5 -sourceroots " ++ aspects ++ " -inpath test.jar -outjar test_asp.jar"
             ++ " ; aj5 -jar test_asp.jar"
    return ()

fileComparison :: FilePath -> Test -> FilePath -> FilePath -> IO Bool
fileComparison current_dir test file1 file2 = 
 do b <- doesDirectoryExist (current_dir ++ "/ExpOut/Test_" ++ test ^. name)
    if not b 
    then do putStrLn $ "* There are not expected output files for test " ++ test ^. name
                       ++ " in " ++ current_dir ++ "/ExpOut.\n"
            return False
    else do f1 <- checkFile file1
            f2 <- checkFile file2
            let fs = appendWriter f1 f2
            case runWriter fs of
               (b,s) -> if b  
                        then liftM2 (==) (readFile file1) (readFile file2)
                        else do putStrLn s
                                return False

checkOutputDirectory :: FilePath -> IO ()
checkOutputDirectory file = 
 do b <- doesDirectoryExist file
    if b then removeDirectoryRecursive file
         else return ()

appendWriter :: Writer String Bool -> Writer String Bool -> Writer String Bool
appendWriter wr wr' =
 case (runWriter wr,runWriter wr') of 
      ((b,s),(b',s')) -> writer (b&&b',s++s')

--Checks if a given file exists
checkFile :: FilePath -> IO (Writer String Bool)
checkFile add = 
 do b <- doesFileExist add
    if b 
    then return $ writer (b,"") 
    else return $ writer (False,"Error: File " ++ add ++ " does not exist.\n")

--Checks if a given directory exists
checkDirectory :: FilePath -> String -> IO (Writer String Bool)
checkDirectory add s = 
 do b <- doesDirectoryExist (add ++ "/" ++ s)
    if b 
    then return $ writer (b,"") 
    else return $ writer (False,"Error: Cannot find folder " ++ s ++ " in " ++ add ++ ".\n")

generateLarvaFileName :: String -> String
generateLarvaFileName fn = 
 let (ext, _:name) = break ('.' ==) $ reverse fn 
     xs = splitOn "/" name     
 in if (length xs == 1)
    then reverse name ++ ".lrv"
    else reverse (head xs) ++ ".lrv"

generateRefinementFileName :: String -> String
generateRefinementFileName fn = 
 let (ext, _:name) = break ('.' ==) $ reverse fn 
     xs = splitOn "/" name     
 in if (length xs == 1)
    then reverse name ++ "_optimised.ppd"
    else reverse (head xs) ++ "_optimised.ppd"

mainFile :: Program -> String
mainFile prog = 
 "package main;\n\n"
 ++ "public class Main {\n\n"
 ++ "    public static void main(String[] args) throws Exception {\n"
 ++ concatMap (\ xs -> "        " ++ xs) prog
 ++ "    }\n"
 ++ "}"
