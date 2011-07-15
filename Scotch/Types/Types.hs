{-  This file is part of Scotch.

    Scotch is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Scotch is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Scotch.  If not, see <http://www.gnu.org/licenses/>.
-}

module Scotch.Types.Types where

import Data.Binary
import Data.List
import Numeric

formatString [] = []
formatString (h:t) = if h == '"' then "\\\"" ++ formatString t
                     else h : formatString t
                     
                     
-- binds a left term to a right term
type Binding = (Expr, Expr)
                     

-- a value identifier
type Id = String
-- a value with its corresponding type
data Value = NumInt Integer
           | NumFloat Double
           | Str String
           | Bit Bool
           | Hash [[(String, Expr)]]
           | Null
           | Lambda [Id] Expr
           | Proc [Expr]
           | Thread Expr
           | Undefined String
           | File String
           | InvalidValue
           deriving Eq
instance Show (Value) where
    show (Str s) = "\"" ++ formatString s ++ "\""
    show (NumInt n) = show n
    show (NumFloat n) = showFFloat Nothing n ""
    show (Bit True) = "true"
    show (Bit False) = "false"
    show (Hash h) = "{" ++ (if length items > 0
                            then tail $ tail (foldl (++) "" items)
                            else "") ++ "}"
                           where items = [", \"" ++ fst i ++ "\": " ++ show (snd i) | j <- h, i <- j]
    show (Lambda ids expr) = "(" ++ tail (foldl (++) "" ["," ++ id | id <- ids]) ++ ") -> " ++ show expr
    show (Proc p) = "do " ++ foldl (++) "" [show i ++ ";" | i <- p]
    show (Thread th) = "thread " ++ show th
    show (Null) = "null"
    show (Undefined s) = show s
    show (File f) = "file(" ++ show f ++ ")"
    show InvalidValue = "**invalid value**"
instance Binary(Value) where
    put (Str s) =           do put (4 :: Word8)
                               put s
    put (NumInt n) =        do put (5 :: Word8)
                               put n
    put (NumFloat n) =      do put (6 :: Word8)
                               put n
    put (Bit b) =           do put (7 :: Word8)
                               put b
    put (Hash h) =          do put (9 :: Word8)
                               put h
    put (Lambda i e) =      do put (11 :: Word8)
                               put i
                               put e
    put (Proc p) =          do put (12 :: Word8)
                               put p
    put (Thread th) =       do put (13 :: Word8)
                               put th
    put (Null) =            do put (14 :: Word8)
    put (Undefined s) =     do put (15 :: Word8)
                               put s
    put (File f) =          do put (16 :: Word8)
                               put f
    get = do t <- get :: Get Word8
             case t of 
               4 ->     do s <- get
                           return $ Str s
               5 ->     do n <- get
                           return $ NumInt n
               6 ->     do n <- get
                           return $ NumFloat n
               7 ->     do b <- get
                           return $ Bit b
               9 ->     do h <- get
                           return $ Hash h
               11 ->    do i <- get
                           e <- get
                           return $ Lambda i e
               12 ->    do p <- get
                           return $ Proc p
               13 ->    do th <- get
                           return $ Thread th
               14 ->    do return $ Null
               15 ->    do s <- get
                           return $ Undefined s
               16 ->    do f <- get
                           return $ File f

