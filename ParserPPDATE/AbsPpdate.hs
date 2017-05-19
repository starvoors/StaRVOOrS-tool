

module AbsPpdate where

-- Haskell module generated by the BNF converter




newtype Id = Id String deriving (Eq, Ord, Show, Read)
newtype Symbols = Symbols String deriving (Eq, Ord, Show, Read)
data AbsPPDATE
    = AbsPPDATE Imports Global Templates CInvariants HTriples Methods
  deriving (Eq, Ord, Show, Read)

data Imports = Imports [Import]
  deriving (Eq, Ord, Show, Read)

data Import = Import [JavaFiles]
  deriving (Eq, Ord, Show, Read)

data JavaFiles = JavaFiles Id
  deriving (Eq, Ord, Show, Read)

data Global = Global Context
  deriving (Eq, Ord, Show, Read)

data Context
    = Ctxt Variables ActEvents Triggers Properties Foreaches
  deriving (Eq, Ord, Show, Read)

data Variables = VarNil | VarDef [Variable]
  deriving (Eq, Ord, Show, Read)

data Variable = Var VarModifier Type [VarDecl]
  deriving (Eq, Ord, Show, Read)

data VarModifier = VarModifierFinal | VarModifierNil
  deriving (Eq, Ord, Show, Read)

data ActEvents = ActEventsNil | ActEventsDef [ActEvent]
  deriving (Eq, Ord, Show, Read)

data ActEvent = ActEvent Id
  deriving (Eq, Ord, Show, Read)

data Triggers = TriggersNil | TriggersDef [Trigger]
  deriving (Eq, Ord, Show, Read)

data Trigger = Trigger Id [Bind] CompoundTrigger WhereClause
  deriving (Eq, Ord, Show, Read)

data CompoundTrigger
    = Collection TriggerList
    | NormalEvent Binding Id [Vars] TriggerVariation
    | ClockEvent Id Integer
    | OnlyId Id
    | OnlyIdPar Id
  deriving (Eq, Ord, Show, Read)

data TriggerList = CECollection [CompoundTrigger]
  deriving (Eq, Ord, Show, Read)

data TriggerVariation
    = EVEntry | EVExit [Vars] | EVThrow [Vars] | EVHadle [Vars]
  deriving (Eq, Ord, Show, Read)

data Binding = BindingVar Bind
  deriving (Eq, Ord, Show, Read)

data Bind = BindStar | BindType Type Id | BindId Id
  deriving (Eq, Ord, Show, Read)

data WhereClause = WhereClauseNil | WhereClauseDef [WhereExp]
  deriving (Eq, Ord, Show, Read)

data WhereExp = WhereExp Bind VarExp
  deriving (Eq, Ord, Show, Read)

data Vars = Vars Bind
  deriving (Eq, Ord, Show, Read)

data Properties
    = PropertiesNil | ProperiesDef Id PropKind Properties
  deriving (Eq, Ord, Show, Read)

data PropKind
    = PropKindNormal States Transitions | PropKindPinit Id [Id]
  deriving (Eq, Ord, Show, Read)

data States = States Starting Accepting Bad Normal
  deriving (Eq, Ord, Show, Read)

data Accepting = AcceptingNil | AcceptingDef [State]
  deriving (Eq, Ord, Show, Read)

data Bad = BadNil | BadDef [State]
  deriving (Eq, Ord, Show, Read)

data Normal = NormalNil | NormalDef [State]
  deriving (Eq, Ord, Show, Read)

data Starting = StartingDef [State]
  deriving (Eq, Ord, Show, Read)

data State = State NameState InitialCode HTNames
  deriving (Eq, Ord, Show, Read)

data NameState = NameState Id
  deriving (Eq, Ord, Show, Read)

data HTNames = CNS [HTName] | CNSNil
  deriving (Eq, Ord, Show, Read)

data HTName = CN Id
  deriving (Eq, Ord, Show, Read)

data InitialCode = InitNil | InitProg Java
  deriving (Eq, Ord, Show, Read)

data Transitions = Transitions [Transition]
  deriving (Eq, Ord, Show, Read)

data Transition = Transition NameState NameState Arrow
  deriving (Eq, Ord, Show, Read)

data Arrow = Arrow Id Actmark Condition
  deriving (Eq, Ord, Show, Read)

data Actmark = ActMarkNil | ActMark
  deriving (Eq, Ord, Show, Read)

data Condition = Cond1 | Cond2 Cond
  deriving (Eq, Ord, Show, Read)

data Cond = CondExpDef CondExp | CondAction CondExp Action
  deriving (Eq, Ord, Show, Read)

data Action = Action Expressions
  deriving (Eq, Ord, Show, Read)

