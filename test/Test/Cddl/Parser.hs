module Test.Cddl.Parser (spec) where

import CddlAiken.Cddl.Parser (parseCddl)
import CddlAiken.Cddl.Types (
  CborSchema (..),
  Constraint (..),
  Key (..),
  MapEntry (..),
  Occurrence (..),
  Schema (..),
  SizeConstraint (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "CDDL Parser" $ do
  it "parses simple key/value with primitives" $ do
    let input =
          "key = { \"id\" : uint }\n\
          \value = { \"name\" : tstr }\n"
    parseCddl input
      `shouldBe` Right
        ( Schema
            { schemaKey = CMap [MapEntry (TextKey "id") Required (CUint Nothing)]
            , schemaValue = CMap [MapEntry (TextKey "name") Required (CTstr Nothing)]
            }
        )

  it "parses optional fields" $ do
    let input =
          "key = { \"id\" : uint }\n\
          \value = { \"name\" : tstr, ? \"memo\" : tstr }\n"
    case parseCddl input of
      Right (Schema _ val) ->
        val
          `shouldBe` CMap
            [ MapEntry (TextKey "name") Required (CTstr Nothing)
            , MapEntry (TextKey "memo") Optional (CTstr Nothing)
            ]
      Left err -> fail err

  it "parses size constraints" $ do
    let input =
          "key = { \"hash\" : bstr .size 32 }\n\
          \value = { \"data\" : bstr }\n"
    case parseCddl input of
      Right (Schema k _) ->
        k `shouldBe` CMap [MapEntry (TextKey "hash") Required (CBstr (Just (ExactSize 32)))]
      Left err -> fail err

  it "parses integer constraints" $ do
    let input =
          "key = { \"id\" : uint }\n\
          \value = { \"age\" : uint .le 150 }\n"
    case parseCddl input of
      Right (Schema _ val) ->
        val `shouldBe` CMap [MapEntry (TextKey "age") Required (CUint (Just (Le 150)))]
      Left err -> fail err

  it "parses array types" $ do
    let input =
          "key = [uint, uint]\n\
          \value = { \"data\" : bstr }\n"
    case parseCddl input of
      Right (Schema k _) ->
        k `shouldBe` CArray [CUint Nothing, CUint Nothing]
      Left err -> fail err

  it "parses multiple fields" $ do
    let input =
          "key = { \"owner\" : bstr .size 28 }\n\
          \value = { \"amount\" : uint, \"payload\" : bstr, ? \"label\" : tstr }\n"
    case parseCddl input of
      Right schema -> do
        schemaKey schema
          `shouldBe` CMap [MapEntry (TextKey "owner") Required (CBstr (Just (ExactSize 28)))]
        schemaValue schema
          `shouldBe` CMap
            [ MapEntry (TextKey "amount") Required (CUint Nothing)
            , MapEntry (TextKey "payload") Required (CBstr Nothing)
            , MapEntry (TextKey "label") Optional (CTstr Nothing)
            ]
      Left err -> fail err

  it "handles comments" $ do
    let input =
          "; This is a comment\n\
          \key = { \"id\" : uint }\n\
          \; Another comment\n\
          \value = { \"data\" : bstr }\n"
    case parseCddl input of
      Right _ -> () `shouldBe` ()
      Left err -> fail err

  it "rejects missing key rule" $ do
    let input = "value = { \"data\" : bstr }\n"
    case parseCddl input of
      Left err -> err `shouldBe` "Missing 'key' rule"
      Right _ -> fail "expected error"

  it "rejects missing value rule" $ do
    let input = "key = { \"id\" : uint }\n"
    case parseCddl input of
      Left err -> err `shouldBe` "Missing 'value' rule"
      Right _ -> fail "expected error"
