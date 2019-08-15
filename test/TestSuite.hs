{-# LANGUAGE TemplateHaskell #-}

module TestSuite where

import Control.Lens hiding(Context)

testSuite :: [Test]
testSuite = 
 [ test_automata_communication_1 
 , test_grammar
 , test_hoare_triples_behaviour
 , test_monitor_behaviour
 , test_pinit_section
 , test_templates_behaviour
 ]

data Option = Yes | No deriving(Eq,Show)

type Program = [String]

data Test = 
 Test { _name          :: String --Name of the test
      , _specification :: String --Name of the specification to analyse
      , _parsing       :: Option --Test the parsing of the specification
      , _translation   :: Option --Test the larve specification generated
      , _ppdRefinement :: Option --Test the refinement in the specification
      , _monitorExec   :: (Option,Program) --Test the monitor against the provided program
      }

-----------
-- Tests --
-----------

test_automata_communication_1 :: Test
test_automata_communication_1 = 
 Test "automata_communication_case_1" "automata_communication.ppd" No Yes No (Yes,prog1)

prog1 :: Program
prog1 = [ "CMachine cm = new CMachine(2);\n\n"
        , "cm.brew();\n"
        , "cm.brew();\n"
        , "cm.cleanF();\n"
        , "cm.brew();\n"
        , "cm.brew();\n"
        ]

test_grammar :: Test
test_grammar = Test "grammar" "grammar.ppd" Yes No No (No,[])

test_hoare_triples_behaviour :: Test
test_hoare_triples_behaviour = 
 Test "hoare_triples_behaviour" "hoare_triples_behaviour.ppd" No Yes Yes (Yes,[])

test_monitor_behaviour :: Test
test_monitor_behaviour = Test "monitor_behaviour" "monitor_behaviour.ppd" No Yes Yes (Yes,[])

test_pinit_section :: Test
test_pinit_section = Test "pinit_section" "pinit_section.ppd" No Yes Yes (Yes,[])

test_templates_behaviour :: Test
test_templates_behaviour = Test "templates_behaviour" "templates_behaviour.ppd" No Yes Yes (Yes,[])

------------
-- Lenses --
------------

-- ^. is view, e.g. ppd ^. importsGet
-- %~ is over, e.g. importsGet %~ foo $ ppd
-- .~ is set, e.g. importsGet .~ imps $ ppd

makeLenses ''Test
