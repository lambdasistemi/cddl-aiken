module CddlAiken.Aiken.Generator (
  generateAiken,
  generateValidator,
)
where

import CddlAiken.Aiken.Cbor (cborLibrary)
import CddlAiken.Cddl.Types (
  CborSchema (..),
  Constraint (..),
  Key (..),
  MapEntry (..),
  Occurrence (..),
  Schema (..),
  SizeConstraint (..),
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (chr, ord)
import Data.List (sortOn)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)

-- | Generate a complete Aiken validator project as a map of file paths to contents
generateAiken :: Schema -> [(FilePath, Text)]
generateAiken schema =
  [ ("lib/cbor.ak", cborLibrary)
  , ("validators/schema.ak", generateValidator schema)
  , ("aiken.toml", aikenToml)
  ]

-- | Generate the withdrawal validator source
generateValidator :: Schema -> Text
generateValidator schema =
  T.unlines
    [ "use aiken/builtin"
    , "use cardano/address.{Credential}"
    , "use cardano/transaction.{Transaction}"
    , "use cbor.{ParseResult, parse_map_header, parse_array_header,"
    , "          parse_uint, parse_int, parse_tstr, parse_bstr,"
    , "          parse_bool, parse_null, skip_value}"
    , ""
    , "/// Withdrawal validator that validates CBOR-encoded request"
    , "/// key and value against a CDDL schema."
    , "validator cddl_schema {"
    , "  withdraw(redeemer: Data, _account: Credential, _self: Transaction) {"
    , "    // Redeemer: (key_bytes, value_bytes)"
    , "    expect (key_bytes, value_bytes): (ByteArray, ByteArray) = redeemer"
    , ""
    , "    // Validate key"
    , "    let key_end = validate_key(key_bytes, 0)"
    , "    expect key_end == builtin.length_of_bytearray(key_bytes)"
    , ""
    , "    // Validate value"
    , "    let value_end = validate_value(value_bytes, 0)"
    , "    expect value_end == builtin.length_of_bytearray(value_bytes)"
    , ""
    , "    True"
    , "  }"
    , "}"
    , ""
    , generateSchemaFn "validate_key" (schemaKey schema)
    , ""
    , generateSchemaFn "validate_value" (schemaValue schema)
    ]

-- | Generate a validation function for a schema
generateSchemaFn :: Text -> CborSchema -> Text
generateSchemaFn name schema =
  T.unlines
    [ "fn " <> name <> "(bytes: ByteArray, pos: Int) -> Int {"
    , indent 2 (generateBody schema)
    , "}"
    ]

-- | Generate the body of a validation function
generateBody :: CborSchema -> Text
generateBody schema = case schema of
  CUint constraint ->
    let vname = if isNothing constraint then "_v" else "v"
     in T.unlines $
          ["let ParseResult { value: " <> vname <> ", pos } = parse_uint(bytes, pos)"]
            ++ constraintChecks "v" constraint
            ++ ["pos"]
  CInt constraint ->
    let vname = if isNothing constraint then "_v" else "v"
     in T.unlines $
          ["let ParseResult { value: " <> vname <> ", pos } = parse_int(bytes, pos)"]
            ++ constraintChecks "v" constraint
            ++ ["pos"]
  CTstr sizeConstraint ->
    let vname = if isNothing sizeConstraint then "_v" else "v"
     in T.unlines $
          ["let ParseResult { value: " <> vname <> ", pos } = parse_tstr(bytes, pos)"]
            ++ sizeChecks "v" sizeConstraint
            ++ ["pos"]
  CBstr sizeConstraint ->
    let vname = if isNothing sizeConstraint then "_v" else "v"
     in T.unlines $
          ["let ParseResult { value: " <> vname <> ", pos } = parse_bstr(bytes, pos)"]
            ++ sizeChecks "v" sizeConstraint
            ++ ["pos"]
  CBool ->
    T.unlines
      [ "let ParseResult { pos, .. } = parse_bool(bytes, pos)"
      , "pos"
      ]
  CNull ->
    "parse_null(bytes, pos)"
  CMap entries ->
    generateMapBody entries
  CArray elements ->
    generateArrayBody elements
  CChoice _alternatives ->
    T.unlines
      [ "// Choice validation — peek at major type"
      , "skip_value(bytes, pos)"
      ]
  CRef _name ->
    "fail @\"unresolved reference\""

-- | Generate map validation body with canonical key ordering
generateMapBody :: [MapEntry] -> Text
generateMapBody entries =
  let
    sorted = sortOn (\e -> case entryKey e of TextKey k -> k) entries
    minEntries = sum [minOcc (entryOccurrence e) | e <- sorted]
    maxEntries = sum [maxOcc (entryOccurrence e) | e <- sorted]
   in
    T.unlines $
      [ "let ParseResult { value: count, pos } = parse_map_header(bytes, pos)"
      , "expect count >= " <> showT minEntries
      ]
        ++ ["expect count <= " <> showT maxEntries | minEntries /= maxEntries]
        ++ [""]
        ++ generateCanonicalEntries sorted 0
  where
    minOcc :: Occurrence -> Int
    minOcc Required = 1
    minOcc Optional = 0
    minOcc ZeroOrMore = 0
    minOcc OneOrMore = 1

    maxOcc :: Occurrence -> Int
    maxOcc Required = 1
    maxOcc Optional = 1
    maxOcc ZeroOrMore = 100
    maxOcc OneOrMore = 100

