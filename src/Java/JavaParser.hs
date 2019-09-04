module Java.JavaParser where 

import qualified Types as T
import Language.Java.Parser
import Language.Java.Syntax
import Language.Java.Pretty
import Language.Java.Lexer
import Data.Maybe (fromJust,isJust)
import Control.Lens hiding(Context,pre) 
import Java.JavaLanguage

---------------------------------------
-- Manipulation of parsed java files --
---------------------------------------

--receives the content of a Java file as a string
parseJavaFile = parser compilationUnit

updateDecls :: CompilationUnit -> T.ClassInfo -> [Decl] -> CompilationUnit
updateDecls (CompilationUnit a b c) cl decls = 
 let f = ClassTypeDecl . (\x -> updateClassDecl cl x decls) . getClassDecls
 in CompilationUnit a b (map f c)

getClassTypeDecls :: CompilationUnit -> [TypeDecl]
getClassTypeDecls (CompilationUnit _ _ xs) = xs

getClassDecls :: TypeDecl -> ClassDecl
getClassDecls (ClassTypeDecl cd) = cd

updateClassDecl :: T.ClassInfo -> ClassDecl -> [Decl] -> ClassDecl
updateClassDecl cl cd@(ClassDecl _ id _ _ _ _) decls = if (cl == prettyPrint id) 
                                                       then updateClassBody cd (ClassBody decls) 
                                                       else cd
 

lookForCTD :: T.ClassInfo -> [ClassDecl] -> ClassDecl
lookForCTD _  []       = error $ "Missmatch between file name and class name.\n"
lookForCTD cl (cd:cds) = case cd of 
                              ClassDecl _ id _ _ _ _ -> if (cl == prettyPrint id) 
                                                        then cd 
                                                        else lookForCTD cl cds
                              _                      -> lookForCTD cl cds

getClassBody :: ClassDecl -> ClassBody
getClassBody (ClassDecl _ _ _ _ _ cbody) = cbody

updateClassBody :: ClassDecl -> ClassBody -> ClassDecl
updateClassBody (ClassDecl a b c d e cbody) cbody' = ClassDecl a b c d e cbody'

getDecls :: ClassBody -> [Decl]
getDecls (ClassBody decls) = decls

getMemberDecl :: [Decl] -> [Decl]
getMemberDecl []     = []
getMemberDecl (d:ds) = case d of
                         MemberDecl _ -> d:getMemberDecl ds
                         _            -> getMemberDecl ds

getVarDecl' :: [Decl] -> [MemberDecl]
getVarDecl' []     = []
getVarDecl' (d:ds) = case d of
                         MemberDecl md -> case md of 
                                              FieldDecl _ _ _ -> md:getVarDecl' ds
                                              _               -> getVarDecl' ds
                         _             -> getVarDecl' ds

getMethodDecl :: [Decl] -> [MemberDecl]
getMethodDecl []     = []
getMethodDecl (d:ds) = 
 case d of
      MemberDecl md -> case md of 
               MethodDecl _ _ _ _ _ _ _ -> md:getMethodDecl ds
               _                        -> getMethodDecl ds
      _             -> getMethodDecl ds

getMethodDeclId :: [Decl] -> [String]
getMethodDeclId []     = []
getMethodDeclId (d:ds) = 
 case d of
      MemberDecl md -> case md of 
               MethodDecl _ _ _ (Ident id) _ _ _ 
                          -> id:getMethodDeclId ds
               _          -> getMethodDeclId ds
      _             -> getMethodDeclId ds

getVarsInfo:: MemberDecl -> (String, String, [String])
getVarsInfo (FieldDecl mods t vid) = (getModifier $ map prettyPrint mods, prettyPrint t, map getIdVar vid)

getModifier :: [String] -> String
getModifier []     = ""
getModifier (x:xs) = 
 if elem x javaModifiers
 then x
 else getModifier xs

getIdVar :: VarDecl -> String
getIdVar (VarDecl (VarId (Ident id)) _) = id

splitVars :: [(String,String, [String])] -> [(String,String,String)]
splitVars []                 = []
splitVars (tv:tvs) = splitV tv ++ splitVars tvs

splitV :: (String,String, [String]) -> [(String,String, String)]
splitV (_,_,[])        = []
splitV (mods,t,(v:vs)) = (mods, t,v):splitV (mods,t,vs)