data Foreaches
    = ForeachesNil | ForeachesDef [Args] Context Foreaches
  deriving (Eq, Ord, Show, Read)

data Templates = Temps [Template] | TempsNil
  deriving (Eq, Ord, Show, Read)

data Template = Temp Id [Args] BodyTemp
  deriving (Eq, Ord, Show, Read)

data BodyTemp = Body Variables ActEvents Triggers Properties
  deriving (Eq, Ord, Show, Read)

data CInvariants = CInvariants [CInvariant] | CInvempty
  deriving (Eq, Ord, Show, Read)

data CInvariant = CI Id JML
  deriving (Eq, Ord, Show, Read)

data HTriples = HTriples [HT] | HTempty
  deriving (Eq, Ord, Show, Read)

data HT = HT Id Pre Method Post Assignable
  deriving (Eq, Ord, Show, Read)

data Pre = Pre JML | PreNil
  deriving (Eq, Ord, Show, Read)

data Method = Method Id Id Overriding
  deriving (Eq, Ord, Show, Read)

data Post = Post JML | PostNil
  deriving (Eq, Ord, Show, Read)

data Assignable = Assignable [Assig] | AssigNil
  deriving (Eq, Ord, Show, Read)

data Assig = AssigJML JML | AssigE | AssigN
  deriving (Eq, Ord, Show, Read)

data Overriding = Over [Type] | OverNil
  deriving (Eq, Ord, Show, Read)

data Methods = Methods BodyMethods | MethodsNil
  deriving (Eq, Ord, Show, Read)

data BodyMethods = BodyMemDecl [MemberDecl] | BodyImport ImportFile
  deriving (Eq, Ord, Show, Read)

data MemberDecl
    = MemberDeclMethod Type Id [Args] Java
    | MemberDeclField VariableDecl
  deriving (Eq, Ord, Show, Read)

data VariableDecl = VariableDecl Type [VarDecl]
  deriving (Eq, Ord, Show, Read)

data VarDecl = VarDecl Id VariableInitializer
  deriving (Eq, Ord, Show, Read)

data VariableInitializer = VarInit VarExp | VarInitNil
  deriving (Eq, Ord, Show, Read)

data Type = Type TypeDef
  deriving (Eq, Ord, Show, Read)

data TypeDef
    = TypeDef Id | TypeGen Id Symbols Id Symbols | TypeArray Id
  deriving (Eq, Ord, Show, Read)

data Args = Args Type Id
  deriving (Eq, Ord, Show, Read)

data ImportFile = ImportFile Address
  deriving (Eq, Ord, Show, Read)

data Address = Address Id Add
  deriving (Eq, Ord, Show, Read)

data Add = AddBar Id Add | AddId Id
  deriving (Eq, Ord, Show, Read)

data CondExp
    = CondExpId Id CondExp
    | CondExpSymb Symbols CondExp
    | CondExpInt Integer CondExp
    | CondExpDouble Double CondExp
    | CondExpTimes CondExp
    | CondExpParent CondExp CondExp
    | CondExpDot CondExp
    | CondExpCorchete CondExp CondExp
    | CondExpComma CondExp
    | CondExpSlash CondExp
    | CondExpEq CondExp
    | CondExpBar CondExp
    | CondExpNil
  deriving (Eq, Ord, Show, Read)

data VarExp
    = VarExpId Id VarExp
    | VarExpSymb Symbols VarExp
    | VarExpInt Integer VarExp
    | VarExpDouble Double VarExp
    | VarExpTimes VarExp
    | VarExpParent VarExp VarExp
    | VarExpBrack VarExp VarExp
    | VarExpDot VarExp
    | VarExpComma VarExp
    | VarExpCorchete VarExp VarExp
    | VarExpSlash VarExp
    | VarExpBar VarExp
    | VarExpNil
  deriving (Eq, Ord, Show, Read)

data Expressions
    = ExpId Id Expressions
    | ExpSymb Symbols Expressions
    | ExpInt Integer Expressions
    | ExpDouble Double Expressions
    | ExpTimes Expressions
    | ExpDot Expressions
    | ExpBrack Expressions Expressions
    | ExpParent Expressions Expressions
    | ExpCorchete Expressions Expressions
    | ExpEq Expressions
    | ExpSemiColon Expressions
    | ExpBSlash Expressions
    | ExpComma Expressions
    | ExpSlash Expressions
    | ExpBar Expressions
    | ExpNil
  deriving (Eq, Ord, Show, Read)

data Java = Java Expressions
  deriving (Eq, Ord, Show, Read)

data JML = JML Expressions
  deriving (Eq, Ord, Show, Read)

