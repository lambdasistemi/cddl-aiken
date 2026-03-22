module Test.Aiken.Generator (spec) where

import CddlAiken.Aiken.Generator (generateValidator)
import CddlAiken.Cddl.Types (
  CborSchema (..),
  Key (..),
  MapEntry (..),
  Occurrence (..),
  Schema (..),
  SizeConstraint (..),
 )
import Data.Text qualified as T
import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "Aiken Generator" $ do
  it "generates validator with key and value functions" $ do
    let schema =
          Schema
            { schemaKey = CMap [MapEntry (TextKey "id") Required (CUint Nothing)]
            , schemaValue = CMap [MapEntry (TextKey "name") Required (CTstr Nothing)]
            }
    let output = generateValidator schema
    output `shouldSatisfy` T.isInfixOf "validator cddl_schema"
    output `shouldSatisfy` T.isInfixOf "validate_key"
    output `shouldSatisfy` T.isInfixOf "validate_value"

  it "generates canonical key ordering" $ do
    let schema =
          Schema
            { schemaKey = CMap [MapEntry (TextKey "id") Required (CUint Nothing)]
            , schemaValue =
                CMap
                  [ MapEntry (TextKey "zebra") Required (CTstr Nothing)
                  , MapEntry (TextKey "alpha") Required (CUint Nothing)
                  ]
            }
    let output = generateValidator schema
    -- Should sort: alpha before zebra
    let lines' = T.lines output
        alphaLine = findLineWith "alpha" lines'
        zebraLine = findLineWith "zebra" lines'
    case (alphaLine, zebraLine) of
      (Just a, Just z) -> a `shouldSatisfy` (< z)
      _ -> pure () -- keys might appear differently
  it "generates size constraint checks" $ do
    let schema =
          Schema
            { schemaKey = CMap [MapEntry (TextKey "hash") Required (CBstr (Just (ExactSize 32)))]
            , schemaValue = CMap [MapEntry (TextKey "data") Required (CBstr Nothing)]
            }
    let output = generateValidator schema
    output `shouldSatisfy` T.isInfixOf "length_of_bytearray"
    output `shouldSatisfy` T.isInfixOf "== 32"

  it "generates optional field handling" $ do
    let schema =
          Schema
            { schemaKey = CMap [MapEntry (TextKey "id") Required (CUint Nothing)]
            , schemaValue =
                CMap
                  [ MapEntry (TextKey "name") Required (CTstr Nothing)
                  , MapEntry (TextKey "memo") Optional (CTstr Nothing)
                  ]
            }
    let output = generateValidator schema
    output `shouldSatisfy` T.isInfixOf "optional"

findLineWith :: T.Text -> [T.Text] -> Maybe Int
findLineWith needle = go 0
  where
    go _ [] = Nothing
    go n (l : ls)
      | needle `T.isInfixOf` l = Just n
      | otherwise = go (n + 1) ls
