module Main (main) where

import CddlAiken.E2E.WithdrawalSpec qualified
import Test.Hspec (hspec)

main :: IO ()
main = hspec CddlAiken.E2E.WithdrawalSpec.spec
