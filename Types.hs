module Types where

import qualified Data.Map as Map
import System.FilePath
import System.Console.GetOpt
import Data.Maybe ( fromMaybe )
import Language.Java.Syntax hiding(Type,VarDecl)
import qualified AbsActions as Act

------------
-- ppDATE --
------------

data PPDATE = PPDATE
  { importsGet     :: Imports
  , globalGet      :: Global
  , templatesGet   :: Templates
  , cinvariantsGet :: CInvariants
  , htsGet         :: HTriples
  , methodsGet     :: Methods 
  } deriving (Show, Eq)

updateHTsPP :: PPDATE -> HTriples -> PPDATE
updateHTsPP (PPDATE imp global temps cinvs conts ms) conts' = PPDATE imp global temps cinvs conts' ms

updateGlobalPP :: PPDATE -> Global -> PPDATE
updateGlobalPP (PPDATE imp global temps cinvs conts ms) global' = PPDATE imp global' temps cinvs conts ms

updateTemplatesPP :: PPDATE -> Templates -> PPDATE
updateTemplatesPP (PPDATE imp global temps cinvs conts ms) temps' = PPDATE imp global temps' cinvs conts ms

data Import = Import String deriving (Eq)

instance Show Import where
 show (Import imp) = "import " ++ imp ++ " ;"

type Imports = [Import]

type Class = String
type ClassInfo = String
type BodyCInv = String

data CInvariant = CI Class BodyCInv | CInvNil deriving (Eq)

instance Show CInvariant where
 show (CI cl body) = cl ++ " {" ++ (concat.lines) body ++ "}"
 show CInvNil      = ""

type CInvariants = [CInvariant]


type HTName     = String
type MethodName = String
type Pre        = JMLExp
type Post       = JMLExp
type Assignable = String
data MethodCN   = 
 MCN { clinf :: ClassInfo
     , mname :: MethodName
     , overl :: Overloading
     } deriving (Show,Eq)

data Overloading = Over [Type] | OverNil
  deriving (Ord, Read)

instance Eq Overloading where
 OverNil == OverNil     = True
 (Over xs) == (Over ys) = xs == ys
 _ == _                 = False

instance Show Overloading where
 show OverNil   = "nil"
 show (Over []) = "()"
 show (Over xs) = "(" ++ foldr1 (\x xs -> x ++ "," ++ xs) xs ++ ")"

data HT = HT
  { htName :: HTName
  , methodCN :: MethodCN
  , pre :: Pre
  , post :: Post
  , assignable :: Assignable
  , optimized :: [Pre] -- Added to control new preconditions generated by KeY
  , chGet :: Int -- Added to associate a Hoare triple to a channel
  , path2it :: String -- Added to associate the Hoare triple to the address of its class
  } | CNil deriving (Show, Eq)

type HTriples = [HT]

updateCN :: HT -> HTName -> HT
updateCN (HT cn m p po ass opt ch p2it) cn' = HT cn' m p po ass opt ch p2it

updatePre :: HT -> Pre -> HT
updatePre (HT cn m p po ass opt ch p2it) p' = HT cn m p' po ass opt ch p2it

updatePost :: HT -> Post -> HT
updatePost (HT cn m p po ass opt ch p2it) po' = HT cn m p po' ass opt ch p2it

updateOpt :: HT -> [Pre] -> HT
updateOpt (HT cn m p po ass opt ch p2it) opt' = HT cn m p po ass opt' ch p2it

updateCH :: HT -> Int -> HT
updateCH (HT cn m p po ass opt ch p2it) ch' = HT cn m p po ass opt ch' p2it

updatePath :: HT -> String -> HT
updatePath (HT cn m p po ass opt ch p2it) p2it' = HT cn m p po ass opt ch p2it'



data Context =
   Ctxt { variables :: Variables
        , actevents :: ActEvents
        , triggers  :: Triggers
        , property  :: Property
        , foreaches :: Foreaches
        }
  deriving (Eq,Show,Read)

