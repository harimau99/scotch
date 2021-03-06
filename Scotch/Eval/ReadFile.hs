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

module Scotch.Eval.ReadFile (importFile, execute, wexecute) where

import Data.List
import Data.ByteString.Lazy (readFile)
import System.Directory
import Control.Concurrent
import Text.Parsec.Pos
import Scotch.Parse.Parse as Parse
import Scotch.Types.Types
import Scotch.Types.Exceptions
import Scotch.Types.Bindings
import Scotch.Types.Hash
import Scotch.Types.Interpreter
import Scotch.Eval.Eval
import Scotch.Config
import Scotch.Lib.StdLib


-- interpret a list of code lines using a list of scoped bindings
wexecute :: InterpreterSettings -> [PosExpr] -> VarDict -> IO VarDict
wexecute _ [] bindings = do return bindings
wexecute settings (h:t) bindings = 
  do let parsed = snd h
     -- evaluate the parsed code
     result <- do ieval settings parsed bindings []
     -- get new bindings if any definitions/imports were made
     newBindings <- case result of
                      Def id x Skip -> do return [(localVar id, x)]
                      EagerDef id x Skip -> do evaluated <- ieval settings x bindings []
                                               case evaluated of
                                                 Exception e -> do putStrLn $ show $ Exception e
                                                                   return []
                                                 otherwise -> return [(localVar id, evaluated)]
                                               return [(localVar id, evaluated)]
                      Import s t -> do i <- importFile settings True s t
                                       b <- case i of 
                                              (False, _) -> do putStrLn ("Failed to import module " ++ show s)
                                                               return []
                                              (True, i) -> do return $ reverse [e | j <- i, e <- j]
                                       return b
                      Val (Proc p) -> do e <- wexecute settings [(position, e) | e <- p] bindings
                                         return [i | j <- e, i <- j]
                      Val v -> do return $ [(Var "ans", result)]
                      otherwise -> do return []
     -- output, if necessary
     case result of
       Exception e -> do putStrLn ("\nException in " ++ (showPosition) ++ "\n" ++ e ++ "\n")
                         return []
       Call (Var "print") [x] -> do case x of
                                      Val (Str s) -> putStrLn s
                                      otherwise -> print x
                                    nextline newBindings
       Call (Var "write") [Val (Str f), Val (Str x)] -> do writeFile f x
                                                           nextline newBindings
       Call (Var "append") [Val (Str f), Val (Str x)] -> do appendFile f x
                                                            nextline newBindings
       Val (Thread th) -> do forkIO (do wexecute settings [(Nothing, th)] bindings
                                        return ())
                             nextline newBindings
       Val (Proc p) -> nextline newBindings
       Skip -> nextline newBindings
       Import a b -> nextline newBindings
       Def a b c -> nextline newBindings
       EagerDef a b c -> nextline newBindings
       otherwise -> if (interpret settings)
                    then do putStrLn $ show otherwise
                            nextline newBindings
                    else nextline newBindings
     where name = case position of
                    Just p -> fst p
                    Nothing -> ""
           line = case position of
                    Just p -> fst (snd p)
                    Nothing -> 1
           column = case position of
                     Just p -> snd (snd p)
                     Nothing -> 1
           showPosition = name ++ ": Line " ++ show line ++ ", column " ++ show column
           position = fst h
           nextline newBindings = wexecute settings t (makeVarDict (reverse newBindings) bindings)
           localVar id = case id of
                           Var v -> Var ("local." ++ v)
                           Call (Var v) args -> Call (Var ("local." ++ v)) args
                           otherwise -> id


-- returns a qualified file name from a list of identifiers provided by an import statement        
importName [] = ""
importName (h:t) = "/" ++ h ++ (importName t)
searchPathMatch :: [String] -> IO String
searchPathMatch [] = do return ""
searchPathMatch (h:t) = do exists <- doesFileExist (h ++ ".sco")
                           case exists of
                             True -> return h
                             False -> searchPathMatch t
                             
-- returns (was the import successful?, VarDict of imported bindings)
importFile :: InterpreterSettings -> Bool -> [String] -> [String] -> IO (Bool, VarDict)
--importFile settings True ["std", "lib"] ["std", "lib"] = do return (True, stdlib)
importFile settings _ s t = 
  do currDir <- getCurrentDirectory
     libDir <- libraryPath
     let moduleName = importName s
     let searchPath = [currDir ++ moduleName ++ "/main",
                       currDir ++ moduleName,
                       libDir ++ moduleName ++ "/main",
                       libDir ++ moduleName]
     path <- searchPathMatch searchPath
     let builtin = stdLib settings
     val <- case path of 
              "" -> do return []
              otherwise -> do e <- execute (InterpreterSettings 
                                            {
                                             verbose = verbose settings,
                                             strict = strict settings,
                                             interpret = False,
                                             exePath = exePath settings,
                                             exeMod = exeMod settings,
                                             stdLib = stdLib settings
                                            })
                                   path builtin
                              return [i | j <- e, i <- j]
     let success = case path of
                     "" -> False
                     otherwise -> True
     let newval = [(case fst binding of
                      Var v -> Var (qualifier ++ stripLocal v)
                      Call (Var v) a -> Call (Var (qualifier ++ stripLocal v)) a
                      otherwise -> otherwise,--stripLocal (stripName (fst binding))),
                    snd binding) 
                   | binding <- val,
                     case fst binding of
                       Var v -> isPrefixOf "local." v
                       Call (Var v) _ -> isPrefixOf "local." v
                       otherwise -> True
                     --isPrefixOf "local." (stripName (fst binding))
                     ]
                   where qualifier = (foldl (++) [] [i ++ "." | i <- t])
                         stripLocal s = if isPrefixOf "local." s then [s !! n | n <- [length "local." .. (length s) - 1]] else s
     return (success, makeVarDict newval emptyHash)

-- interpret the contents of a file, returning a dictionary of the new bindings
execute :: InterpreterSettings -> String -> VarDict -> IO VarDict
execute settings file bindings = 
  do optimized <- doesFileExist (file ++ ".osc")
     parsed <- case optimized of
                 True -> do t1 <- getModificationTime (file ++ ".sco")
                            t2 <- getModificationTime (file ++ ".osc")
                            if t1 > t2 || (exeMod settings) > t2
                             then do input <- Prelude.readFile (file ++ ".sco")
                                     let exprs = (Parse.read (file ++ ".sco") input)
                                     serialize (file ++ ".osc") exprs
                             else do return ()
                            bytes <- Data.ByteString.Lazy.readFile (file ++ ".osc")
                            return $ Parse.readBinary (bytes)
                 False -> do input <- Prelude.readFile (file ++ ".sco")
                             let exprs = (Parse.read (file ++ ".sco") input)
                             serialize (file ++ ".osc") exprs
                             return exprs
     wexecute settings parsed bindings
