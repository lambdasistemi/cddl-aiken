module CddlAiken.Cddl.Parser (
  parseCddl,
  parseSchema,
)
where

import CddlAiken.Cddl.Types (
  CborSchema (..),
  Constraint (..),
  Key (..),
  MapEntry (..),
  Occurrence (..),
  Schema (..),
  SizeConstraint (..),
 )
import Control.Monad (void)
import Data.Char qualified
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void)
import Text.Megaparsec (
  MonadParsec (..),
  Parsec,
  between,
  choice,
  empty,
  eof,
  many,
  optional,
  parse,
  satisfy,
  sepBy1,
  (<?>),
  (<|>),
 )
import Text.Megaparsec.Char (char, letterChar, space1)
import Text.Megaparsec.Char.Lexer qualified as L

type Parser = Parsec Void Text

-- | Whitespace consumer (handles comments starting with ;)
sc :: Parser ()
sc =
  L.space
    space1
    (L.skipLineComment ";")
    empty

-- | Lexeme wrapper
lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

-- | Symbol parser
symbol :: Text -> Parser Text
symbol = L.symbol sc

-- | Parse an integer literal
integer :: Parser Integer
integer = lexeme L.decimal

-- | Parse a quoted string
quotedString :: Parser Text
quotedString = lexeme $ do
  void $ char '"'
  content <- many (satisfy (/= '"'))
  void $ char '"'
  pure $ T.pack content

-- | Parse an identifier (rule name)
identifier :: Parser Text
identifier = lexeme $ do
  first <- letterChar <|> char '_'
  rest <- many (letterChar <|> char '_' <|> char '-' <|> satisfy isDigitChar)
  pure $ T.pack (first : rest)
  where
    isDigitChar = Data.Char.isDigit

{- | Parse a complete CDDL file into a Schema
Expects exactly two top-level rules: "key" and "value"
-}
parseCddl :: Text -> Either String Schema
parseCddl input =
  case parse (sc *> many rule <* eof) "<cddl>" input of
    Left err -> Left (show err)
    Right rules ->
      let ruleMap = Map.fromList rules
       in case (Map.lookup "key" ruleMap, Map.lookup "value" ruleMap) of
            (Just k, Just v) -> Right $ Schema k v
            (Nothing, _) -> Left "Missing 'key' rule"
            (_, Nothing) -> Left "Missing 'value' rule"

-- | Parse a Schema from text (alias for parseCddl)
parseSchema :: Text -> Either String Schema
parseSchema = parseCddl

-- | Parse a single rule: name = type
rule :: Parser (Text, CborSchema)
rule = do
  name <- identifier
  void $ symbol "="
  (name,) <$> cborType

-- | Parse a CBOR type expression
cborType :: Parser CborSchema
cborType = do
  first <- singleType
  rest <- many (symbol "/" *> singleType)
  pure $ case rest of
    [] -> first
    _ -> CChoice (first : rest)

-- | Parse a single (non-choice) type
singleType :: Parser CborSchema
singleType = do
  base <- baseType
  constraint <- optional constraintSuffix
  applyConstraint base constraint

-- | Apply a constraint suffix to a base type
applyConstraint :: CborSchema -> Maybe ConstraintSuffix -> Parser CborSchema
applyConstraint base Nothing = pure base
applyConstraint (CUint _) (Just (ValueConstraint c)) = pure $ CUint (Just c)
applyConstraint (CInt _) (Just (ValueConstraint c)) = pure $ CInt (Just c)
applyConstraint (CTstr _) (Just (SizeConstraintSuffix s)) = pure $ CTstr (Just s)
applyConstraint (CBstr _) (Just (SizeConstraintSuffix s)) = pure $ CBstr (Just s)
applyConstraint _ _ = fail "constraint not applicable to this type"

data ConstraintSuffix
  = ValueConstraint Constraint
  | SizeConstraintSuffix SizeConstraint

-- | Parse .size or .le/.ge constraints
constraintSuffix :: Parser ConstraintSuffix
constraintSuffix =
  choice
    [ sizeConstraint
    , leConstraint
    , geConstraint
    , eqConstraint
    ]

sizeConstraint :: Parser ConstraintSuffix
sizeConstraint = do
  void $ symbol ".size"
  choice
    [ do
        void $ symbol "("
        lo <- integer
        void $ symbol ".."
        hi <- integer
        void $ symbol ")"
        pure $ SizeConstraintSuffix (SizeRange lo hi)
    , SizeConstraintSuffix . ExactSize <$> integer
    ]

leConstraint :: Parser ConstraintSuffix
leConstraint = do
  void $ symbol ".le"
  ValueConstraint . Le <$> integer

geConstraint :: Parser ConstraintSuffix
geConstraint = do
  void $ symbol ".ge"
  ValueConstraint . Ge <$> integer

eqConstraint :: Parser ConstraintSuffix
eqConstraint = do
  void $ symbol ".eq"
  ValueConstraint . CddlAiken.Cddl.Types.Eq <$> integer

-- | Parse a base type (without constraints)
baseType :: Parser CborSchema
baseType =
  choice
    [ CUint Nothing <$ symbol "uint"
    , CInt Nothing <$ symbol "int"
    , CTstr Nothing <$ symbol "tstr"
    , CBstr Nothing <$ symbol "bstr"
    , CBool <$ symbol "bool"
    , CNull <$ symbol "null"
    , mapType
    , arrayType
    , CRef <$> identifier
    ]
    <?> "type"

-- | Parse a map type: { entries }
mapType :: Parser CborSchema
mapType = CMap <$> between (symbol "{") (symbol "}") (mapEntry `sepBy1` symbol ",")

-- | Parse a single map entry: [occurrence] "key" : type
mapEntry :: Parser MapEntry
mapEntry = do
  occ <- occurrenceIndicator
  key <- TextKey <$> quotedString
  void $ symbol ":"
  MapEntry key occ <$> cborType

-- | Parse occurrence indicator
occurrenceIndicator :: Parser Occurrence
occurrenceIndicator =
  choice
    [ Optional <$ symbol "?"
    , ZeroOrMore <$ symbol "*"
    , OneOrMore <$ symbol "+"
    , pure Required
    ]

-- | Parse an array type: [ elements ]
arrayType :: Parser CborSchema
arrayType = CArray <$> between (symbol "[") (symbol "]") (cborType `sepBy1` symbol ",")