updateCtxtFors :: Context -> Foreaches -> Context
updateCtxtFors (Ctxt vars acts trs props fors) fors' = Ctxt vars acts trs props fors'

updateCtxtProps :: Context -> Property -> Context
updateCtxtProps (Ctxt vars acts trs props fors) props' = Ctxt vars acts trs props' fors

updateCtxtTrs :: Context -> Triggers -> Context
updateCtxtTrs (Ctxt vars acts trs props fors) trs' = Ctxt vars acts trs' props fors

data Global = Global
  { ctxtGet  :: Context } deriving (Show, Eq)

updateGlobal :: Global -> Context -> Global
updateGlobal (Global ctxt) ctxt' = Global ctxt'

---------------
-- Templates --
---------------

data Templates = TempNil | Temp [Template] deriving (Eq,Show)

data Template = Template
  { tempId        :: Id
  , tempBinds     :: [Args]
  , tempVars      :: Variables
  , tempActEvents :: ActEvents
  , tempTriggers  :: Triggers 
  , tempProp      :: Property
  } deriving (Show, Eq)

updateTemplateProp :: Template -> Property -> Template
updateTemplateProp (Template id bs vars ies trs prop) prop' = Template id bs vars ies trs prop'

data TempArgs = TArgs --Arguments used to instantiate a template
 { targTr   :: [(Args,Act.Args)]--triggers
 , targAct  :: [(Args,Act.Args)]--actions
 , targCond :: [(Args,Act.Args)]--conditions
 , targHT   :: [(Args,Act.Args)]--Hoare triples
 , targRef  :: [(Args,Act.Args)]--reference types
 , targMN   :: [(Args,Act.Args)]--method names
 } deriving (Show,Eq)

emptyTargs :: TempArgs
emptyTargs = TArgs [] [] [] [] [] []

--------------
-- Methods  --
--------------

type Methods = String

---------------
-- Foreaches --
---------------

type Foreaches = [Foreach]

--ForId is introduced to keep track of the scope where a trigger is defined
data Foreach = 
 Foreach { getArgsForeach :: [Args]
         , getCtxtForeach :: Context
         , getIdForeach :: ForId 
         } deriving (Eq,Show, Read)

updCtxtForeach :: Foreach -> Context -> Foreach
updCtxtForeach (Foreach args ctxt id) ctxt' = Foreach args ctxt' id

data ForId = ForId Id deriving (Eq,Read)

instance Show ForId where
 show (ForId id) = id

--Type used to know where a trigger is defined
data Scope = TopLevel | InFor ForId | InTemp Id deriving (Eq,Show,Read)

tempScope :: Scope -> Bool
tempScope (InTemp _) = True
tempScope _          = False

data Args =
 Args { getArgsType :: Type
      , getArgsId :: Id
      } deriving (Eq,Ord,Read)

instance Show Args where
 show (Args t id) = t ++ " " ++ id

makeArgs :: Type -> Id -> Args
makeArgs t id = Args t id

bindToArgs :: Bind -> Args
bindToArgs (BindType t id) = Args t id
bindToArgs _               = error "bindToArgs.\n"

---------------
-- Variables --
---------------

type Variables = [Variable]

data Variable = 
 Var { getVarMod     :: VarModifier
     , getTypeVar    :: Type
     , getVarDeclVar :: [VarDecl]
     } deriving (Eq,Ord,Read)

instance Show Variable where
 show (Var modif t vdecls) = show modif ++ t ++ " " ++ addComma' (map show vdecls) ++ " ;"

data VarModifier =
   VarModifierFinal
 | VarModifierNil
  deriving (Eq,Ord,Read)

instance Show VarModifier where
 show VarModifierFinal = "final "
 show VarModifierNil   = ""

