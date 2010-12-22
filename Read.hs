module Read where

import System.IO
import Control.Monad
import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Expr
import Text.ParserCombinators.Parsec.Language
import qualified Text.ParserCombinators.Parsec.Token as Token
import Types

languageDef =
  emptyDef { Token.commentStart    = "{-",
             Token.commentEnd      = "-}",
             Token.commentLine     = "#",
             Token.identStart      = letter,
             Token.identLetter     = alphaNum <|> oneOf "_!'",
             Token.reservedNames   = ["if", "then", "else",
                                      "for", "in",
                                      "print", "skip",
                                      "true", "false",
                                      "and", "or", "not",
                                      "where", "case", "otherwise",
                                      "do",
                                      "int", "float", "str"
                                     ],
             Token.reservedOpNames = ["+", "-", "*", "/", "^", "=", ":=", "==",
                                      "<", ">", "and", "or", "not", ":", "->",
                                      "<=", ">=", "+="
                                     ]
           }
           
lexer = Token.makeTokenParser languageDef

identifier = Token.identifier       lexer -- parses an identifier
reserved   = Token.reserved         lexer -- parses a reserved name
reservedOp = Token.reservedOp       lexer -- parses an operator
parens     = Token.parens           lexer -- parses surrounding parentheses
squares    = Token.squares          lexer -- parses square brackets
integer    = Token.integer          lexer -- parses an integer
float      = Token.float            lexer -- parses a float
whiteSpace = Token.whiteSpace       lexer -- parses whitespace
stringLit  = Token.stringLiteral    lexer -- parses a string
charLit    = Token.charLiteral      lexer -- parses a character literal

parser :: Parser [PosExpr]
parser = many statement

statement :: Parser PosExpr
statement = whiteSpace >> do pos <- getPosition
                             expr <- try subscriptStmt <|> expression
                             return (Just pos, expr)

-- expression parsers

expression :: Parser Expr
expression = try operation <|> term
           
operation = buildExpressionParser operators (try term <|> parens term)

term :: Parser Expr
term = try syntax <|>
       parens expression
     
value = try listValue <|> try strValue <|> try floatValue <|> try intValue
valueStmt = try listStmt <|>
            try strStmt <|>
            try floatStmt <|>
            try intStmt
     
syntax :: Parser Expr
syntax = try (reserved "true" >> return (Val (Bit True))) <|>
         try (reserved "false" >> return (Val (Bit False))) <|>
         try (reserved "null" >> return (Val Null)) <|>
         try importStmt <|>
         try assignment <|>
         try ifStmt <|>
         try caseStmt <|>
         try skipStmt <|>
         try printStmt <|>
         try rangeStmt <|>
         try forStmt <|>
         try notStmt <|>
         try conversionStmt <|>
         try valueStmt <|>
         try funcallStmt <|>
         try splitExpr <|>
         try varcallStmt <|>
         try whereStmt <|>
         subscriptStmt

-- syntax parsers

moduleName :: Parser [String]
moduleName =
  do sepBy identifier (oneOf ".")

importStmt :: Parser Expr
importStmt =
  do reserved "import"
     mod <- moduleName
     return $ Import mod

defprocStmt = try defprocFun <|> try defprocVar

defprocVar :: Parser Expr
defprocVar =
  do var <- identifier
     reservedOp "="
     reserved "do"
     exprs <- many $ try (do expr <- whiteSpace >> expression
                             reservedOp ";"
                             return expr)
     return $ Defproc (Name var) [] exprs Placeholder

defprocFun :: Parser Expr
defprocFun =
  do var <- identifier
     params <- parens idList
     reservedOp "="
     reserved "do"
     exprs <- many $ try (do expr <- whiteSpace >> expression
                             reservedOp ";"
                             return expr)
     return $ Defproc (Name var) params exprs Placeholder

defunStmt :: Parser Expr
defunStmt =
  do var <- identifier
     params <- parens idList
     reservedOp "="
     expr <- expression
     return $ Defun (Name var) params expr Placeholder

