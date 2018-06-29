module StaticAnalysis(staticAnalysis) where

import Types
import CommonFunctions
import System.Directory
import System.Process
import JML.JMLInjection
import ParserXMLKeYOut
import ReportGen
import UpgradePPDATE
import System.Exit
import Control.Lens hiding(Context,pre)

-------------------------------
-- Static Analysis using KeY --
-------------------------------

staticAnalysis :: FilePath -> UpgradePPD PPDATE -> FilePath -> [Flag] -> IO (Either [Proof] [Proof])
staticAnalysis jpath ppd output_add flags =
 let ppdate      = getValue ppd
     consts      = ppdate ^. htsGet
 in if elem OnlyRV flags
    then do putStrLn "StaRVOOrS is ran in only runtime verification mode.\n"
            return $ Right []
    else if (null consts)
         then do putStrLn "\nThere are no Hoare triples to analyse."
                 return $ Left []
         else do putStrLn "Initiating static verification of Hoare triples with KeY."
                 runAnalysis jpath ppd output_add flags

runAnalysis :: FilePath -> UpgradePPD PPDATE -> FilePath -> Flags -> IO (Either [Proof] [Proof])
runAnalysis jpath ppd output_addr flags =
 let toAnalyse_add = output_addr ++ "workspace/files2analyse"
     ppdate        = getValue ppd
     consts        = ppdate ^. htsGet
 in do injectJMLannotations ppd jpath output_addr
       runKeY toAnalyse_add output_addr flags
       let xml_add = output_addr ++ "out.xml"
       b <- doesFileExist xml_add
       if b
       then do xml_to_parse <- readFile xml_add
               let xml     = ParserXMLKeYOut.parse xml_to_parse
               let cns     = getHTNamesEnv ppd
               let xml'    = removeNoneHTs xml cns
               if (not (elem XML flags)) then removeFile xml_add else return ()
               generateReport xml' output_addr
               return $ Right xml'
       else do generateReportFailure output_addr flags
               return $ Right []

-------------
-- Run KeY --
-------------

runKeY :: FilePath -> FilePath -> [Flag] -> IO ExitCode
runKeY output_add' output_addr flags = 
 if elem OnlyRV flags
 then return ExitSuccess
 else rawSystem "java" ["-jar","key.starvoors.jar","-starvoors",output_add', output_addr]