data VarDecl =
 VarDecl { varDecId   :: Id
         , varDecInit :: VariableInitializer
         } deriving (Eq,Ord,Read)

instance Show VarDecl where
 show (VarDecl id varinit) = id ++ show varinit

data VariableInitializer =
   VarInit VarExp
 | VarInitNil
  deriving (Eq,Ord,Read)

instance Show VariableInitializer where
 show VarInitNil    = ""
 show (VarInit exp) = " = " ++ exp 

getVariableArgs :: Variable -> [Args]
getVariableArgs (Var vm t [])          = []
getVariableArgs (Var vm t (dec:decls)) = Args t (getVarDeclId dec) : getVariableArgs (Var vm t decls)

getVarDeclId :: VarDecl -> Id
getVarDeclId (VarDecl id _) = id

addComma' :: [String] -> String
addComma' []          = ""
addComma' [xs]        = xs
addComma' (xs:ys:xss) = xs ++ "," ++ addComma' (ys:xss)

------------------
-- Useful types --
------------------

type Id = String

type Type = String

type VarExp = String

type XML = String

type Java = String

type Filename = String

type ErrorMsg = String

type JMLExp = String

type HTjml = [(MethodName, ClassInfo, Overloading, String)]

type MethodInvocations = [Exp]

type Channel = String

data TriggersInfo = 
 TI { tiTN      :: Trigger --trigger_name
    , tiMN      :: MethodName --method_name
    , tiCI      :: ClassInfo --class_type
    , tiCVar    :: String --class_variable_name
    , tiTrvar   :: TriggerVariation
    , tiBinds   :: [Bind]
    , tiTrDef   :: Maybe TriggerDef
    , tiScope   :: Scope
    , tiOver    :: Overloading
    } deriving (Show,Eq)

data CreateActInfo = 
 CAI { caiId    :: Id
     , caiArgs  :: [Act.Args]
     , caiCh    :: Channel
     , caiAct   :: Act.Action
     , caiScope :: Scope
     } deriving (Show,Eq)

--------------
-- PROPERTY --
--------------

data InitialCode =
   InitNil
 | InitProg Java
  deriving (Eq,Ord,Read)

instance Show InitialCode where
 show InitNil         = ""
 show (InitProg java) = " { " ++ java ++ " } " 

type PropertyName = String
type NameState = String

data State = State NameState InitialCode [HTName] deriving (Eq,Read)

getNameState :: State -> NameState
getNameState (State nm _ _) = nm

updateHTns :: State -> [HTName] -> State
updateHTns (State nm i hts) hts' = State nm i hts'

instance Show State where
 show (State ns initc hts) = ns ++ show initc ++ foo hts ++ "; "
                                 where foo []  = ""
                                       foo hts = " (" ++ addComma' hts ++ ") "

getCNList :: State -> [HTName]
getCNList (State ns ic cns) = cns

getNS :: State -> NameState
getNS (State ns ic cns) = ns

getInitialCode :: State -> InitialCode
getInitialCode (State ns ic cns) = ic

type Accepting = [State]
type Bad = [State]
type Normal = [State]
type Starting = [State]

data States = States 
  { getStarting  :: Starting
  , getAccepting :: Accepting
  , getBad       :: Bad
  , getNormal    :: Normal   
  } deriving (Eq, Show,Read)

type Transitions = [Transition]

type Trigger = String
type Cond    = String
type Action  = String

data Arrow = Arrow 
  { trigger :: Trigger
  , cond    :: Cond
  , action  :: Action
  } deriving (Eq,Read)

instance Show Arrow where
 show (Arrow tr c act) = " [" ++ tr ++ " \\ "  ++ c ++ " \\ " ++ (concat.lines) act ++ " ]"

data Transition = Transition 
  { fromState :: NameState
  , arrow :: Arrow
  , toState :: NameState
  } deriving (Eq,Read)

