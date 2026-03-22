module CddlAiken.E2E.WithdrawalSpec (spec) where

import Cardano.Ledger.Api (
  Addr (..),
  Coin (..),
  ConwayEra,
  Credential (..),
  Network (..),
  PParams,
  PlutusV3,
  Script,
  ScriptHash,
  StakeReference (..),
  Tx,
  TxIn,
  TxOut,
  hashScript,
 )
import Cardano.Ledger.Api qualified as L
import Cardano.Ledger.Conway.TxBody (ConwayTxBody)
import Cardano.Ledger.Core (bodyTxL, mkBasicTx, mkBasicTxBody)
import Cardano.Ledger.Plutus (PlutusBinary (..), Plutus (..))
import Cardano.Node.Client.E2E.Devnet (withCardanoNode)
import Cardano.Node.Client.E2E.Setup (
  addKeyWitness,
  devnetMagic,
  genesisAddr,
  genesisDir,
  genesisSignKey,
  withDevnet,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), submitTx)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Test.Hspec (Spec, around, describe, it, shouldSatisfy)

spec :: Spec
spec = around withDevnetBracket $ do
  describe "CDDL withdrawal validator" $ do
    it "accepts valid CBOR key/value" $ \(_lsq, _ltxs) -> do
      -- TODO: build and submit transaction with valid CBOR redeemer
      -- For now, just verify the devnet starts and we can query it
      pending

    it "rejects invalid CBOR key/value" $ \(_lsq, _ltxs) -> do
      -- TODO: build and submit transaction with invalid CBOR redeemer
      -- Should fail with phase-2 validation error
      pending

-- | Bracket that starts the local devnet and provides channels
withDevnetBracket :: ((a, b) -> IO c) -> IO c
withDevnetBracket action = withDevnet $ \lsq ltxs ->
  action (lsq, ltxs)
