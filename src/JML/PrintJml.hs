{-# OPTIONS_GHC -fno-warn-incomplete-patterns #-}
module JML.PrintJml where

-- pretty-printer generated by the BNF converter

import JML.AbsJml
import Data.Char


-- the top-level printing method
printTree :: Print a => a -> String
printTree = render . prt 0

type Doc = [ShowS] -> [ShowS]

doc :: ShowS -> Doc
doc = (:)

-- Modify to remove white space before '[' and '('
-- Modify to remove white space between ==
-- Modify to remove white spaces around '.'
-- Modify to remove white space after '\\' and '!'
-- Modify to remove white space in "> =", "< =" , "! =" "& &" and "| |"
-- Modify to remove white space after openning \" and before closing \"
render :: Doc -> String
render d = rend 0 (map ($ "") $ d []) "" where
  rend i ss = case ss of
    "\\"     :ts -> showChar '\\' . rend i ts
    t:"+":"+":ts -> showString t . showChar '+' . space "+" . rend i ts
    t:"-":"-":ts -> showString t . showChar '-' . space "-" . rend i ts
    t: "%"   :ts -> space t . showChar '%' . rend i ts
    t: "."   :ts -> showString t . showChar '.' . rend i ts 
    "=" :"=" :ts -> showChar '=' . space "=" . rend i ts
    ">" :"=" :ts -> showChar '>' . space "=" . rend i ts
    "<" :"=" :ts -> showChar '<' . space "=" . rend i ts
    "!" :"=" :ts -> showChar '!' . space "=" . rend i ts
    "!" :t   :ts -> showChar '!' . showString t . rend i ts
    "&" :"&" :ts -> showChar '&' . space "&" . rend i ts
    "|" :"|" :ts -> showChar '|' . space "|" . rend i ts
    t : "["  :ts -> showString t . showChar '[' . rend i ts
    t : "("  :ts -> showString t . showChar '(' . rend i ts
    "{"      :ts -> showChar '{' . new (i+1) . rend (i+1) ts
    "}" : ";":ts -> new (i-1) . space "}" . showChar ';' . new (i-1) . rend (i-1) ts
    "}"      :ts -> new (i-1) . showChar '}' . new (i-1) . rend (i-1) ts
    ";"      :ts -> showChar ';' . new i . rend i ts
    t  : "," :ts -> showString t . space "," . rend i ts
    t  : ")" :ts -> showString t . showString ") " . rend i ts
    t  : "]" :ts -> showString t . showChar ']' . rend i ts
    "\""     :ts -> showChar '\"' . rend i ts
    t  :"\"" :ts -> if (t == " ") then showChar '\"' . rend i ts 
                                  else showString t . showChar '\"' . rend i ts 
    t        :ts -> space t . rend i ts
    _            -> id
  new i   = showChar '\n' . replicateS (2*i) (showChar ' ') . dropWhile isSpace
  space t = showString t . (\s -> if null s then "" else (' ':s))

parenth :: Doc -> Doc
parenth ss = doc (showChar '(') . ss . doc (showChar ')')

concatS :: [ShowS] -> ShowS
concatS = foldr (.) id

concatD :: [Doc] -> Doc
concatD = foldr (.) id

replicateS :: Int -> ShowS -> ShowS
replicateS n f = concatS (replicate n f)

-- the printer class does the job
class Print a where
  prt :: Int -> a -> Doc
  prtList :: Int -> [a] -> Doc
  prtList i = concatD . map (prt i)

instance Print a => Print [a] where
  prt = prtList

instance Print Char where
  prt _ s = doc (showChar '\'' . mkEsc '\'' s . showChar '\'')
  prtList _ s = doc (showChar '"' . concatS (map (mkEsc '"') s) . showChar '"')

mkEsc :: Char -> Char -> ShowS
mkEsc q s = case s of
  _ | s == q -> showChar '\\' . showChar s
  '\\'-> showString "\\\\"
  '\n' -> showString "\\n"
  '\t' -> showString "\\t"
  _ -> showChar s

prPrec :: Int -> Int -> Doc -> Doc
prPrec i j = if j<i then parenth else id


instance Print Integer where
  prt _ x = doc (shows x)


instance Print Double where
  prt _ x = doc (shows x)



instance Print IdJml where
  prt _ (IdJml i) = doc (showString ( i))


instance Print Symbols where
  prt _ (Symbols i) = doc (showString ( i))



instance Print JML where
  prt i e = case e of
    JMLAnd jml1 jml2 -> prPrec i 0 (concatD [prt 0 jml1, doc (showString "&&"), prt 0 jml2])
    JMLOr jml1 jml2 -> prPrec i 0 (concatD [prt 0 jml1, doc (showString "||"), prt 0 jml2])
    JMLImp jml1 jml2 -> prPrec i 0 (concatD [prt 0 jml1, doc (showString "==>"), prt 0 jml2])
    JMLIff jml1 jml2 -> prPrec i 0 (concatD [prt 0 jml1, doc (showString "<==>"), prt 0 jml2])
    JMLForallRT type_ idjml bodyf -> prPrec i 0 (concatD [doc (showString "("), doc (showString "\\forall"), prt 0 type_, prt 0 idjml, prt 0 bodyf, doc (showString ")")])
    JMLExistsRT type_ idjml bodyf -> prPrec i 0 (concatD [doc (showString "("), doc (showString "\\exists"), prt 0 type_, prt 0 idjml, prt 0 bodyf, doc (showString ")")])
    JMLPar jml -> prPrec i 0 (concatD [doc (showString "("), prt 0 jml, doc (showString ")")])
    JMLNeg symbols jml -> prPrec i 0 (concatD [prt 0 symbols, prt 0 jml])
    JMLExp expressions -> prPrec i 0 (concatD [prt 0 expressions])

instance Print BodyF where
  prt i e = case e of
    BodyF rangeterm -> prPrec i 0 (concatD [doc (showString ";"), prt 0 rangeterm])

instance Print RangeTerm where
  prt i e = case e of
    RangeTerm jml1 jml2 -> prPrec i 0 (concatD [prt 0 jml1, doc (showString ";"), prt 0 jml2])
    OnlyRange jml -> prPrec i 0 (concatD [prt 0 jml])

instance Print Type where
  prt i e = case e of
    Type idjml -> prPrec i 0 (concatD [prt 0 idjml])

instance Print Expression where
  prt i e = case e of
    Exp idjml -> prPrec i 0 (concatD [prt 0 idjml])
    ExpS symbols -> prPrec i 0 (concatD [prt 0 symbols])
    ExpRes -> prPrec i 0 (concatD [doc (showString "\\result")])
    ExpOld jml -> prPrec i 0 (concatD [doc (showString "\\old"), doc (showString "("), prt 0 jml, doc (showString ")")])
    ExpTypeOf jml -> prPrec i 0 (concatD [doc (showString "\\typeof"), doc (showString "("), prt 0 jml, doc (showString ")")])
    ExpType jml -> prPrec i 0 (concatD [doc (showString "\\type"), doc (showString "("), prt 0 jml, doc (showString ")")])
    ExpInv jml -> prPrec i 0 (concatD [doc (showString "\\invariant_for"), doc (showString "("), prt 0 jml, doc (showString ")")])
    ExpDls content -> prPrec i 0 (concatD [doc (showString "\\dl_strContent"), doc (showString "("), prt 0 content, doc (showString ")")])
    ExpMC methodcall -> prPrec i 0 (concatD [prt 0 methodcall])
    ExpPar expressions -> prPrec i 0 (concatD [doc (showString "("), prt 0 expressions, doc (showString ")")])
  prtList _ [x] = (concatD [prt 0 x])
  prtList _ (x:xs) = (concatD [prt 0 x, prt 0 xs])
instance Print MethodCall where
  prt i e = case e of
    MC idjml argss -> prPrec i 0 (concatD [prt 0 idjml, doc (showString "("), prt 0 argss, doc (showString ")")])

instance Print Args where
  prt i e = case e of
    ArgsId idjml -> prPrec i 0 (concatD [prt 0 idjml])
    ArgsS str -> prPrec i 0 (concatD [prt 0 str])
  prtList _ [] = (concatD [])
  prtList _ [x] = (concatD [prt 0 x])
  prtList _ (x:xs) = (concatD [prt 0 x, doc (showString ","), prt 0 xs])
instance Print Content where
  prt i e = case e of
    ContentStr str -> prPrec i 0 (concatD [prt 0 str])
    ContentId idjml -> prPrec i 0 (concatD [prt 0 idjml])
    ContentMC methodcall -> prPrec i 0 (concatD [prt 0 methodcall])