instance Show Transition where
 show (Transition fns arr tns) = fns ++ " -> " ++ tns ++ show arr

data Property = Property
  { pName        :: PropertyName
  , pStates      :: States
  , pTransitions :: Transitions
  , pProps       :: Property
  } | PNIL 
    | PINIT { piName  :: PropertyName 
            , tmpId   :: Id 
            , bounds  :: [Id]
            , piProps :: Property
            }
         deriving (Show, Eq,Read)


---------------
-- ActEvents --
---------------

type ActEvents = [ActEvent]

data ActEvent =
   ActEvent Id
  deriving (Eq,Ord,Read)

instance Show ActEvent where
 show (ActEvent id) = id

--------------
-- Triggers --
--------------

type WhereClause = String

data TriggerDef = TriggerDef 
  { tName :: Trigger
  , args :: [Bind]
  , compTrigger :: CompoundTrigger
  , whereClause :: WhereClause
  } deriving (Eq,Read)

instance Show TriggerDef where 
 show (TriggerDef nm [] ct w) = nm ++ "() = { " ++ show ct ++ " }" ++ showWhere w
 show (TriggerDef nm xs ct w) = nm ++ "(" ++ addComma' (map show xs) ++ ") = { " ++ show ct ++ " }" ++ showWhere w

showWhere :: String -> String
showWhere [] = ""
showWhere xs = " where { " ++ xs ++ " }"

data CompoundTrigger =
   NormalEvent Binding Id [Bind] TriggerVariation
 | ClockEvent Id Integer
 | OnlyId Id
 | OnlyIdPar Id
 | Collection TriggerList
  deriving (Eq,Read)

instance Show CompoundTrigger where
 show (NormalEvent b id binds tv) = show b ++ "." ++ id ++ "(" ++ addComma' (map show binds) ++ ")" ++ show tv
 show (ClockEvent id n)           = id ++ "@" ++ show n
 show (OnlyId id)                 = id
 show (OnlyIdPar id)              = id ++ "()"
 show (Collection tls)            = show tls

getCTVariation :: CompoundTrigger -> TriggerVariation
getCTVariation (NormalEvent _ _ _ tv) = tv

getCTArgs :: CompoundTrigger -> [Bind]
getCTArgs (NormalEvent _ _ bs _) = bs

data TriggerVariation =
   EVEntry
 | EVExit [Bind]
 | EVThrow [Bind]
 | EVHadle [Bind]
 | EVNil--Added to simplify search of triggers during the translation
  deriving (Eq,Read)

instance Show TriggerVariation where
 show EVEntry      = "entry"
 show (EVExit rs)  = "exit(" ++ concatMap show rs ++ ")" 
 show (EVThrow rs) = "throw(" ++ concatMap show rs ++ ")"
 show (EVHadle rs) = "handle(" ++ concatMap show rs ++ ")"
 show EVNil        = ""

data TriggerList =
   CECollection [CompoundTrigger]
  deriving (Eq,Read)

instance Show TriggerList where
 show (CECollection xs) = foldr (\x xs -> "{" ++ x ++ "}" ++ " | " ++ xs) [] (map show xs)

data Bind =
   BindStar
 | BindType Type Id
 | BindId Id
  deriving (Eq,Read)

instance Show Bind where
 show BindStar        = "*"
 show (BindType t id) = t ++ " " ++ id
 show (BindId id)     = id

getBindTypeId :: Bind -> Id
getBindTypeId (BindType t id) = id

getBindTypeType :: Bind -> Type
getBindTypeType (BindType t id) = t

getBindIdId :: Bind -> Id
getBindIdId (BindId id) = id

data Binding =
   BindingVar Bind
  deriving (Eq,Read)

instance Show Binding where
 show (BindingVar b) = show b 

getBind :: Binding -> Bind
getBind (BindingVar bn) = bn

