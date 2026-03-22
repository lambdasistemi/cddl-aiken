module Main (main) where

import Test.Aiken.Generator qualified
import Test.Cddl.Parser qualified
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
  Test.Cddl.Parser.spec
  Test.Aiken.Generator.spec