eagerStmt :: Parser Expr
eagerStmt =
  do var <- identifier
     w <- whiteSpace
     reservedOp ":="
     w <- whiteSpace
     expr <- expression
     return $ EagerDef (Name var) expr Placeholder
     
accumulateStmt :: Parser Expr
accumulateStmt =
  do var <- identifier
     reservedOp "+="
     expr <- expression
     return $ EagerDef (Name var) (Add (Var (Name var)) (expr)) Placeholder
     
assignStmt :: Parser Expr
assignStmt =
  do var <- identifier
     w <- whiteSpace
     reservedOp "="
     w <- whiteSpace
     expr1 <- expression
     return $ Def (Name var) expr1 Placeholder
           
ifStmt :: Parser Expr
ifStmt =
  do reserved "if"
     cond  <- expression
     reserved "then"
     expr1 <- expression
     reserved "else"
     expr2 <- expression
     return $ If cond expr1 expr2
     
nestedCase [] = Undefined "No match found for case expression"
nestedCase (h:t) = case h of
                     If (Eq (b) (Placeholder)) c _ -> c
                     If a b _ -> If a b (nestedCase t)
     
caseStmt :: Parser Expr
caseStmt =
  do reserved "case"
     check <- whiteSpace >> expression
     reserved "of"
     cases <- sepBy (do cond <- whiteSpace >> (try (do reserved "otherwise"
                                                       return Placeholder
                                                       ) <|> 
                                               try expression)
                        reservedOp "->"
                        expr <- expression
                        return $ If (Eq (check) (cond)) (expr) (Placeholder)
                        ) (oneOf ",")
     return $ nestedCase cases
     
skipStmt :: Parser Expr
skipStmt = reserved "skip" >> return Skip

printStmt :: Parser Expr
printStmt =
  do reserved "print"
     expr <- expression
     return $ Output (expr) Placeholder
     
rangeStmt :: Parser Expr
rangeStmt =
  try (do reserved "range"
          reservedOp "("
          expr1 <- expression
          reservedOp ","
          expr2 <- expression
          reservedOp ","
          expr3 <- expression
          reservedOp ")"
          return $ Range expr1 expr2 expr3)
  <|> try (do reserved "range"
              reservedOp "("
              expr1 <- expression
              reservedOp ","
              expr2 <- expression
              reservedOp ")"
              return $ Range expr1 expr2 (Val (NumInt 1)))
  <|> try (do reserved "range"
              expr <- parens expression
              return $ Range (Val (NumInt 1)) expr (Val (NumInt 1)))

     
forStmt :: Parser Expr
forStmt =
  do reserved "for"
     iterator <- identifier
     reserved "in"
     list <- expression
     reservedOp ","
     expr <- expression
     return $ For (Name iterator) list expr
     
notStmt :: Parser Expr
notStmt =
  do reserved "not"
     expr <- expression
     return $ Not expr
     
conversionStmt :: Parser Expr
conversionStmt = try toIntStmt <|> try toFloatStmt <|> toStrStmt

toIntStmt =
  do reserved "int"
     expr <- parens expression
     return $ ToInt expr
toFloatStmt =
  do reserved "float"
     expr <- parens expression
     return $ ToFloat expr
toStrStmt =
  do reserved "str"
     expr <- parens expression
     return $ ToStr expr
     
subscriptStmt :: Parser Expr
subscriptStmt =
  do expr <- try valueStmt <|> 
             try varcallStmt <|>
             funcallStmt
     subs <- squares expression
     return $ Subs subs expr

-- value parsers

exprList :: Parser [Expr]
exprList = sepBy (whiteSpace >> expression) (oneOf ",")

identifierOrValue :: Parser Id
identifierOrValue = try idSplit <|> try idName <|> try idPattern
idSplit = 
  do id1 <- identifier
     reservedOp ":"
     id2 <- identifier
     return $ Split id1 id2
