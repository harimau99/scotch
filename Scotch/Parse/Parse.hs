{-  This file is part of Scotch.

    Scotch is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Scotch is distributed in ther hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Scotch.  If not, see <http://www.gnu.org/licenses/>.
-}

module Scotch.Parse.Parse where

import Data.ByteString.Lazy
import Data.Binary
import Data.List
import Data.List.Utils
import Data.List.Split
import Codec.Compression.GZip
import Text.Parsec.ByteString
import Text.Parsec.Expr
import Text.Parsec.Char
import Text.Parsec.Combinator
import Text.Parsec.Prim
import Text.Parsec.Pos
import Scotch.Types.Types
import Scotch.Types.Hash
import Scotch.Parse.Expressions
import Scotch.Parse.ParseBase

parser = try (do whiteSpace
                 pos <- getPosition
                 expr <- statement
                 return (Just (sourceName pos, (sourceLine pos, sourceColumn pos)), expr))
         <|> 
         try (do whiteSpace
                 pos <- getPosition
                 chars <- many1 (noneOf "")
                 return (Just (sourceName pos, (sourceLine pos, sourceColumn pos)), 
                         Exception $ "Parse error: Unable to parse text starting with \"" ++ summary (Prelude.take 40 chars) ++ "\""))
         <|> do return (Nothing, Skip)

summary [] = []
summary (h:t) = if h == '\n' then "" else h : summary t

splitLines :: [String] -> [String] -> [String]
splitLines [] a = a
splitLines (h:[]) a = a ++ [h]
splitLines (h:t) a = if Prelude.length (Prelude.head t) > 0 && 
                        Prelude.head (Prelude.head t) == ' '
                     then splitLines ((h ++ "\n" ++ Prelude.head t) : Prelude.tail t) a
                     else splitLines t (a ++ [h])
leadons = [('(', ')'), ('{', '}'), ('\"', '\"'), ('\'', '\'')]
connectLines _ [] a = a
connectLines _ (h:[]) a = a ++ [h]
connectLines [] (h:t) a = connectLines leadons t (a ++ [h])
connectLines (l:m) (h:t) a = if countElem (fst l) h > countElem (snd l) h
                             then connectLines leadons ([h ++ "\n" ++ Prelude.head t] ++ 
                                                        Prelude.tail t) a
                             else connectLines m (h:t) a

                           
read name text = [case (parse parser name l) of
                    Right r -> r
                    otherwise -> (Nothing, Exception $ "Parse error" ++ (show otherwise))
                  | l <- realLines text]
realLines text = connectLines leadons (splitLines (splitOn "\n" (replace "\\\n" "" text)) []) []
                  
                
serialize file exprs = Data.ByteString.Lazy.writeFile file (compress (encode (exprs :: [PosExpr])))
readBinary bytes = decode (decompress bytes) :: [PosExpr]
