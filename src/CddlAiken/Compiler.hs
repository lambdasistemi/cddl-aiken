module CddlAiken.Compiler (
  compile,
  CompileError (..),
)
where

import CddlAiken.Aiken.Generator (generateAiken)
import CddlAiken.Cddl.Parser (parseCddl)
import CddlAiken.Cddl.Types (Schema)
import Data.Text (Text)

-- | Compilation errors
data CompileError
  = ParseError String
  | ValidationError String
  deriving stock (Show)

-- | Compile a CDDL source into Aiken project files
compile :: Text -> Either CompileError [(FilePath, Text)]
compile cddlSource = do
  schema <- parseSchema cddlSource
  validateSchema schema
  pure $ generateAiken schema

-- | Parse CDDL source
parseSchema :: Text -> Either CompileError Schema
parseSchema src = case parseCddl src of
  Left err -> Left (ParseError err)
  Right schema -> Right schema

-- | Validate the schema uses only supported features
validateSchema :: Schema -> Either CompileError ()
validateSchema _schema =
  -- For now, the parser already restricts to the supported subset.
  -- Future: check for unresolved references, unsupported nesting, etc.
  Right ()
