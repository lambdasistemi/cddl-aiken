module CddlAiken.Cddl.Types (
  CborSchema (..),
  Key (..),
  Occurrence (..),
  Constraint (..),
  SizeConstraint (..),
  MapEntry (..),
  Schema (..),
)
where

import Data.Text (Text)

-- | Top-level schema: defines key and value shapes
data Schema = Schema
  { schemaKey :: CborSchema
  , schemaValue :: CborSchema
  }
  deriving stock (Show, Eq)

-- | CBOR structure description
data CborSchema
  = CUint (Maybe Constraint)
  | CInt (Maybe Constraint)
  | CTstr (Maybe SizeConstraint)
  | CBstr (Maybe SizeConstraint)
  | CBool
  | CNull
  | CMap [MapEntry]
  | CArray [CborSchema]
  | CChoice [CborSchema]
  | CRef Text
  deriving stock (Show, Eq)

-- | A single entry in a CBOR map
data MapEntry = MapEntry
  { entryKey :: Key
  , entryOccurrence :: Occurrence
  , entryValue :: CborSchema
  }
  deriving stock (Show, Eq)

-- | Map key (always a text string for JSON-like CDDL)
newtype Key
  = TextKey Text
  deriving stock (Show, Eq, Ord)

-- | Occurrence indicator
data Occurrence
  = Required
  | Optional
  | ZeroOrMore
  | OneOrMore
  deriving stock (Show, Eq)

-- | Value constraint for integers
data Constraint
  = Le Integer
  | Ge Integer
  | Range Integer Integer
  | Eq Integer
  deriving stock (Show, Eq)

-- | Size constraint for strings/bytes
data SizeConstraint
  = ExactSize Integer
  | SizeRange Integer Integer
  deriving stock (Show, Eq)