-- | Generate sequential key validation for sorted map entries
generateCanonicalEntries :: [MapEntry] -> Int -> [Text]
generateCanonicalEntries [] _ = ["pos"]
generateCanonicalEntries (MapEntry (TextKey keyName) occ valSchema : rest) idx =
  let
    keyHex = textToHex keyName
    suffix = showT idx
   in
    case occ of
      Required ->
        [ "// \"" <> keyName <> "\" (required)"
        , "let ParseResult { value: k" <> suffix <> ", pos } = parse_tstr(bytes, pos)"
        , "expect k" <> suffix <> " == #\"" <> keyHex <> "\""
        , "let pos = {"
        , indent 2 (generateBody valSchema)
        , "}"
        ]
          ++ generateCanonicalEntries rest (idx + 1)
      Optional ->
        let remaining = countRequired rest
         in [ "// \"" <> keyName <> "\" (optional)"
            , "let pos ="
            , "  if count > " <> showT (remaining + idx) <> " {"
            , "    let saved" <> suffix <> " = pos"
            , "    let ParseResult { value: k" <> suffix <> ", pos } = parse_tstr(bytes, pos)"
            , "    if k" <> suffix <> " == #\"" <> keyHex <> "\" {"
            , indent 6 (generateBody valSchema)
            , "    } else {"
            , "      // Optional key absent, restore position"
            , "      saved" <> suffix
            , "    }"
            , "  } else {"
            , "    pos"
            , "  }"
            ]
              ++ generateCanonicalEntries rest (idx + 1)
      _ ->
        [ "// TODO: " <> showT occ <> " for map entries"
        , "pos"
        ]
          ++ generateCanonicalEntries rest (idx + 1)

-- | Count required entries
countRequired :: [MapEntry] -> Int
countRequired = length . filter (\e -> entryOccurrence e == Required)

-- | Generate array validation body
generateArrayBody :: [CborSchema] -> Text
generateArrayBody elements =
  T.unlines $
    [ "let ParseResult { value: count, pos } = parse_array_header(bytes, pos)"
    , "expect count == " <> showT (length elements)
    ]
      ++ concatMap
        ( \(_i, el) ->
            [ "let pos = {"
            , indent 2 (generateBody el)
            , "}"
            ]
        )
        (zip [0 :: Int ..] elements)
      ++ ["pos"]

-- | Generate constraint checks for integers
constraintChecks :: Text -> Maybe Constraint -> [Text]
constraintChecks _ Nothing = []
constraintChecks var (Just c) = case c of
  Le n -> ["expect " <> var <> " <= " <> showT n]
  Ge n -> ["expect " <> var <> " >= " <> showT n]
  Range lo hi ->
    [ "expect " <> var <> " >= " <> showT lo
    , "expect " <> var <> " <= " <> showT hi
    ]
  CddlAiken.Cddl.Types.Eq n -> ["expect " <> var <> " == " <> showT n]

-- | Generate size checks for string/bytes
sizeChecks :: Text -> Maybe SizeConstraint -> [Text]
sizeChecks _ Nothing = []
sizeChecks var (Just c) = case c of
  ExactSize n ->
    ["expect builtin.length_of_bytearray(" <> var <> ") == " <> showT n]
  SizeRange lo hi ->
    [ "expect builtin.length_of_bytearray(" <> var <> ") >= " <> showT lo
    , "expect builtin.length_of_bytearray(" <> var <> ") <= " <> showT hi
    ]

-- | Convert Text to hex representation for Aiken ByteArray literal
textToHex :: Text -> Text
textToHex = bsToHex . TE.encodeUtf8

-- | Convert ByteString to hex
bsToHex :: ByteString -> Text
bsToHex = T.pack . concatMap (\w -> [hexChar (w `div` 16), hexChar (w `mod` 16)]) . BS.unpack

-- | Single hex character
hexChar :: Word8 -> Char
hexChar n
  | n < 10 = chr (fromIntegral n + ord '0')
  | otherwise = chr (fromIntegral n - 10 + ord 'a')

-- | Indent text by n spaces
indent :: Int -> Text -> Text
indent n = T.intercalate "\n" . map (\l -> if T.null l then l else T.replicate n " " <> l) . T.lines

-- | Show as Text
showT :: (Show a) => a -> Text
showT = T.pack . show

-- | aiken.toml template
aikenToml :: Text
aikenToml =
  T.unlines
    [ "name = \"generated/cddl_schema\""
    , "version = \"0.0.1\""
    , "compiler = \"v1.1.21\""
    , "plutus = \"v3\""
    , ""
    , "[repository]"
    , "user = \"generated\""
    , "project = \"cddl_schema\""
    , "platform = \"github\""
    , ""
    , "[[dependencies]]"
    , "name = \"aiken-lang/stdlib\""
    , "version = \"v3.0.0\""
    , "source = \"github\""
    ]
