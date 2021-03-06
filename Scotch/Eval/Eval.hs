{-  This file is part of Scotch.

    Scotch is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Scotch is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOnoR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Scotch.  If not, see <http://www.gnu.org/licenses/>.
-}

module Scotch.Eval.Eval (ieval, subfile) where

import Data.List
import Numeric
import System.Directory
import Scotch.Types.Types
import Scotch.Types.Exceptions
import Scotch.Types.Bindings
import Scotch.Types.Hash
import Scotch.Types.Interpreter
import Scotch.Eval.Calc
import Scotch.Eval.Substitute
import Scotch.Parse.Parse as Parse


{- 
eval: evaluates an expression.
      This function evaluates expressions step by step and should not be assumed to result 
      in full evaluation; rather, eval should be run until the result is the same as the initial input.
-}
eval :: Expr -> VarDict -> InterpreterSettings -> Bool -> Expr
eval exp [] settings rw = eval exp emptyHash settings rw
eval oexp vars settings rw = 
  if exp /= oexp 
  then exp
  else case exp of
  Var id ->             if length (qualVarHash id vars) > 0
                        then Val $ Hash $ makeHash strHash (qualVarHash id vars) emptyHash
                        else if length (qualVarHash ("local." ++ id) vars) > 0
                             then Val $ Hash $ makeHash strHash (qualVarHash ("local." ++ id) vars) emptyHash
                             else Var id
  Call x [] -> x
  Call (Call id args) args' -> eval' $ Call id (args ++ args')
  Call (Var "eval") 
       [x] ->           case eval' x of
                          Val (Str s) -> case length evaled of
                                           0 -> Skip
                                           1 -> evaled !! 0
                                           otherwise -> Val $ Proc $ evaled
                                         where evaled = [snd i | i <- Parse.read "" s]
                          otherwise -> Call (Var "eval") [otherwise]
  Call (Var "int") 
       [x] ->           case eval' x of
                          Val (NumInt i) -> Val $ NumInt i
                          Val (NumFloat f) -> Val $ NumInt (truncate f)
                          Val (Str s) -> case (Parse.read "" s) !! 0 of
                                           (Just a, Val (NumInt i)) -> Val (NumInt i)
                                           otherwise -> exCantConvert s "integer"
                          Exception e -> Exception e
                          otherwise -> Call (Var "int") [otherwise]
  Call (Var "float") 
       [x] ->           case eval' x of
                          Val (NumInt i) -> Val $ NumFloat $ fromIntegral i
                          Val (NumFloat f) -> Val $ NumFloat f
                          Val (Str s) -> case (Parse.read "" s) !! 0 of
                                           (Just a, Val (NumFloat f)) -> Val (NumFloat f)
                                           (Just a, Val (NumInt i)) -> Val (NumFloat (fromIntegral i))
                                           otherwise -> exCantConvert s "float"
                          Exception e -> Exception e
                          otherwise -> Call (Var "float") [otherwise]
  Call (Var "str") 
       [x] ->           case eval' x of
                          Val (Str s) -> Val $ Str s
                          Val (NumFloat f) -> Val $ Str $ showFFloat Nothing f ""
                          Val (Undefined u) -> Exception u
                          Val v -> Val $ Str (show v)
                          Exception e -> Exception e
                          otherwise -> if otherwise == x
                                       then Val $ Str $ show x
                                       else Call (Var "str") [otherwise]
  Call (Var "list") 
       [x] ->           case eval' x of
                          List l -> List l
                          Val (Str s) -> List [Val (Str [c]) | c <- s]
                          Val (Hash h) -> List [List [Val (Str (fst l)), snd l] | e <- h, l <- e]
                          Exception e -> Exception e
                          Val v -> List [Val v]
                          otherwise -> Call (Var "list") [otherwise]
  Call (Var "bool") 
       [x] ->           case eval' x of
                          Val Null -> Val (Bit False)
                          Val (Bit b) -> Val (Bit b)
                          Val (NumInt n) -> Val (Bit (n /= 0))
                          Val (NumFloat n) -> Val (Bit (n /= 0))
                          Val (Str s) -> Val (Bit (s /= ""))
                          List l -> Val (Bit (l /= []))
                          otherwise -> Call (Var "bool") [otherwise]
  Call (Var id) args -> if fullEval (Var id) eval' == Var id
                        then Call (Var id) [fullEval arg eval' | arg <- args]
                        else Call (fullEval (Var id) eval') args
  Call (Val (Lambda ids expr)) args ->
                        if length ids == length args
                        then substitute expr (zip [Var id | id <- ids] args)
                        else exp
  Call (Val (NumInt i)) args -> Prod (Val (NumInt i)) (totalProd args)
  Call (Val (NumFloat i)) args -> Prod (Val (NumFloat i)) (totalProd args)
  Call (Val (Str s)) args -> Val $ Str $ s ++ foldl (++) "" [case fullEval i eval' of
                                                               Val (Str a) -> a
                                                               otherwise -> show otherwise 
                                                             | i <- args]
  Call x args ->        Call (fullEval x eval') args
  Import s t ->         Import s t
  Take n x ->           case n of
                          Val (NumInt i) -> case x of
                                              List l -> List (take i' l)
                                              Val (Str s) -> Val $ Str $ take i' s
                                              Exception e -> Exception e
                                              Add (List l) (y) -> if length t == i'
                                                                  then List t
                                                                  else Take n (eval' x)
                                                                  where t = take i' l
                                              otherwise -> Take n (eval' x)
                                            where i' = fromIntegral i
                          Exception e -> Exception e
                          otherwise -> Take (eval' otherwise) x
  List l ->             case (validList l) of
                          Val _ -> case List [eval' i | i <- l] of
                                     List l -> if all ((==) True)
                                                      [case i of
                                                         Val (Str s) -> length s == 1
                                                         otherwise -> False 
                                                       | i <- l]
                                               then Val $ Str (foldl (++) [case i of
                                                                             Val (Str s) -> s !! 0
                                                                           | i <- l] [])
                                               else List l
                                     otherwise -> otherwise
                          Exception e -> Exception e
  HashExpr l ->         Val $ Hash $ makeHash strHash
                                     [(case eval' (fst i) of
                                         Val (Str s) -> s
                                         otherwise -> show otherwise,
                                       snd i)
                                      | i <- l] emptyHash
  Val x ->              case x of
                          Undefined s -> Exception s
                          otherwise -> Val x
  Subs n x ->           case fullEval x' eval' of
                          List l ->       case n' of
                                            Val (NumInt n) -> case (if n >= 0
                                                                    then getElemAtN l (fromIntegral n)
                                                                    else getElemAtN l ((length l) + (fromIntegral n))) of
                                                                Just x -> x
                                                                Nothing -> exNotInList n
                                            List l' ->        List [Subs i (List l) | i <- l']
                                            otherwise ->      Subs n' x'
                          Val (Str s) ->  case n' of
                                            Val (NumInt n) -> if n >= 0
                                                              then Val (Str ([s !! (fromIntegral n)]))
                                                              else Val (Str ([s !! ((length s) + (fromIntegral n))]))
                                            List l' ->        List [Subs i (Val (Str s)) | i <- l']
                                            otherwise ->      Subs n' x'
                          Val (Hash l) -> case n' of
                                            Exception e -> Exception e
                                            List l' ->        List [Subs i (Val (Hash l)) | i <- l']
                                            otherwise -> case fullEval (Call (Var "str") [otherwise]) eval' of
                                                           Val (Str s) ->    case hashMember strHash s l of
                                                                               Just x -> x
                                                                               Nothing -> exNotInHash s
                                                           Exception e ->    Exception e
                                                           otherwise ->      Subs n' x'
                          Call (Var f) args ->  case n' of
                                                  Val (NumInt n) -> if n >= 0
                                                                    then eval' $ Subs (Val (NumInt n)) (eval' (Take (Val (NumInt ((fromIntegral n) + 1))) (Call (Var f) args)))
                                                                    else Subs (Val (NumInt n)) (eval' x)
                                                  List l' ->        List [Subs i f' | i <- l']
                                                                    where f' = (Call (Var f) args)
                                                  otherwise ->      Subs n' x'
                          otherwise ->    Subs n x'
                        where n' = eval' n
                              x' = eval' x
  Concat x y ->         eval' (Add x y)
  Add x y ->            case x of
                          Exception e ->    Exception e
                          List l ->         case y of
                                              Exception e -> Exception e
                                              List l' -> List $ l ++ l'
                                              Val v -> vadd (strict settings) x y
                                              Add a (Call id args) -> Add (eval' (Add x a)) (Call id args)
                                              otherwise -> nextOp
                          Val (Proc p) ->   Val $ Proc $ p ++ [y]
                          Val v ->          case y of
                                              Exception e -> Exception e
                                              List l -> vadd (strict settings) x y
                                              Val v -> vadd (strict settings) x y
                                              otherwise -> nextOp
                          otherwise ->      nextOp
                        where nextOp = if vadd (strict settings) x y == Add x y
                                       then Add (eval' x) (eval' y)
                                       else operation x y vadd Add
  Sub x y ->            operation x y vsub Sub
  Prod x y ->           {-if nextOp == Prod x y
                        then if eval' (Prod y x) == Prod y x
                             then nextOp
                             else case x of
                                    Prod a b -> if eval' x == x
                                                then Prod a (Prod b y)
                                                else nextOp
                                    otherwise -> case y of
                                                   Prod a b -> if eval' y == y
                                                               then Prod (Prod x a) b
                                                               else nextOp
                                                   otherwise -> nextOp
                        else -}nextOp
                        where nextOp = operation x y vprod Prod
  Div x y ->            operation x y vdiv Div
  Mod x y ->            operation x y vmod Mod
  Exp x y ->            operation x y vexp Exp
  Eq x y ->             case operation x' y' veq Eq of
                          Eq (List a) (List b) -> if length a' == length b'
                                                  then Val $ Bit $ 
                                                        allTrue [fullEval (Eq (a' !! n) 
                                                                              (b' !! n))
                                                                          eval'
                                                                 | n <- [0 .. (length a - 1)]]
                                                  else Val (Bit False)
                                                  where allTrue [] = True
                                                        allTrue (h:t) = case h of 
                                                                          Val (Bit True) -> allTrue t
                                                                          otherwise -> False
                                                        list' l = case fullEval (List l) eval' of
                                                                    List l -> l
                                                                    otherwise -> []
                                                        a' = list' a
                                                        b' = list' b
                          otherwise -> if x' == y' then Val (Bit True) 
                                       else otherwise
                        where x' = fullEval x eval'
                              y' = fullEval y eval'
  InEq x y ->           eval' (Prod (operation x y veq Eq) (Val (NumInt (-1))))
  Gt x y ->             operation x y vgt Gt
  Lt x y ->             operation x y vlt Lt
  And x y ->            case eval' x of
                          Val (Bit True) -> case eval' y of
                                              Val (Bit True) -> Val (Bit True)
                                              Val (Bit False) -> Val (Bit False)
                                              otherwise -> And (eval' x) (eval' y)
                          Val (Bit False) -> Val (Bit False)
                          otherwise -> And (eval' x) (eval' y)
                        where err = exTypeMismatch (eval' x) (eval' y) "and"
  Or x y ->             case eval' x of
                          Val (Bit True) -> Val (Bit True)                                            
                          Val (Bit False) -> case eval' y of
                                               Val (Bit b) -> Val (Bit b)
                                               otherwise -> Or (eval' x) (eval' y)
                          otherwise -> Or (eval' x) (eval' y)
                        where err = exTypeMismatch (eval' x) (eval' y) "or"
  Not x ->              case eval' x of
                          Exception s -> Exception s
                          Val (Bit b) -> Val $ Bit $ not b
                          otherwise -> Not otherwise
  Def f x Skip ->       case f of
                          List l -> Val $ Proc $ 
                                    [Def (l !! n) (Subs (Val $ NumInt $ fromIntegral n) x) Skip 
                                     | n <- [0 .. length(l) - 1]]
                          Subs a b -> case fullEval b eval' of
                                        Val (Hash h) -> Def b (Val (Hash (makeHash strHash [((case fullEval a eval' of
                                                                                                Val (Str s) -> s
                                                                                                otherwise -> show a), x)
                                                                                            ] h))) Skip
                                        HashExpr h -> Def b (HashExpr (h ++ [(a, x)])) Skip
                                        Var id -> Def b (Val (Hash (makeHash strHash [(show a, x)] emptyHash))) Skip
                                        otherwise -> Def f x Skip
                          otherwise -> Def f x Skip
  Def f x y ->          evalWithNewDefs y [(f, x)]
  EagerDef f x' Skip -> case f of
                          List l -> Val $ Proc $ 
                                    [EagerDef (l !! n) (Subs (Val $ NumInt $ fromIntegral n) x) Skip 
                                     | n <- [0 .. length(l) - 1]]
                          Subs a b -> case fullEval b eval' of
                                        Val (Hash h) -> Def b (Val (Hash (makeHash strHash [((case fullEval a eval' of
                                                                                                Val (Str s) -> s
                                                                                                otherwise -> show a), x)
                                                                                            ] h))) Skip
                                        HashExpr h -> EagerDef b (HashExpr (h ++ [(a, x)])) Skip
                                        Var id -> EagerDef b (Val (Hash (makeHash strHash [(show a, x)] emptyHash))) Skip
                                        otherwise -> EagerDef f x Skip
                          otherwise -> EagerDef f x Skip
                        where x = fullEval x' eval'
  EagerDef f x y ->     case fullEval x eval' of
                          Val v -> next
                          List l -> next
                          otherwise -> next--EagerDef f otherwise y
                        where next = evalWithNewDefs y [(f, fullEval x eval')]
  If cond x y ->        case fullEval cond eval' of
                          Val (Bit True) -> x
                          Val (Bit False) -> y
                          Exception e -> Exception e
                          otherwise -> If otherwise x y
  Case check cases ->   caseExpr check (reverse cases)
  For id x y conds ->   case fullEval x eval' of
                          List l ->         List [substitute y [(Var id, item)] | item <- l,
                                                  allTrue [substitute cond [(Var id, item)] | cond <- conds]
                                                  ]
                          Exception e ->    Exception e
                          otherwise ->      For id otherwise y conds
  Range from to step -> case from of
                          Val (NumInt i) -> case to of
                                              Val (NumInt j) -> case step of
                                                                  Val (NumInt k) -> List [Val (NumInt x) | x <- [i, i+k .. j]]
                                                                  Exception e -> Exception e
                                                                  otherwise -> Range from to (eval' step)
                                              Skip -> case (eval' step) of
                                                        Val (NumInt k) -> List [Val (NumInt x) | x <- [i, i+k ..]]
                                                        Exception e -> Exception e
                                                        otherwise -> Range from Skip otherwise
                                              Exception e -> Exception e
                                              otherwise -> Range from (eval' to) step
                          Exception e -> Exception e
                          otherwise -> Range (eval' from) to step
  UseRule r x ->        case r of
                          Rule r -> eval' (rule x r)
                          List l -> if all ((/=) [Skip]) l'
                                    then UseRule (Rule (allRules l' [])) x
                                    else exInvalidRule r
                                    where l' = [case fullEval i eval' of
                                                  Rule r' -> r'
                                                  otherwise -> [Skip]
                                                | i <- l]
                          Val (Hash h) -> UseRule (Rule r') x
                                          where r' = [Def (Var (fst i)) (snd i) Skip
                                                      | j <- h, i <- j]
                          Val v -> exInvalidRule r
                          otherwise -> UseRule (eval' r) x
                        where rule x (h:t) = case h of
                                               Def a b c -> Def a b (rule x t)
                                               EagerDef a b c -> EagerDef a b (rule x t)
                                               otherwise -> rule x t
                              rule x [] = x
                              allRules (h:t) a = allRules t (a ++ h)
                              allRules [] a = a
  otherwise ->          otherwise
 where operation x y f g = if calc x' y' f (strict settings) == g x' y'
                           then g x' y'
                           else calc x' y' f (strict settings)
                           where x' = fullEval x eval'
                                 y' = fullEval y eval'
                             
       allTrue [] = True
       allTrue (h:t) = case eval' h of
                         Val (Bit True) -> allTrue t
                         Exception e -> False
                         Val v -> False
                         otherwise -> if otherwise == h then False else allTrue (otherwise : t)
       caseExpr check [] = Call (Var "case") [fullEval check eval']
       caseExpr check (h:t) = Def (Call (Var "case") [fst h]) (snd h) (caseExpr check t)
       evalArgs x = case x of
                      Call a b -> Call (evalArgs a) ([fullEval i eval' | i <- b])
                      otherwise -> otherwise
       exp = if rw
             then rewrite (evalArgs oexp) (vars !! exprHash oexp) (vars !! exprHash oexp) eval'
             else oexp
       eval' expr = eval expr vars settings rw
       evalWithNewDefs expr defs = eval expr (makeVarDict defs vars) settings rw
       
getElemAtN [] n = Nothing
getElemAtN (h:t) 0 = Just h
getElemAtN (h:t) n = getElemAtN t (n-1)


totalProd [] = Val (NumInt 1)       
totalProd (h:t) = if t == []
                  then h
                  else Prod h (totalProd t)
                                    

iolist :: [IO Expr] -> IO [Expr]
iolist [] = do return []
iolist (h:t) = do item <- h
                  rest <- iolist t
                  return (item:rest)

-- ieval: evaluates an expression completely, replacing I/O operations as necessary
ieval :: InterpreterSettings -> Expr -> VarDict -> [Expr] -> IO Expr
ieval settings expr vars last =
  do subbed <- subfile expr
     let result = eval subbed vars settings True
     if isInfixOf [result] last
      then return (last !! 0)
      else do if (verbose settings) && length last > 0 
                then putStrLn (show (last !! 0))
                else return ()
              result' <- case expr of
                           Def _ _ Skip -> do return (result, vars)
                           EagerDef _ _ Skip -> do return (result, vars)
                           Def id x y -> do return $ (y, makeVarDict [(id, x)] vars)
                           EagerDef id x y -> do x' <- ieval settings x vars (expr : last')
                                                 return $ (y, makeVarDict [(id, x')] vars)
                           otherwise -> do return (result, vars)
              ieval settings (fst result') (snd result') (expr : last')
              where last' = take 2 last

oneArg f a = do a' <- subfile a
                return $ f a'
twoArgs f a b = do a' <- subfile a
                   b' <- subfile b
                   return $ f a' b'
threeArgs f a b c = do a' <- subfile a
                       b' <- subfile b
                       c' <- subfile c
                       return $ f a' b' c'

-- subfile: substitutes values for delayed I/O operations
subfile :: Expr -> IO Expr
subfile exp =
  case exp of
    Var "input" -> do line <- getLine
                      return $ Val (Str line)
    Call (Var "read") [f] -> do sub <- subfile f
                                case f of
                                  Val (Str f) -> do exists <- doesFileExist f
                                                    case exists of 
                                                      True -> do contents <- readFile f
                                                                 return $ Val $ Str contents
                                                      False -> return $ exFileDNE
                                  otherwise -> return $ exp
    Call f args -> do args' <- iolist [subfile arg | arg <- args]
                      return $ Call f args'
    Take a b -> twoArgs Take a b
    List l ->      do list <- iolist [subfile e | e <- l]
                      return $ List list
    HashExpr l -> do list1 <- iolist [subfile (fst e) | e <- l]
                     list2 <- iolist [subfile (snd e) | e <- l]
                     return $ HashExpr (zip list1 list2)
    Subs a b -> twoArgs Subs a b
    Add a b -> twoArgs Add a b
    Sub a b -> twoArgs Sub a b
    Prod a b -> twoArgs Prod a b
    Div a b -> twoArgs Div a b
    Mod a b -> twoArgs Mod a b
    Exp a b -> twoArgs Exp a b
    Eq a b -> twoArgs Eq a b
    InEq a b -> twoArgs InEq a b
    Gt a b -> twoArgs Gt a b
    Lt a b -> twoArgs Lt a b
    And a b -> twoArgs And a b
    Or a b -> twoArgs Or a b
    Not a -> oneArg Not a
    EagerDef id a b -> twoArgs (EagerDef id) a b
    Def id a b -> oneArg (Def id a) b
    If a b c -> threeArgs If a b c
    For id x y z -> do x' <- subfile x
                       y' <- subfile y
                       z' <- iolist [subfile i | i <- z]
                       return $ For id x' y' z'
    otherwise -> do return otherwise
