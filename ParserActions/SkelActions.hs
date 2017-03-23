module SkelActions where

-- Haskell module generated by the BNF converter

import AbsActions
import ErrM
type Result = Err String

failure :: Show a => a -> Result
failure x = Bad $ "Undefined case: " ++ show x

transIdAct :: IdAct -> Result
transIdAct x = case x of
  IdAct string -> failure x
transActions :: Actions -> Result
transActions x = case x of
  Actions actions -> failure x
transAction :: Action -> Result
transAction x = case x of
  ActProg program -> failure x
  ActBlock actions -> failure x
  ActCreate template argss -> failure x
  ActBang idact -> failure x
  ActCond idacts action -> failure x
  ActSkip -> failure x
  ActLog string params -> failure x
  ActArith arith -> failure x
  ActAssig ass -> failure x
transProgram :: Program -> Result
transProgram x = case x of
  Prog idact argss -> failure x
transAss :: Ass -> Result
transAss x = case x of
  Ass idact val -> failure x
  AssInc idact val -> failure x
  AssDec idact val -> failure x
transArith :: Arith -> Result
transArith x = case x of
  Arith idact -> failure x
transVal :: Val -> Result
transVal x = case x of
  ValMC program -> failure x
  ValV idact val -> failure x
  ValS string -> failure x
  ValNew val -> failure x
  ValNil -> failure x
transType :: Type -> Result
transType x = case x of
  TypeNil -> failure x
  Type idact -> failure x
transTemplate :: Template -> Result
transTemplate x = case x of
  Temp idact -> failure x
transArgs :: Args -> Result
transArgs x = case x of
  ArgsId idact -> failure x
  ArgsS string -> failure x
  ArgsNew program -> failure x
transParams :: Params -> Result
transParams x = case x of
  ParamsNil -> failure x
  Params params -> failure x
transParam :: Param -> Result
transParam x = case x of
  Param idact -> failure x