-- represents an arithmetic expression
data Expr = Exception String                -- undefined
          | Skip                            -- returns Null
          | Val (Value)                     -- value
          | List [Expr]                     -- list expression
          | Take Expr Expr                  -- take _ from _
          | HashExpr [(Expr, Expr)]         -- hash expression
          | ToInt (Expr)                    -- conversion to integer
          | ToFloat (Expr)                  -- conversion to float
          | ToStr (Expr)                    -- conversion to string
          | ToList (Expr)                   -- conversion to list
          | ToBool (Expr)                   -- conversion to boolean
          | Subs Expr Expr                  -- list subscript
          | Concat Expr Expr                -- list concatenation
          | Add Expr Expr                   -- addition
          | Sub Expr Expr                   -- subtraction
          | Prod Expr Expr                  -- product
          | Neg Expr                        -- negation
          | Div Expr Expr                   -- division
          | Mod Expr Expr                   -- find remainder
          | Exp Expr Expr                   -- exponent
          | Eq Expr Expr                    -- equality
          | InEq Expr Expr                  -- inequality
          | Gt Expr Expr                    -- greater than
          | Lt Expr Expr                    -- less than
          | And Expr Expr                   -- boolean and
          | Or Expr Expr                    -- boolean or
          | Not Expr                        -- boolean not
          | Def Expr Expr Expr              -- rewriting rule assignment
          | EagerDef Expr Expr Expr         -- eager assignment
          | Var Id                          -- identifier with optional list of values
          | Call Expr [Expr]                -- call an expression representing a function
          | If Expr Expr Expr               -- conditional
          | Case Expr [(Expr, Expr)]        -- case expression
          | For Id (Expr) (Expr) [Expr]     -- iteration
          | TakeFor Id (Expr) (Expr) [Expr] Integer
                                            -- take from list comprehension
          | Range (Expr) (Expr) (Expr)      -- range
          | Output Expr                     -- output
          | Input                           -- get a line of input from the user
          | Import [String] [String]        -- import module
          | FileObj Expr                    -- file object
          | FileRead Expr                   -- read file
          | FileWrite Expr Expr             -- write to file
          | FileAppend Expr Expr            -- append to file
          | EvalExpr Expr                   -- eval for metaprogramming
          | Rule [Expr]                     -- a rule (list of definitions)
          | UseRule (Expr) (Expr)           -- evaluate using a rule
          deriving Eq
instance Show(Expr) where
    show (Exception s) = "Exception: " ++ s
    show Skip = ""
    show (Val v) = show v
    show (List l) = show l
    show (Take a b) = "take " ++ show a ++ " from " ++ show b
    show (TakeFor a b c d e) = show (Take (Val (NumInt e)) (For a b c d))
    show (HashExpr h) = "{" ++ (if length items > 0
                                then tail (foldl (++) "" items)
                                else "") ++ "}"
                               where items = ["," ++ show (fst i) ++ ":" ++ show (snd i) | i <- h]
    show (ToInt i) = "int(" ++ show i ++ ")"
    show (ToFloat f) = "float(" ++ show f ++ ")"
    show (ToStr s) = "str(" ++ show s ++ ")"
    show (ToList l) = "list(" ++ show l ++ ")"
    show (ToBool b) = "bool(" ++ show b ++ ")"
    show (Concat a b) = "(" ++ show a ++ " : " ++ show b ++ ")"
    show (Subs n s) = show s ++ " @" ++ show n
    show (Add x y) = "(" ++ show x ++ " + " ++ show y ++ ")"
    show (Sub x y) = "(" ++ show x ++ " - " ++ show y ++ ")"
    show (Prod (Val (NumInt x)) (Var y)) = show x ++ y
    show (Prod (Val (NumInt x)) y) = show x ++ if show y !! 0 == '(' then show y else "(" ++ show y ++ ")"
    show (Prod (Val (NumFloat x)) (Val y)) = show x ++ if show y !! 0 == '(' then show y else "(" ++ show y ++ ")"
    show (Prod x y) = "(" ++ show x ++ " * " ++ show y ++ ")"
    show (Div x y) = "(" ++ show x ++ " / " ++ show y ++ ")"
    show (Mod x y) = "(" ++ show x ++ " mod " ++ show y ++ ")"
    show (Exp x y) = "(" ++ show x ++ " ^ " ++ show y ++ ")"
    show (Eq x y) = "(" ++ show x ++ " == " ++ show y ++ ")"
    show (InEq x y) = "(" ++ show x ++ " != " ++ show y ++ ")"
    show (Gt x y) = "(" ++ show x ++ " > " ++ show y ++ ")"
    show (Lt x y) = "(" ++ show x ++ " < " ++ show y ++ ")"
    show (And x y) = "(" ++ show x ++ " & " ++ show y ++ ")"
    show (Or x y) = "(" ++ show x ++ " | " ++ show y ++ ")"
    show (Not x) = "not " ++ show x
    show (Def a (Rule r) Skip) = "rule " ++ show a ++ " =" ++ show (Rule r)
    show (Rule r) = tail $ tail (foldl (++) "" [", " ++ show i | i <- r])
    show (Def a b Skip) = show a ++ " = " ++ show b
    show (Def a b c) = "(" ++ show c ++ " where " ++ show a ++ " = " ++ show b ++ ")"
    show (EagerDef a b Skip) = show a ++ " := " ++ show b
    show (EagerDef a b c) = "(" ++ show c ++ " where " ++ show a ++ " := " ++ show b ++ ")"
    show (UseRule r x) = "using " ++ show r ++ " => " ++ show x
    show (Var f) = f
    show (Call f args) = show f ++ removeBrackets (show args)
    show (If (ToBool cond) x y) = "if " ++ show cond ++ " then " ++ show x ++ " else " ++ show y
    show (If cond x y) = "if " ++ show cond ++ " then " ++ show x ++ " else " ++ show y
    show (Case c o) = "case " ++ show c ++ " of" ++ tail (foldl (++) "" [", " ++ show (fst i) ++ " -> " ++ show (snd i) | i <- o])
    show (For x (ToList y) z w) = "[for " ++ show x ++ " in " ++ show y ++ ", " ++ show z ++ (foldl (++) "" [", " ++ show w' | w' <- w]) ++ "]"
    show (For x y z w) = "[for " ++ show x ++ " in " ++ show y ++ ", " ++ show z ++ (foldl (++) "" [", " ++ show w' | w' <- w]) ++ "]"
    show (Range x y z) = "[" ++ show x ++ ".." ++ show y ++ (if z == (Val (NumInt 1)) then "" else "," ++ show z) ++ "]"
    show (Output x) = "print(" ++ show x ++ ")"
    show Input = "input"
    show (Import s t) = "import " ++ (show s) ++ (if s == t then "" 
                                                  else " as " ++ show t)
    show (FileObj f) = "file(" ++ show f ++ ")"
    show (FileRead f) = "read(" ++ show f ++ ")"
    show (FileWrite f x) = "write(" ++ show f ++ ", " ++ show x ++ ")"
    show (FileAppend f x) = "append(" ++ show f ++ ", " ++ show x ++ ")"
    show (EvalExpr e) = "eval(" ++ show e ++ ")"