updateTriggerArgs :: TriggerDef -> [Bind] -> TriggerDef
updateTriggerArgs (TriggerDef e arg cpes wc) arg' = TriggerDef e arg' cpes wc

updateMethodCallName :: TriggerDef -> MethodName -> TriggerDef
updateMethodCallName (TriggerDef e arg cpes wc) mn = TriggerDef e arg (updateCpeMethodName cpes mn) wc

updateCpeMethodName :: CompoundTrigger -> MethodName -> CompoundTrigger
updateCpeMethodName (NormalEvent bind id bs ev) id' = NormalEvent bind id' bs ev
updateCpeMethodName cpe _                           = cpe

updateCpeMethodCallBody :: CompoundTrigger -> [Bind] -> CompoundTrigger
updateCpeMethodCallBody (NormalEvent bind id bs ev) bs' = NormalEvent bind id bs' ev
updateCpeMethodCallBody cpe _                           = cpe

updateMethodCallBody :: TriggerDef -> [Bind] -> TriggerDef
updateMethodCallBody (TriggerDef e arg cpes wc) bs = TriggerDef e arg (updateCpeMethodCallBody cpes bs) wc

type Triggers = [TriggerDef]


-------------------------------------------------------------------
-- Types to deal with the operationalisation of \old expressions --
-------------------------------------------------------------------

type OldExprL = [(String,Type,String)] --(expr_in_old,type_expr_in_old,name_to_replace_expr_in_old)
type OldExprM = Map.Map HTName OldExprL

-----------------------
-- XML related types --
-----------------------

--Types associated to the KeY API --

type ContractId   = String
type ContractText = String
type Target       = String

data Proof = Proof
  { contractId    :: ContractId
  , contractText  :: ContractText
  , typee         :: Type
  , target        :: Target
  , executionPath :: [EPath]
  } deriving (Show, Eq)
 
data EPath = EPath
  { pathCondition          :: String
  , verified               :: String
  , newPrecondition        :: String
  , terminationKind        :: String 
  , notFulfilledPres       :: [MethodContractApplication]
  , notFulfilledNullChecks :: [MethodContractApplication]
  , notInitValidLoopInvs   :: [MethodContractApplication]
  , notPreservedLoopInvs   :: [MethodContractApplication]
  } deriving (Show, Eq)

data MethodContractApplication = MCA 
 { fileMCA     :: String
 , startLine   :: String
 , startColumn :: String
 , endLine     :: String
 , endColumn   :: String
 , methodMCA   :: String
 , contractMCA :: String
 } deriving(Eq,Show)


-- Types associated to the types inference --

data OldExpr = OldExpr
  { htID          :: Id
  , classInf      :: ClassInfo
  , targ          :: Target
  , path          :: FilePath
  , methoD        :: MethodName
  , oldExprs      :: [OExpr]
  } deriving (Show, Eq)

updateOldExprs :: OldExpr -> [OExpr] -> OldExpr
updateOldExprs (OldExpr cn cinf targ pth m oexprs) oexprs' = OldExpr cn cinf targ pth m oexprs'

data OExpr = OExpr
 { expr      :: String
 , inferType :: String
 } deriving (Show,Eq)


-----------
-- Flags --
-----------

data Flag = Version 
 | OnlyParse
 | NoneVerbose
 | XML
 | Help
 | OnlyRV
    deriving (Show,Eq)

options :: [OptDescr Flag]
options =
    [ Option "v" ["version"] (NoArg Version) "Show version number"
    , Option "n" ["none_verbose"] (NoArg NoneVerbose) "None verbose monitor generation"
    , Option "p" ["only_parse"] (NoArg OnlyParse) "Only parse the ppDATE file"    
    , Option "x" ["xml"] (NoArg XML) ".xml file generated by KeY is not removed"
    , Option "h" ["help"] (NoArg Help) "Describes the different options"
    , Option "r" ["only_rv"] (NoArg OnlyRV) "Monitor generation without performing static verification"
    ]

