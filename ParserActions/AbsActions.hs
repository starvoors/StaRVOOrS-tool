

module AbsActions where

-- Haskell module generated by the BNF converter




newtype IdAct = IdAct String deriving (Eq, Ord, Show, Read)
data Actions = Actions [Action]
  deriving (Eq, Ord, Show, Read)

data Action
    = ActProg Program
    | ActBlock Actions
    | ActCreate Template [Args]
    | ActBang IdAct
    | ActCond [IdAct] Action
    | ActSkip
    | ActLog String Params
    | ActArith Arith
    | ActAssig Ass
  deriving (Eq, Ord, Show, Read)

data Program = Prog IdAct [Args]
  deriving (Eq, Ord, Show, Read)

data Ass = Ass IdAct Val | AssInc IdAct Val | AssDec IdAct Val
  deriving (Eq, Ord, Show, Read)

data Arith = Arith IdAct
  deriving (Eq, Ord, Show, Read)

data Val
    = ValMC Program
    | ValV IdAct Val
    | ValS String
    | ValNew Val
    | ValNil
  deriving (Eq, Ord, Show, Read)

data Type = TypeNil | Type IdAct
  deriving (Eq, Ord, Show, Read)

data Template = Temp IdAct
  deriving (Eq, Ord, Show, Read)

data Args
    = ArgsId IdAct
    | ArgsS String
    | ArgsNew Program
    | ArgsActLog String Params
    | ArgsActIF [IdAct] Action
    | ArgsActProg Program
    | ArgsActBang IdAct
    | ArgsActAss Ass
    | ArgsActBlock Actions
  deriving (Eq, Ord, Show, Read)

data Params = ParamsNil | Params [Param]
  deriving (Eq, Ord, Show, Read)

data Param = Param IdAct
  deriving (Eq, Ord, Show, Read)

