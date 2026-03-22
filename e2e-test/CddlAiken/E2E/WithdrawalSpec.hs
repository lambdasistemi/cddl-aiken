module CddlAiken.E2E.WithdrawalSpec (spec) where

import Cardano.Node.Client.E2E.Setup (withDevnet)
import Cardano.Node.Client.N2C.Types (LSQChannel, LTxSChannel)
import Test.Hspec (Spec, around, describe, it, pendingWith)

spec :: Spec
spec = around withDevnetBracket $ do
  describe "CDDL withdrawal validator" $ do
    it "accepts valid CBOR key/value" $ \(_lsq, _ltxs) -> do
      pendingWith "TODO: build and submit transaction with valid CBOR redeemer"

    it "rejects invalid CBOR key/value" $ \(_lsq, _ltxs) -> do
      pendingWith "TODO: build and submit transaction with invalid CBOR redeemer"

-- | Bracket that starts the local devnet and provides channels
withDevnetBracket :: ((LSQChannel, LTxSChannel) -> IO ()) -> IO ()
withDevnetBracket action = withDevnet $ \lsq ltxs ->
  action (lsq, ltxs)
