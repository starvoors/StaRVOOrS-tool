module Types where

------------
-- ppDATE --
------------

data PPDATE = PPDATE
  { importsGet     :: Imports
  , globalGet      :: Global
  , cinvariantsGet :: CInvariants
  , contractsGet   :: Contracts
  , methodsGet     :: Methods 
  } deriving (Show, Eq)

updateContractsPP :: PPDATE -> Contracts -> PPDATE
updateContractsPP (PPDATE imp global cinvs conts ms) conts' = PPDATE imp global cinvs conts' ms

data Import = Import String deriving (Show, Eq)
type Imports = [Import]

type Class = String
type ClassInfo = String
type BodyCInv = String

data CInvariant = CI Class BodyCInv deriving (Show, Eq)
type CInvariants = [CInvariant]


type ContractName   = String
type MethodName     = String
type Pre            = String
type Post           = String
type Assignable     = String
type MethodCN       = (ClassInfo, MethodName)

-- Contracts = Hoare Triples
data Contract = Contract
  { contractName :: ContractName
  , methodCN :: MethodCN
  , pre :: Pre
  , post :: Post
  , assignable :: Assignable
  , optimized :: [Pre] -- Added to control new preconditions generated by KeY
  , chGet :: Int -- Added to associate a contract to a channel
  } | CNil deriving (Show, Eq)

type Contracts = [Contract]

updateCN :: Contract -> ContractName -> Contract
updateCN (Contract cn m p po ass opt ch) cn' = Contract cn' m p po ass opt ch

updatePre :: Contract -> Pre -> Contract
updatePre (Contract cn m p po ass opt ch) p' = Contract cn m p' po ass opt ch

updatePost :: Contract -> Post -> Contract
updatePost (Contract cn m p po ass opt ch) po' = Contract cn m p po' ass opt ch

updateOpt :: Contract -> [Pre] -> Contract
updateOpt (Contract cn m p po ass opt ch) opt' = Contract cn m p po ass opt' ch

updateCH :: Contract -> Int -> Contract
updateCH (Contract cn m p po ass opt ch) ch' = Contract cn m p po ass opt ch'


data Context =
   Ctxt { variables :: Variables
        , events :: Events
        , property :: Property
        , foreaches :: Foreaches
        }
  deriving (Eq,Show,Read)

data Global = Global
  { ctxtGet  :: Context } deriving (Show, Eq)

updateGlobal :: Global -> Context -> Global
updateGlobal (Global ctxt) ctxt' = Global ctxt'


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

bindToArgs :: Bind -> Args
bindToArgs (BindType t id) = Args t id
bindToArgs _               = error "bindToArgs \n"

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

type JML = String

--------------
-- PROPERTY --
--------------

data InitialCode =
   InitNil
 | InitProg Java
  deriving (Eq,Ord,Show,Read)

type PropertyName = String
type NameState = String

data State = State NameState InitialCode [ContractName] deriving (Show, Eq,Read)

getCNList :: State -> [ContractName]
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
  { getAccepting :: Accepting
  , getBad       :: Bad
  , getNormal    :: Normal 
  , getStarting  :: Starting
  } deriving (Eq, Show,Read)

type Transitions = [Transition]

type Event = String
type Cond = String
type Action = String

data Arrow = Arrow 
  { event  :: Event
  , cond   ::  Cond
  , action :: Action
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
  } | PNIL deriving (Show, Eq,Read)


------------
-- EVENTS --
------------

-- Events = Triggers

type WhereClause = String

data EventDef = EventDef 
  { eName :: Event
  , args :: [Bind]
  , compEvent :: CompoundEvent
  , whereClause :: WhereClause
  } deriving (Show, Eq,Read)

data CompoundEvent =
   NormalEvent Binding Id [Bind] EventVariation
 | ClockEvent Id Integer
 | OnlyId Id
 | OnlyIdPar Id
 | Collection EventList
  deriving (Eq,Show,Read)

data EventVariation =
   EVEntry
 | EVExit [Bind]
 | EVThrow [Bind]
 | EVHadle [Bind]
  deriving (Eq,Show,Read)

data EventList =
   CECollection [CompoundEvent]
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

updateEventArgs :: EventDef -> [Bind] -> EventDef
updateEventArgs (EventDef e arg cpes wc) arg' = EventDef e arg' cpes wc

updateMethodCallName :: EventDef -> MethodName -> EventDef
updateMethodCallName (EventDef e arg cpes wc) mn = EventDef e arg (updateCpeMethodName cpes mn) wc

updateCpeMethodName :: CompoundEvent -> MethodName -> CompoundEvent
updateCpeMethodName (NormalEvent bind id bs ev) id' = NormalEvent bind id' bs ev
updateCpeMethodName cpe _                           = cpe

updateCpeMethodCallBody :: CompoundEvent -> [Bind] -> CompoundEvent
updateCpeMethodCallBody (NormalEvent bind id bs ev) bs' = NormalEvent bind id bs' ev
updateCpeMethodCallBody cpe _                           = cpe

updateMethodCallBody :: EventDef -> [Bind] -> EventDef
updateMethodCallBody (EventDef e arg cpes wc) bs = EventDef e arg (updateCpeMethodCallBody cpes bs) wc

type Events = [EventDef]

-----------------------
-- XML related types --
-----------------------

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

