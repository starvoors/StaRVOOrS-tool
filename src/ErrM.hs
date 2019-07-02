-- BNF Converter: Error Monad
-- Copyright (C) 2004  Author:  Aarne Ranta

-- This file comes with NO WARRANTY and may be used FOR ANY PURPOSE.
module ErrM where

-- the Error monad: like Maybe type with error msgs

import Control.Monad (MonadPlus(..), liftM)
import Control.Applicative (Applicative(..), Alternative(..))

data Err a = Ok a | Bad String
  deriving (Read, Show, Eq, Ord)

instance Monad Err where
  return      = Ok
  fail        = Bad
  Ok a  >>= f = f a
  Bad s >>= _ = Bad s

instance Applicative Err where
  pure = Ok
  (Bad s) <*> _ = Bad s
  (Ok f) <*> o  = liftM f o


instance Functor Err where
  fmap = liftM

instance MonadPlus Err where
  mzero = Bad "Err.mzero"
  mplus (Bad _) y = y
  mplus x       _ = x

instance Alternative Err where
  empty = mzero
  (<|>) = mplus

partitionErr :: [Err a] -> ([Err a],[Err a])
partitionErr []     = ([],[])
partitionErr (x:xs) = let (ls,rs) = partitionErr xs 
                      in case x of
                             Ok a  -> (ls,x:rs)
                             Bad s -> (x:ls,rs)

fromOK :: Err a -> a
fromOK (Ok a)  = a

fromBad :: Err a -> String
fromBad (Bad s) = s

isBad :: Err a -> Bool
isBad (Bad _) = True
isBad _       = False
