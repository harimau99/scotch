module Types where

-- a bindable identifier
data Id = Name String | Pattern Value deriving Eq
instance Show(Id) where
    show (Name s) = s
    show (Pattern v) = show v
-- a list of identifiers (empty list for variables) and an expression containing them
type Call = ([Id], Expr)
-- binds an ID to a Call
type Binding = (Id, Call)

-- a value with its corresponding type
data Value = NumInt Integer
           | NumFloat Double
           | Str String
           | Bit Bool
           | List [Expr]
           | Null
           deriving Eq
instance Show (Value) where
    show (Str s) = s
    show (NumInt n) = show n
    show (NumFloat n) = show n
    show (Bit True) = "true"
    show (Bit False) = "false"
    show (List l) = show l
    show (Null) = "null"

-- a calculation, which may cause an exception if one of its members contains an exception
data Calculation = Exception String | Result (Value) | Incomplete (Expr) deriving Eq
instance Show (Calculation) where
    show (Result r) = show r
    show (Exception s) = "Exception: " ++ s
    show (Incomplete e) = show e

-- represents an arithmetic expression
data Expr = 
            Undefined String                -- undefined
          | Skip                            -- returns Null
          | Val (Value)                     -- value
          | Add Expr Expr                   -- addition
          | Sub Expr Expr                   -- subtraction
          | Prod Expr Expr                  -- product
          | Neg Expr                        -- negation
          | Div Expr Expr                   -- division
          | Exp Expr Expr                   -- exponent
          | Eq Expr Expr                    -- equal
          | Gt Expr Expr                    -- greater than
          | Lt Expr Expr                    -- less than
          | And Expr Expr                   -- boolean and
          | Or Expr Expr                    -- boolean or
          | Not Expr                        -- boolean not
          | Def Id Expr Expr                -- identifier assignment
          | EagerDef Id Expr Expr           -- identifier assignment
          | Defun Id [Id] Expr Expr         -- function definition
          | Var Id                          -- identifier
          | Func Id [Expr]                  -- function cal
          | If Expr Expr Expr               -- conditional
          | For Id (Expr) (Expr)            -- iteration
          | Range (Expr)                    -- range, start -> finish -> step size
          | Output (Expr) (Expr)            -- output
          | Placeholder                     -- the next statement should go here
          | Import String
          deriving Eq
se' :: (Show a) => [a] -> String
se' [] = []
se' (h:t) = " " ++ show h ++ (se' t)
se :: (Show a) => String -> [a] -> String
se sym (h:t) = "(" ++ sym ++ " " ++ (show h) ++ (se' t) ++ ")"
instance Show(Expr) where
    show (Undefined s) = "Undefined " ++ s
    show Skip = "Skip"
    show (Val v) = show v
    show (Add x y) = se "+" [x, y]
    show (Sub x y) = se "-" [x, y]
    show (Prod x y) = se "*" [x, y]
    show (Div x y) = se "/" [x, y]
    show (Exp x y) = se "^" [x, y]
    show (Eq x y) = se "==" [x, y]
    show (Gt x y) = se ">" [x, y]
    show (Lt x y) = se "<" [x, y]
    show (And x y) = se "&" [x, y]
    show (Or x y) = se "|" [x, y]
    show (Not x) = se "!" [x]
    show (Def a b c) = "(def " ++ (show a) ++ se' [b, c] ++ ")"
    show (EagerDef a b c) = "(eager def " ++ (show a) ++ se' [b, c] ++ ")"
    show (Defun a b c d) = "(def " ++ (show a) ++ " " ++ (show b) ++ se' [c, d] ++ ")"
    show (Var v) = show v
    show (Func f p) = "(func " ++ (show f) ++ " " ++ (show p) ++ ")"
    show (If cond x y) = se "if" [cond, x, y]
    show (For x y z) = "(for " ++ (show x) ++ " in " ++ (show y) ++ " " ++ (show z) ++ ")"
    show (Range r) = "(range " ++ show r ++ ")"
    show (Output x y) = se "print" [x, y]
    show (Placeholder) = "**nothing**"
    show (Import s) = "import " ++ s
