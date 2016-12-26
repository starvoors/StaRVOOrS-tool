module Types where

import Data.Map
import System.FilePath

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

data Import = Import String deriving (Show, Eq)
type Imports = [Import]

type Class = String
type ClassInfo = String
type BodyCInv = String

data CInvariant = CI Class BodyCInv | CInvNil deriving (Show, Eq)
type CInvariants = [CInvariant]


type HTName   = String
type MethodName     = String
type Pre            = JMLExp
type Post           = JMLExp
type Assignable     = String
type MethodCN       = (ClassInfo, MethodName)


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

--------------
-- Methods  --
--------------

type Methods = String

---------------
-- Foreaches --
---------------

type Foreaches = [Foreach]

data Foreach = Foreach [Args] Context deriving (Eq,Show, Read)

data Args =
   Args Type Id
  deriving (Eq,Ord,Show,Read)

getArgsId :: Args -> Id
getArgsId (Args t id) = id

getArgsType :: Args -> Type
getArgsType (Args t id) = t

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
   Var VarModifier Type [VarDecl]
  deriving (Eq,Ord,Show,Read)

data VarModifier =
   VarModifierFinal
 | VarModifierNil
  deriving (Eq,Ord,Show,Read)

data VarDecl =
   VarDecl Id VariableInitializer
  deriving (Eq,Ord,Show,Read)

data VariableInitializer =
   VarInit VarExp
 | VarInitNil
  deriving (Eq,Ord,Show,Read)

getVariableArgs :: Variable -> [Args]
getVariableArgs (Var vm t [])          = []
getVariableArgs (Var vm t (dec:decls)) = Args t (getVarDeclId dec) : getVariableArgs (Var vm t decls)

getVarDeclId :: VarDecl -> Id
getVarDeclId (VarDecl id _) = id

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

--------------
-- PROPERTY --
--------------

data InitialCode =
   InitNil
 | InitProg Java
  deriving (Eq,Ord,Show,Read)

type PropertyName = String
type NameState = String

data State = State NameState InitialCode [HTName] deriving (Show, Eq,Read)

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
  , cond    ::  Cond
  , action  :: Action
  } deriving (Show, Eq,Read)


data Transition = Transition 
  { fromState :: NameState
  , arrow :: Arrow
  , toState :: NameState
  } deriving (Show, Eq,Read)


data Property = Property
  { pName        :: PropertyName
  , pStates      :: States
  , pTransitions :: Transitions
  , pProps       :: Property
  } | PNIL 
    | PINIT { piName  :: PropertyName 
            , tmpId   :: Id 
            , fors    :: [Id]
            , piProps :: Property
            }
         deriving (Show, Eq,Read)


---------------
-- ActEvents --
---------------

type ActEvents = [ActEvent]

data ActEvent =
   ActEvent Id
  deriving (Eq,Ord,Show,Read)

--------------
-- Triggers --
--------------

type WhereClause = String

data TriggerDef = TriggerDef 
  { tName :: Trigger
  , args :: [Bind]
  , compTrigger :: CompoundTrigger
  , whereClause :: WhereClause
  } deriving (Show, Eq,Read)

data CompoundTrigger =
   NormalEvent Binding Id [Bind] TriggerVariation
 | ClockEvent Id Integer
 | OnlyId Id
 | OnlyIdPar Id
 | Collection TriggerList
  deriving (Eq,Show,Read)

getCTVariation :: CompoundTrigger -> TriggerVariation
getCTVariation (NormalEvent _ _ _ tv) = tv

data TriggerVariation =
   EVEntry
 | EVExit [Bind]
 | EVThrow [Bind]
 | EVHadle [Bind]
 | EVNil--Added to simplify search of triggers during the translation
  deriving (Eq,Show,Read)

data TriggerList =
   CECollection [CompoundTrigger]
  deriving (Eq,Show,Read)

data Bind =
   BindStar
 | BindType Type Id
 | BindId Id
  deriving (Eq,Show,Read)

getBindTypeId :: Bind -> Id
getBindTypeId (BindType t id) = id

getBindTypeType :: Bind -> Type
getBindTypeType (BindType t id) = t

getBindIdId :: Bind -> Id
getBindIdId (BindId id) = id

data Binding =
   BindingVar Bind
  deriving (Eq,Show,Read)

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
type OldExprM = Map HTName OldExprL

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

