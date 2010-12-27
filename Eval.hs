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

module Eval where

import System.Directory
import Types
import Bindings
import Calc
import Substitute

-- evalList: checks a list for exceptions
evalList [] = Val (Bit True)
evalList (h:t) = case h of                   
                   Exception e -> Exception e
                   Val (Undefined e) -> Exception e
                   otherwise -> evalList t

-- eval: computes the Val of an expression as far as possible
weval :: Expr -> [Binding] -> Expr
weval exp vars = case exp of
  Import s ->           Skip
  ListExpr l ->         case (evalList l) of
                          Val _ -> case evalList [Val item | item <- l'] of
                                     Exception e -> Exception e
                                     otherwise -> Val $ List l'
                                   where l' = [case eval item vars of
                                                 Val r -> r
                                                 Exception e -> Undefined e
                                                 otherwise -> Undefined (show otherwise)
                                               | item <- l]
                          Exception e -> Exception e
                        where r = [(case (weval item vars) of
                                      Val r -> Val r
                                      Exception e -> Exception e
                                    ) | item <- l]
  Val x ->              case x of
                          Undefined s -> Exception s
                          otherwise -> Val x
  ToInt x ->            case (weval x vars) of
                          Val (NumInt i) -> Val $ NumInt i
                          Val (NumFloat f) -> Val $ NumInt (truncate f)
                          Val (Str s) -> Val $ NumInt (read s)
                          otherwise -> Exception ("Can't convert " ++ show otherwise ++ " to integer.")
  ToFloat x ->          case (weval x vars) of
                          Val (NumInt i) -> Val $ NumFloat (fromIntegral i)
                          Val (NumFloat f) -> Val $ NumFloat f
                          Val (Str s) -> Val $ NumFloat (read s :: Double)
                          otherwise -> Exception ("Can't convert " ++ show otherwise ++ " to float.")
  ToStr x ->            case (weval x vars) of                       
                          Val (Str s) -> Val $ Str s
                          otherwise -> Val $ Str (show otherwise)
  Subs n x ->           case (weval x vars) of
                          Val (List l) -> case (weval n vars) of
                                            Val (NumInt n) -> if n >= 0 && 
                                                                 n < (fromIntegral (length l))
                                                              then Val (l !! (fromIntegral n))
                                                              else Exception ("Member " ++ show n ++ " not in list")
                                            otherwise ->      Exception ("Non-numerical subscript " ++ show otherwise)
                          Val (Str s) ->  case (weval n vars) of
                                            Val (NumInt n) -> if n >= 0 && 
                                                                 n < (fromIntegral (length s))
                                                              then Val (Str ([s !! (fromIntegral n)]))
                                                              else Exception ("Member " ++ show n ++ " not in list")
                                            otherwise ->      Exception ("Non-numerical subscript " ++ show otherwise)
                          otherwise ->    Exception "Subscript of non-list"
  Add x y ->            calc (weval x vars) (weval y vars) (vadd)
  Sub x y ->            calc (weval x vars) (weval y vars) (vsub)
  Prod x y ->           calc (weval x vars) (weval y vars) (vprod)
  Div x y ->            calc (weval x vars) (weval y vars) (vdiv)
  Exp x y ->            calc (weval x vars) (weval y vars) (vexp)
  Eq x y ->             calc (weval x vars) (weval y vars) (veq)
  InEq x y ->           case calc (weval x vars) (weval y vars) (veq) of
                          Val (Bit True) -> Val (Bit False)
                          Val (Bit False) -> Val (Bit True)
                          otherwise -> otherwise                    
  Gt x y ->             calc (weval x vars) (weval y vars) (vgt)
  Lt x y ->             calc (weval x vars) (weval y vars) (vlt)                    
  And x y ->            calc (weval x vars) (weval y vars) (vand)
  Or x y ->             calc (weval x vars) (weval y vars) (vor)
  Not x ->              case weval x vars of
                          Exception s -> Exception s
                          Val r -> case r of
                                     Bit b -> Val (Bit (not b))
                                     otherwise -> Exception "Expected boolean"
  Def f x y ->          weval y ((f, ([], x)) : vars)
  EagerDef f x y ->     weval y ((f, ([], eager_eval x vars)) : vars)
  Defun f p x y ->      weval y ((f, (p, x)) : 
                                 (f, ([], Val (HFunc f))) : 
                                 vars)
  Defproc f p x y ->    weval y ((f, (p, Val (Proc x))) : 
                                 (f, ([], Val (HFunc f))) : 
                                 vars)
  Var x ->              weval (snd (var_binding x vars)) vars
  Func f args ->        case vardef of
                          Val (HFunc (h)) -> if length params > 0 
                                             then case expr of
                                                    Func f' args' -> if fp == f' 
                                                                     then tailcall fp args args'
                                                                     else newcall
                                                    otherwise -> newcall
                                             else case snd $ var_binding fp vars of
                                                    Func f' args' -> weval (Func f' (args' ++ args)) vars
                                                    otherwise -> Exception $ show expr
                          Func f' args' -> weval (Func f' (args' ++ args)) vars
                          otherwise -> Exception $ "Variable " ++ (show f) ++ " isn't a function"
                        where fp = case vardef of
                                     Val (HFunc (f')) -> f'
                                     otherwise -> f
                              vardef = snd $ var_binding f vars
                              definition = func_binding fp args vars
                              params = fst definition
                              expr = snd definition
                              newcall = weval (substitute expr (funcall (zip params args))) vars
                              tailcall f args args' = if definition' == definition 
                                                      then tailcall f [case weval (substitute (args' !! n) (funcall (zip params args))) vars of
                                                                        Val r -> Val r
                                                                        otherwise -> Exception $ show otherwise
                                                                       | n <- [0 .. (length args') - 1]] args'
                                                      else weval (substitute (snd definition') (funcall (zip (fst definition') args))) vars
                                                      where definition' = func_binding f args vars
                                                 
  If cond x y ->        case (weval cond vars) of
                          Val (Bit True) -> weval x vars
                          Val (Bit False) -> weval y vars
                          Exception e -> Exception e
                          otherwise -> Exception $ "Non-boolean condition " ++ show cond
  For id x y ->         weval (case (weval x vars) of
                                 Val (List l) -> ListExpr (forloop id [Val item | item <- l] y)
                                 Val v -> ListExpr (forloop id [Val v] y)
                                 otherwise -> Exception (show x)) vars
  Range from to step -> case (weval from vars) of
                          Val v -> case v of
                                     NumInt i -> case (weval to vars) of
                                                   Val w -> case w of
                                                              NumInt j -> case (weval step vars) of
                                                                            Val u -> case u of
                                                                                       NumInt k -> Val $ List [NumInt x | x <- [i, i+k .. j]]
                                                                                       otherwise -> Exception "Non-integer argument in range"
                                                                            Exception e -> Exception e
                                                                            otherwise -> Exception "Non-integer argument in range"
                                                              otherwise -> Exception "Non-integer argument in range"
                                                   Exception e -> Exception e
                                                   otherwise -> Exception "Non-integer argument in range"
                                     otherwise -> Exception "Non-integer argument in range"
                          Exception e -> Exception e
                          otherwise -> Exception "Non-integer argument in range"
  FileObj f ->          case weval f vars of
                          Val (Str s) -> Val $ File s
                          otherwise -> Exception "Non-string filename"
  Output x ->           Output (weval x vars)
  FileWrite f x ->      case (weval f vars) of
                          Val (File f) -> case (weval x vars) of
                                            Val (Str s) -> FileWrite (Val (File f)) (Val (Str s))
                                            otherwise -> Exception $ "Write non-string " ++ show otherwise
                          otherwise -> Exception $ "Write to non-file " ++ show otherwise
  FileAppend f x ->     case (weval f vars) of
                          Val (File f) -> case (weval x vars) of
                                            Val (Str s) -> FileAppend (Val (File f)) (Val (Str s))
                                            otherwise -> Exception $ "Write non-string " ++ show otherwise
                          otherwise -> Exception $ "Write to non-file " ++ show otherwise
  otherwise ->          otherwise
 where var_binding :: Id -> [Binding] -> Call
       var_binding x [] = ([], Exception ("Undefined variable " ++ show x))
       var_binding x (h:t) = if (fst h) == x && 
                                length (fst (snd h)) == 0 && 
                                snd (snd h) /= Var (fst h)
                             then case snd (snd h) of
                                    Var v -> if v == x then var_binding x t
                                                       else var_binding v vars
                                    otherwise -> snd h
                             else var_binding x t
       func_binding :: Id -> [Expr] -> [Binding] -> Call
       func_binding x args [] = ([], Exception ("Function " ++ (show x) ++ " doesn't match any existing pattern."))
       func_binding x args (h:t) = if (show id) == (show x) &&
                                      length args == length params &&
                                      pattern_match params args
                                   then binding
                                   else func_binding x args t
                                   where (id, params, expr) =
                                           (fst h, fst binding, snd binding)
                                         binding = snd h
       pattern_match [] [] = True
       pattern_match (a:b) (c:d) = 
         case a of
           Name n -> pattern_match b d
           Split x y -> case weval c vars of
                          Val (List l) -> pattern_match b d
                          Val (Str l) -> pattern_match b d
                          otherwise -> False
           Pattern v -> if result == Val v 
                        then pattern_match b d
                        else case (result, v) of 
                               (Val (List []), Str "") -> pattern_match b d
                               (Val (Str ""), List []) -> pattern_match b d
                               otherwise -> False
                        where result = weval c vars
       is_function id [] = False
       is_function id (h:t) = if fst h == id && length (fst (snd h)) > 0 
                              then True 
                              else is_function id t
       pointed id = case snd $ var_binding id vars of
                      Var v -> pointed v
                      otherwise -> id
       -- funcall: list of (ID parameter, expression argument)
       funcall :: [(Id, Expr)] -> [(Id, Expr)]
       funcall [] = []
       funcall (h:t) = 
         case param of
            Name n -> h : funcall t
            Split x y -> case eager_eval arg vars of
                           Val (List l) -> if length l > 0 then (Name x, Val (head l)) :
                                                                (Name y, Val (List (tail l))) :
                                                                funcall t
                                                           else [(Name x, Exception "Can't split empty list")]
                           Val (Str l) -> if length l > 0 then (Name x, Val (Str [head l])) :
                                                               (Name y, Val (Str (tail l))) :
                                                               funcall t
                                                          else [(Name x, Exception "Can't split empty string")]
            Pattern _ -> funcall t
            where param = fst h
                  arg = snd h
       forloop :: Id -> [Expr] -> Expr -> [Expr]
       forloop id [] y = []
       forloop id (h:t) y = [Def id h y] ++ (forloop id t y)
                                
eval :: Expr -> [Binding] -> Expr
eval exp bindings = weval exp bindings

eager_eval x vars = weval x vars

iolist :: [IO Expr] -> IO [Expr]
iolist [] = do return []
iolist (h:t) = do item <- h
                  rest <- iolist t
                  return (item:rest)

subfile :: Expr -> [Binding] -> IO Expr
subfile exp vars =
  case exp of
    Val (Proc p) -> do list <- iolist [subfile e vars | e <- p]
                       return $ Val (Proc list)
    ToInt x -> do x' <- subfile x vars
                  return $ ToInt x'
    ToFloat x -> do x' <- subfile x vars
                    return $ ToFloat x'
    ToStr x -> do x' <- subfile x vars
                  return $ ToStr x'
    ListExpr l -> do list <- iolist [subfile e vars | e <- l]
                     return $ ListExpr list
    Subs x y -> do x' <- subfile x vars
                   y' <- subfile y vars
                   return $ Subs x' y'
    Add x y -> do x' <- subfile x vars
                  y' <- subfile y vars
                  return $ Add x' y'
    Sub x y -> do x' <- subfile x vars
                  y' <- subfile y vars
                  return $ Sub x' y'
    Prod x y -> do x' <- subfile x vars
                   y' <- subfile y vars
                   return $ Prod x' y'
    Div x y -> do x' <- subfile x vars
                  y' <- subfile y vars
                  return $ Div x' y'
    Exp x y -> do x' <- subfile x vars
                  y' <- subfile y vars
                  return $ Exp x' y'
    Eq x y -> do x' <- subfile x vars
                 y' <- subfile y vars
                 return $ Eq x' y'
    InEq x y -> do x' <- subfile x vars
                   y' <- subfile y vars
                   return $ InEq x' y'
    Gt x y -> do x' <- subfile x vars
                 y' <- subfile y vars
                 return $ Gt x' y'
    Lt x y -> do x' <- subfile x vars
                 y' <- subfile y vars
                 return $ Lt x' y'
    And x y -> do x' <- subfile x vars
                  y' <- subfile y vars
                  return $ And x' y'
    Or x y -> do x' <- subfile x vars
                 y' <- subfile y vars
                 return $ Or x' y'
    Not x -> do x' <- subfile x vars
                return $ Not x'
    EagerDef id x y -> do x' <- subfile x vars'
                          y' <- subfile y vars'
                          return $ EagerDef id x' y'
                          where vars' = ((id, ([], eager_eval x vars)) : vars)
    Def id x y -> do x' <- subfile x vars'
                     y' <- subfile y vars'
                     return $ Def id x' y'
                     where vars' = ((id, ([], x)) : vars)
    Defun id p x y -> do x' <- subfile x vars'
                         y' <- subfile y vars'
                         return $ Defun id p x' y'
                         where vars' = ((id, (p, x)) : 
                                        (id, ([], Val (HFunc id))) : 
                                        vars)
    If x y z -> do x' <- subfile x vars
                   y' <- subfile y vars
                   z' <- subfile z vars
                   return $ If x' y' z'
    For id x y -> do x' <- subfile x vars
                     y' <- subfile y vars
                     return $ For id x' y'
    Output x -> do x' <- subfile x vars
                   return $ Output x'
    FileRead f -> do case weval f vars of
                       Val (File f) -> do exists <- doesFileExist f
                                          case exists of 
                                            True -> do contents <- readFile f
                                                       return $ Val $ Str contents
                                            False -> return $ Exception "File does not exist"
                       otherwise -> do return $ Exception "Invalid file"
    otherwise -> do return otherwise