getMethodsNames :: T.ClassInfo -> T.HTriples -> [(T.MethodName,T.Overriding)]
getMethodsNames _ []      = []
getMethodsNames cl (c:cs) = if ((T._methodCN c ^. T.clinf) == cl)  
                            then (T._methodCN c ^. T.mname,T._methodCN c ^. T.overl):getMethodsNames cl cs
                            else getMethodsNames cl cs

-- Implemented like this due to bug in the java library
-- generates the new methods that have to be added due to instrumentation of code
instrumentMethodMemberDecl :: [Decl] -> [((T.MethodName,T.Overriding),Int)] -> [(String, String, String,T.Overriding)]
instrumentMethodMemberDecl [] _        = []
instrumentMethodMemberDecl (d:ds) mns  = 
 case d of
      MemberDecl md -> case md of 
                            MethodDecl _ _ _ (Ident id) _ _ _ -> 
                               let (m1,m2,over,mns') = generateMethods d mns
                               in if (m1 == Nothing)
                                  then instrumentMethodMemberDecl ds mns
                                  else (id 
                                       , prettyPrint $ (\(Just x) -> x) m1
                                       , ((head.lines.prettyPrint) m2) ++ "\n {"
                                       , over):instrumentMethodMemberDecl ds mns'
                            _                                 -> instrumentMethodMemberDecl ds mns
      _             -> instrumentMethodMemberDecl ds mns


generateMethods :: Decl -> [((T.MethodName,T.Overriding),Int)] 
                    -> (Maybe Decl, Decl, T.Overriding, [((T.MethodName,T.Overriding),Int)])
generateMethods md@(MemberDecl (MethodDecl public xs type' (Ident id) param ex mbody)) mns = 
 let mn_n = getMethodName id mns in
 if isJust mn_n
 then if (isJust type')
      then let new_body    = makeNewBodyRet id param (snd $ fromJust mn_n)
               new_method  = MethodDecl public xs type' (Ident id) param ex new_body
               id_arg      = FormalParam [] (RefType (ClassRefType (ClassType [(Ident "Integer",[])]))) False (VarId (Ident "id"))
               method_inst = MethodDecl public xs type' (Ident (id ++ "Aux")) (param ++ [id_arg]) ex mbody
           in (Just (MemberDecl new_method), MemberDecl method_inst, (snd.fst) $ fromJust mn_n, dropId mns id)
      else let new_body    = makeNewBodyVoid id param (snd $ fromJust mn_n)
               new_method  = MethodDecl public xs type' (Ident id) param ex new_body
               id_arg      = FormalParam [] (RefType (ClassRefType (ClassType [(Ident "Integer",[])]))) False (VarId (Ident "id"))
               method_inst = MethodDecl public xs type' (Ident (id ++ "Aux")) (param ++ [id_arg]) ex mbody
           in (Just (MemberDecl new_method), MemberDecl method_inst, (snd.fst) $ fromJust mn_n, dropId mns id)
 else (Nothing, md, T.OverNil,mns)

getMethodName :: String -> [((T.MethodName,T.Overriding),Int)] -> Maybe ((T.MethodName,T.Overriding),Int)
getMethodName id mns = 
 let ys = [ y | y <- mns, (fst.fst) y == id]
 in if null ys
    then Nothing
    else Just $ head ys

dropId :: Eq a => [((a,b),c)] -> a -> [((a,b),c)]
dropId [] _      = []
dropId (x:xs) id = 
 if (fst.fst) x == id
 then xs
 else x:dropId xs id

makeNewBodyRet :: T.MethodName -> [FormalParam] -> Int -> MethodBody
makeNewBodyRet mn fps n = 
 let expNames = makeNewArgsInCall fps mn n
 in MethodBody (Just (Block [BlockStmt (Return (Just (MethodInv (MethodCall (Name [Ident (mn ++ "Aux")]) expNames))))]))

makeNewBodyVoid :: T.MethodName -> [FormalParam] -> Int -> MethodBody
makeNewBodyVoid mn fps n = 
 let expNames = makeNewArgsInCall fps mn n
 in MethodBody (Just (Block [BlockStmt (ExpStmt (MethodInv (MethodCall (Name [Ident (mn ++ "Aux")]) expNames)))]))

makeNewArgsInCall :: [FormalParam] -> T.MethodName -> Int -> [Exp]
makeNewArgsInCall [] mn n = [MethodInv (MethodCall (Name [Ident ("fid_"++mn++show n),Ident "getNewId"]) [])]
makeNewArgsInCall ((FormalParam _ _ _ (VarId (Ident id))):fps) mn n = 
 (ExpName (Name [Ident id])) : makeNewArgsInCall fps mn n
