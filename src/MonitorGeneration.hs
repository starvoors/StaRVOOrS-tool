module MonitorGeneration(monitorGen) where 

import Types
import UpgradePPDATE
import qualified System.IO
import System.Process
import CommonFunctions
import Translators.Translator2DATE

------------------------------------
-- Monitor generation using LARVA --
------------------------------------

monitorGen :: FilePath -> Filename -> UpgradePPD PPDATE -> Flags -> IO ()
monitorGen output_addr ppdate_fn ppdate flags = 
 do putStrLn "Initiating monitor files generation."
    let output_add' = output_addr ++ "out"
    let larva_fn  = generateLarvaFileName ppdate_fn
    let larva_add = output_addr ++ "out/" ++ larva_fn
    writeFile larva_add ""
    translate ppdate larva_add
    putStrLn "Running LARVA..."
    let verbose = if elem NoneVerbose flags then "" else "-v"
    let distributed = if elem Distributed flags then "-d" else ""
    expath <- getExecutableDir
    rawSystem "java" ["-jar",expath++"/larva.jar",larva_add,verbose,distributed,"-o",output_add']
    putStrLn "Monitor files generation completed."


generateLarvaFileName :: Filename -> Filename
generateLarvaFileName fn = 
 let (ext, _:name) = break ('.' ==) $ reverse fn 
     xs = splitOnIdentifier "/" name     
 in if (length xs == 1)
    then reverse name ++ ".lrv"
    else reverse (head xs) ++ ".lrv"