idName =
  do id <- identifier
     return $ Name id 
idPattern =
  do val <- value
     return $ Pattern val
       

idList :: Parser [Id]
idList = do id <- sepBy (whiteSpace >> identifierOrValue) (oneOf ",")
            return $ id

strValue :: Parser Value
strValue = 
  try (do chars <- stringLit
          return $ Str chars) <|>
  try (do char <- charLit
          return $ Str [char])
   
strStmt :: Parser Expr
strStmt =
  do str <- strValue
     return $ Val str
     
intValue :: Parser Value
intValue =
  do value <- integer
     whitespace <- whiteSpace
     return $ NumInt value
intStmt :: Parser Expr
intStmt =
  do value <- intValue
     return $ Val value
     
floatValue :: Parser Value
floatValue =
  do value <- float
     whitespace <- whiteSpace
     return $ NumFloat value
floatStmt :: Parser Expr
floatStmt =
  do value <- floatValue
     return $ Val value

listValue :: Parser Value
listValue =
  do exprs <- squares (sepBy value (oneOf ","))
     return $ List exprs
listStmt :: Parser Expr
listStmt =
  do exprs <- squares exprList
     return $ ListExpr exprs
     
     
funcallStmt :: Parser Expr
funcallStmt =
  do var <- identifier
     params <- parens exprList
     return $ Func (Name var) params
     
splitExpr =
  do id1 <- identifier
     reservedOp ":"
     id2 <- identifier
     return $ Add (Var (Name id1)) (Var (Name id2))
     
varcallStmt :: Parser Expr
varcallStmt =
  do var <- identifier
     return $ Var (Name var)

assignment :: Parser Expr
assignment = try defprocStmt <|> 
             try defunStmt <|> 
             try accumulateStmt <|> 
             try eagerStmt <|> 
             assignStmt
     
nestwhere [] wexpr = wexpr
nestwhere (h:t) wexpr = case h of
                          Defun a b c Placeholder -> Defun a b c (nestwhere t wexpr)
                          EagerDef a b Placeholder -> EagerDef a b (nestwhere t wexpr)
                          Def a b Placeholder -> Def a b (nestwhere t wexpr)
                          otherwise -> nestwhere t wexpr

whereStmt :: Parser Expr
whereStmt =
  do wexpr <- parens expression
     reserved "where"
     assignment <- sepBy (whiteSpace >> assignment) (oneOf ",")
     return $ nestwhere assignment wexpr

-- operator table

ltEq x y = Not (Gt x y)
gtEq x y = Not (Lt x y)

operators :: [[ Operator Char st Expr ]]
operators = [[Infix  (reservedOp "^"   >> return (Exp             )) AssocLeft],
             [Infix  (reservedOp "*"   >> return (Prod            )) AssocLeft,
              Infix  (reservedOp "/"   >> return (Div             )) AssocLeft],
             [Infix  (reservedOp "+"   >> return (Add             )) AssocLeft,
              Infix  (reservedOp "-"   >> return (Sub             )) AssocLeft],
             [Infix  (reservedOp "=="  >> return (Eq              )) AssocLeft,
              Infix  (reservedOp "<="  >> return (ltEq            )) AssocLeft,
              Infix  (reservedOp ">="  >> return (gtEq            )) AssocLeft,
              Infix  (reservedOp "not" >> return (InEq            )) AssocLeft,
              Infix  (reservedOp ">"   >> return (Gt              )) AssocLeft,
              Infix  (reservedOp "<"   >> return (Lt              )) AssocLeft],
             [Infix  (reservedOp "and" >> return (And             )) AssocLeft,
              Infix  (reservedOp "or"  >> return (Or              )) AssocLeft,
              Infix  (reservedOp "&"   >> return (And             )) AssocLeft,
              Infix  (reservedOp "|"   >> return (Or              )) AssocLeft ]
             ]

read name s = case (parse parser name s) of
                Right r -> r
                otherwise -> [(Nothing, Undefined "Parse error")]