instance Binary(Expr) where
    put (Exception s) =     do put (18 :: Word8)
                               put s
    put (Skip) =            do put (19 :: Word8)
    put (Val v) =           do put (20 :: Word8)
                               put v
    put (List l) =          do put (21 :: Word8)
                               put l
    put (Take a b) =        do put (22 :: Word8)
                               put a
                               put b
    put (HashExpr h) =      do put (23 :: Word8)
                               put h
    put (ToInt i) =         do put (24 :: Word8)
                               put i
    put (ToFloat f) =       do put (25 :: Word8)
                               put f
    put (ToStr s) =         do put (26 :: Word8)
                               put s
    put (ToList l) =        do put (27 :: Word8)
                               put l
    put (ToBool b) =        do put (45 :: Word8)
                               put b
    put (Subs n s) =        do put (28 :: Word8)
                               put n
                               put s
    put (Add a b) =         do put (29 :: Word8)
                               put a
                               put b
    put (Sub a b) =         do put (30 :: Word8)
                               put a
                               put b
    put (Prod a b) =        do put (31 :: Word8)
                               put a
                               put b
    put (Div a b) =         do put (32 :: Word8)
                               put a
                               put b
    put (Mod a b) =         do put (33 :: Word8)
                               put a
                               put b
    put (Exp a b) =         do put (34 :: Word8)
                               put a
                               put b
    put (Eq a b) =          do put (35 :: Word8)
                               put a
                               put b
    put (InEq a b) =        do put (36 :: Word8)
                               put a
                               put b
    put (Gt a b) =          do put (37 :: Word8)
                               put a
                               put b
    put (Lt a b) =          do put (38 :: Word8)
                               put a
                               put b
    put (And a b) =         do put (39 :: Word8)
                               put a
                               put b
    put (Or a b) =          do put (40 :: Word8)
                               put a
                               put b
    put (Not a) =           do put (41 :: Word8)
                               put a
    put (Def a b c) =       do put (42 :: Word8)
                               put a
                               put b
                               put c
    put (EagerDef a b c) =  do put (43 :: Word8)
                               put a
                               put b
                               put c
    put (Concat a b) =      do put (44 :: Word8)
                               put a
                               put b
    put (Call f p) =        do put (46 :: Word8)
                               put f
                               put p
    put (Var f) =           do put (47 :: Word8)
                               put f
    put (If a b c) =        do put (48 :: Word8)
                               put a
                               put b
                               put c
    put (Case a b) =        do put (49 :: Word8)
                               put a
                               put b
    put (For a b c d) =     do put (50 :: Word8)
                               put a
                               put b
                               put c
                               put d
    put (Range a b c) =     do put (51 :: Word8)
                               put a
                               put b
                               put c
    put (Output x) =        do put (52 :: Word8)
                               put x
    put (Input) =           do put (53 :: Word8)
    put (Import a b) =      do put (54 :: Word8)
                               put a
                               put b
    put (FileObj a) =       do put (55 :: Word8)
                               put a
    put (FileRead a) =      do put (56 :: Word8)
                               put a
    put (FileWrite a b) =   do put (57 :: Word8)
                               put a
                               put b
    put (FileAppend a b) =  do put (58 :: Word8)
                               put a
                               put b
    put (EvalExpr a) =      do put (61 :: Word8)
                               put a
    put (Rule a) =          do put (62 :: Word8)
                               put a
    put (UseRule a b) =     do put (63 :: Word8)
                               put a
                               put b
    get = do t <- get :: Get Word8
             case t of 
               18 ->    do s <- get
                           return $ Exception s
               19 ->    do return Skip
               20 ->    do v <- get
                           return $ Val v
               21 ->    do l <- get
                           return $ List l
               22 ->    do a <- get
                           b <- get
                           return $ Take a b
               23 ->    do h <- get
                           return $ HashExpr h
               24 ->    do i <- get
                           return $ ToInt i
               25 ->    do f <- get
                           return $ ToFloat f
               26 ->    do s <- get
                           return $ ToStr s
               27 ->    do l <- get
                           return $ ToList l
               45 ->    do b <- get
                           return $ ToBool b
               28 ->    do a <- get
                           b <- get
                           return $ Subs a b
               29 ->    do a <- get
                           b <- get
                           return $ Add a b
               30 ->    do a <- get
                           b <- get
                           return $ Sub a b
               31 ->    do a <- get
                           b <- get
                           return $ Prod a b
               32 ->    do a <- get
                           b <- get
                           return $ Div a b
               33 ->    do a <- get
                           b <- get
                           return $ Mod a b
               34 ->    do a <- get
                           b <- get
                           return $ Exp a b
               35 ->    do a <- get
                           b <- get
                           return $ Eq a b
               36 ->    do a <- get
                           b <- get
                           return $ InEq a b
               37 ->    do a <- get
                           b <- get
                           return $ Gt a b
               38 ->    do a <- get
                           b <- get
                           return $ Lt a b
               39 ->    do a <- get
                           b <- get
                           return $ And a b
               40 ->    do a <- get
                           b <- get
                           return $ Or a b
               41 ->    do a <- get
                           return $ Not a
               42 ->    do a <- get
                           b <- get
                           c <- get
                           return $ Def a b c
               43 ->    do a <- get
                           b <- get
                           c <- get
                           return $ EagerDef a b c
               44 ->    do a <- get
                           b <- get
                           return $ Concat a b
               46 ->    do a <- get
                           b <- get
                           return $ Call a b
               47 ->    do a <- get
                           return $ Var a
               48 ->    do a <- get
                           b <- get
                           c <- get
                           return $ If a b c
               49 ->    do a <- get
                           b <- get
                           return $ Case a b
               50 ->    do a <- get
                           b <- get
                           c <- get
                           d <- get
                           return $ For a b c d
               51 ->    do a <- get
                           b <- get
                           c <- get
                           return $ Range a b c
               52 ->    do a <- get
                           return $ Output a
               53 ->    do return $ Input
               54 ->    do a <- get
                           b <- get
                           return $ Import a b
               55 ->    do a <- get
                           return $ FileObj a
               56 ->    do a <- get
                           return $ FileRead a
               57 ->    do a <- get
                           b <- get
                           return $ FileWrite a b
               58 ->    do a <- get
                           b <- get
                           return $ FileAppend a b
               61 ->    do a <- get
                           return $ EvalExpr a
               62 ->    do a <- get
                           return $ Rule a
               63 ->    do a <- get
                           b <- get
                           return $ UseRule a b
type ExprPosition = (String, (Int, Int))
type PosExpr = (Maybe ExprPosition, Expr)

removeBrackets s = if (s !! 0) == '[' && (s !! (l-1)) == ']'
                   then "(" ++ [s !! n | n <- [1..l-2]] ++ ")"
                   else s
                   where l = length s
