module Main where

import System
import System.Environment.Executable
import System.Directory
import Data.List
import Types
import Read
import Eval
import System.Console.Readline
import ReadFile


version = "0.1"
-- check for -v or -i flags
vFlag [] = False
vFlag (h:t) = if h == "-v" then True else vFlag t
iFlag [] = False
iFlag (h:t) = if h == "-i" then True else iFlag t

left [] 0 = []
left (h:t) 0 = []
left (h:t) n = h : (left t (n - 1))

main = do args <- getArgs
          let verbose = vFlag args
          let interpret = iFlag args
          full_path <- splitExecutablePath
          let path = (fst full_path) ++ "scotch.std/lib.sco"
          exists <- doesFileExist path
          -- import std.lib
          bindings <- case exists of 
                        True -> execute verbose path []
                        False -> do return []
          let unscoped = unscope bindings
          if verbose then putStrLn "-v Verbose mode on" else return ()
          if (length args) > 0 && isSuffixOf ".sco" (args !! 0) 
            -- if a .sco filename is given as the first argument, interpret that file
            then do newbindings <- execute verbose (args !! 0) unscoped
                    -- if the -i flag is set, start the interpreter
                    if interpret then loop verbose (unscope newbindings)
                                 else return ()
            -- otherwise, start the interpreter
            else do putStrLn ("Scotch interpreter, version " ++ version)                    
                    loop verbose unscoped

-- the interpreter's main REPL loop
loop :: Bool -> [Binding] -> IO ()
loop verbose bindings = 
  do line <- readline ">> "
     case line of
        Nothing -> return ()
        Just "quit" -> return ()
        Just input -> do -- parse input
                         let parsed = Read.read input
                         imp <- case parsed of
                                        Import s -> importFile verbose 0 s
                                        otherwise -> do return []
                         -- evaluate parsed input
                         let result = eval parsed bindings
                         if verbose then putStrLn (show parsed)
                                    else return ()
                         -- determine whether any definitions were made
                         let newBindings = case parsed of
                                             Def id x Placeholder -> [(id, ([], x))]
                                             EagerDef id x Placeholder -> [(id, ([], (case eval x bindings of
                                                                                        Result r -> Val r
                                                                                        Exception s -> Undefined s
                                                                                      )))]
                                             Defun id params x Placeholder -> [(id, (params, x))]
                                             otherwise -> []
                         -- output, if necessary
                         case parsed of
                            Output x y -> putStrLn (case (eval x bindings) of
                                                         Result (Str s) -> s
                                                         e -> show e)
                            otherwise -> putStrLn (show result)
                         -- continue loop
                         loop verbose (newBindings ++ (unscope imp) ++ bindings)
