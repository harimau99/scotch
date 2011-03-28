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

module Scotch.Eval.Substitute where

import Scotch.Types.Types
import Scotch.Types.Bindings
import Scotch.Types.Hash
import Scotch.Eval.Calc
import Data.List

-- if expression x should be rewritten, return the rewritten expression;
-- otherwise, returns an InvalidValue
rewrite :: Expr -> [Binding] -> [Binding] -> Expr
rewrite x [] allDefs = parseExpr x rewrite'
                       where rewrite' x = rewrite x allDefs allDefs
rewrite x (h:t) allDefs = 
  if fst match 
  then substitute (snd h) (snd match)
  else rewrite x t allDefs
  where match = patternMatch x (fst h) True

nameMatch x y = x == y || isSuffixOf ("." ++ y) ("." ++ x)

-- check if expression x matches definition y
patternMatch :: Expr -> Expr -> Bool -> (Bool, [Binding])
patternMatch x y tl =
  case (x, y) of
    (_, Var v2) ->              case tl of
                                  True -> case x of
                                            Var v1 -> (nameMatch v2 v1, [])
                                            otherwise -> (False, [])
                                  False -> (True, if x == y 
                                                  then []
                                                  else [(y, x)])
    (Call (Var v1) args1, 
     Call (Var v2) args2) -> 
                                if length args1 == length args2
                                   && nameMatch v2 v1
                                then trySubs 
                                     [patternMatch (args1 !! n) (args2 !! n) False
                                      | n <- [0 .. (length args1) - 1]]
                                else (False, [])
    (_, Concat (Var v1) 
               (Var v2)) ->     case x of
                                  List l ->         if length l > 0 
                                                    then (True, [(Var v1, head l),
                                                                 (Var v2, List (tail l))])
                                                    else (False, [])
                                  Val (Str l) ->    if length l > 0 
                                                    then (True, [(Var v1, Val (Str [head l])),
                                                                 (Var v2, Val (Str (tail l)))])
                                                    else (False, [])
                                  otherwise -> (False, [])
    (Add a b, Add c d) ->       trySubs [patternMatch' a c, patternMatch' b d]
    (Sub a b, Sub c d) ->       trySubs [patternMatch' a c, patternMatch' b d]
    (Prod a b, Prod c d) ->     trySubs [patternMatch' a c, patternMatch' b d]
    (Div a b, Div c d) ->       trySubs [patternMatch' a c, patternMatch' b d]
    (Exp a b, Exp c d) ->       trySubs [patternMatch' a c, patternMatch' b d]
    otherwise ->                if veq False x y == Val (Bit True)
                                then (True, []) else (False, [])
  where trySubs exprs = if all ((==) True) [fst expr | expr <- exprs]
                        then (True, foldl (++) [] [snd expr | expr <- exprs])
                        else (False, [])
        patternMatch' a b = patternMatch a b False
                        

substitute :: Expr -> [Binding] -> Expr
substitute exp [] = exp
substitute exp params =
  case lookup exp params of
    Just expr -> expr
    otherwise -> parseExpr exp substitute'
                 where substitute' x = substitute x params
      
parseExpr exp f =
  case exp of
    Call id args -> Call (f id) [f arg | arg <- args]
    Val (Proc p) -> Val (Proc ([f e | e <- p]))
    Val (Lambda ids expr) -> Val (Lambda ids (f expr))
    Val (Thread e) -> Val (Thread (f e))
    Take n x -> Take (f n) (f x)        
    ToInt x -> ToInt (f x)
    ToFloat x -> ToFloat (f x)
    ToStr x -> ToStr (f x)
    ToList l -> ToList (f l)
    List l -> List [f e | e <- l]    
    HashExpr l -> HashExpr [(f (fst kv), f (snd kv)) | kv <- l]
    Subs n x -> Subs (f n) (f x)
    Concat x y -> Concat (f x) (f y)
    Add x y -> Add (f x) (f y)
    Sub x y -> Sub (f x) (f y)
    Prod x y -> Prod (f x) (f y)
    Div x y -> Div (f x) (f y)
    Mod x y -> Mod (f x) (f y)
    Exp x y -> Exp (f x) (f y)
    Eq x y -> Eq (f x) (f y)
    InEq x y -> InEq (f x) (f y)
    Gt x y -> Gt (f x) (f y)
    Lt x y -> Lt (f x) (f y)
    And x y -> And (f x) (f y)
    Or x y -> Or (f x) (f y)
    Not x -> Not (f x)
    Def id x y -> Def id (f x) (f y)
    EagerDef id x y -> EagerDef id (f x) (f y)
    If x y z -> If (f x) (f y) (f z)
    Case c opts -> Case (f c) [(fst opt, f (snd opt)) | opt <- opts]
    For id x y z -> For id (f x) (f y) [f i | i <- z]
    TakeFor id x y z n -> TakeFor id (f x) (f y) [f i | i <- z] n
    Range x y z -> Range (f x) (f y) (f z)
    Output x -> Output (f x)
    FileObj x -> FileObj (f x)
    FileRead x -> FileRead (f x)
    FileWrite a x -> FileWrite (f a) (f x)
    FileAppend a x -> FileAppend (f a) (f x)
    EvalExpr x -> EvalExpr (f x)
    otherwise -> otherwise
