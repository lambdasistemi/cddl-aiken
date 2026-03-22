{-# LANGUAGE DataKinds #-}

module CddlAiken.E2E.WithdrawalSpec (spec) where

import Cardano.Ledger.Address (RewardAccount (..))
import Cardano.Ledger.Alonzo.PParams (getLanguageView)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..), fromPlutusScript, mkPlutusScript)
import Cardano.Ledger.Alonzo.Tx (ScriptIntegrity (..), hashScriptIntegrity)
import Cardano.Ledger.Alonzo.TxWits (AlonzoTxWits (..), Redeemers (..), TxDats (..))
import Cardano.Ledger.Api.Tx (Tx, bodyTxL, mkBasicTx)
import Cardano.Ledger.Api.Tx.Out (TxOut, coinTxOutL, mkBasicTxOut)
import Cardano.Ledger.Api.Tx.Body
  ( TxBody
  , certsTxBodyL
  , collateralInputsTxBodyL
  , feeTxBodyL
  , inputsTxBodyL
  , mkBasicTxBody
  , outputsTxBodyL
  , scriptIntegrityHashTxBodyL
  , withdrawalsTxBodyL
  )
import Cardano.Ledger.BaseTypes (Network (..), StrictMaybe (..))
import Cardano.Ledger.BaseTypes (Inject (..))
import Cardano.Ledger.Coin (Coin (..), unCoin)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Conway.TxCert (ConwayDelegCert (..), ConwayTxCert (..))
import Cardano.Ledger.Core (PParams, Script, ScriptHash, hashScript)
import Cardano.Ledger.Credential (Credential (..), StakeCredential)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Ledger.Plutus.Data (Data (..))
import Cardano.Ledger.Plutus.Language (Language (..), Plutus (..), PlutusBinary (..))
import Cardano.Ledger.Shelley.API (Withdrawals (..))
import Cardano.Node.Client.Balance (balanceTx)
import Cardano.Ledger.Alonzo.Tx (AlonzoTx (..), IsValid (..))
import Cardano.Node.Client.E2E.Setup
  ( addKeyWitness
  , genesisAddr
  , genesisSignKey
  , withDevnet
  )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.N2C.Types (LSQChannel, LTxSChannel)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter, submitTx)
import Control.Concurrent (threadDelay)
import Unsafe.Coerce (unsafeCoerce)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as B16
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Lens.Micro ((&), (.~), (^.))
import PlutusLedgerApi.V1 qualified as PV1
import Test.Hspec (Spec, around, describe, it, shouldSatisfy)

spec :: Spec
spec = around withDevnetBracket $ do
  describe "CDDL withdrawal validator" $ do
    it "accepts valid CBOR key/value" $ \(lsq, ltxs) -> do
      let prov = mkN2CProvider lsq
          sub = mkN2CSubmitter ltxs
      pp <- queryProtocolParams prov

      let (_script, scriptHash) = loadScript
          stakeCred = ScriptHashObj scriptHash

      -- Step 1: register the staking credential
      registerResult <- registerStakeCred prov sub pp stakeCred
      registerResult `shouldSatisfy` isSubmitted

      -- Wait for registration to land
      threadDelay 2_000_000

      -- Step 2: submit withdrawal with valid CBOR
      utxos2 <- queryUTxOs prov genesisAddr
      withdrawResult <- submitWithdrawal prov sub pp utxos2 validKeyCbor validValueCbor
      withdrawResult `shouldSatisfy` isSubmitted

    it "rejects invalid CBOR key/value" $ \(lsq, ltxs) -> do
      let prov = mkN2CProvider lsq
          sub = mkN2CSubmitter ltxs
      pp <- queryProtocolParams prov

      let (_script, scriptHash) = loadScript
          stakeCred = ScriptHashObj scriptHash

      -- Register credential (may already be registered from prev test)
      _ <- registerStakeCred prov sub pp stakeCred
      threadDelay 2_000_000

      -- Submit withdrawal with invalid CBOR
      utxos2 <- queryUTxOs prov genesisAddr
      withdrawResult <- submitWithdrawal prov sub pp utxos2 invalidKeyCbor invalidValueCbor
      withdrawResult `shouldSatisfy` isRejected

-- | Register a staking credential via a simple tx with a RegTxCert.
-- balanceTx doesn't account for cert deposits, so we subtract the deposit
-- from the change output it produces.
registerStakeCred
  :: Provider IO -> Submitter IO -> PParams ConwayEra -> StakeCredential -> IO SubmitResult
registerStakeCred prov sub pp stakeCred = do
  utxos <- queryUTxOs prov genesisAddr
  let deposit = Coin 400000
      cert = ConwayTxCertDeleg (ConwayRegCert stakeCred (SJust deposit))
      body =
        (mkBasicTxBody :: TxBody ConwayEra)
          & certsTxBodyL .~ StrictSeq.singleton cert
  case balanceTx pp utxos genesisAddr (mkBasicTx body) of
    Left err -> error $ "register balanceTx: " <> show err
    Right balanced ->
      -- Subtract deposit from the change output (last output added by balanceTx)
      let bdy = balanced ^. bodyTxL
          outs = bdy ^. outputsTxBodyL
          adjustedOuts = adjustLastOutput outs (\(Coin c) -> Coin (c - unCoin deposit))
          fixed = balanced & bodyTxL .~ (bdy & outputsTxBodyL .~ adjustedOuts)
          signed = addKeyWitness genesisSignKey fixed
       in submitTx sub signed

-- | Build and submit a withdrawal transaction
submitWithdrawal
  :: Provider IO
  -> Submitter IO
  -> PParams ConwayEra
  -> [(TxIn, TxOut ConwayEra)]
  -> BS.ByteString
  -> BS.ByteString
  -> IO SubmitResult
submitWithdrawal _prov sub pp utxos keyCbor valueCbor = do
  let (script, scriptHash) = loadScript
      stakeCred = ScriptHashObj scriptHash
      rewardAcct = RewardAccount Testnet stakeCred
      redeemer = PV1.List [PV1.B keyCbor, PV1.B valueCbor]

      rdmrs =
        Redeemers $
          Map.singleton
            (ConwayRewarding (AsIx 0))
            (Data redeemer, mempty)

      langViews = Set.singleton (getLanguageView pp PlutusV3)
      integrity =
        hashScriptIntegrity
          (ScriptIntegrity rdmrs (TxDats mempty :: TxDats ConwayEra) langViews)

  let (feeIn, feeOut) = case utxos of
        (x : _) -> x
        [] -> error "no UTxOs"
      Coin available = feeOut ^. coinTxOutL
      fee = Coin 1_000_000
      changeCoin = Coin (available - unCoin fee)
      changeOut = mkBasicTxOut genesisAddr (inject changeCoin)

      finalBody =
        (mkBasicTxBody :: TxBody ConwayEra)
          & withdrawalsTxBodyL .~ Withdrawals (Map.singleton rewardAcct mempty)
          & scriptIntegrityHashTxBodyL .~ SJust integrity
          & collateralInputsTxBodyL .~ Set.singleton feeIn
          & inputsTxBodyL .~ Set.singleton feeIn
          & outputsTxBodyL .~ StrictSeq.singleton changeOut
          & feeTxBodyL .~ fee

      -- Construct witnesses directly via pattern (avoids MemoBytes staleness)
      wits =
        AlonzoTxWits
          { txwitsVKey = mempty
          , txwitsBoot = mempty
          , txscripts = Map.singleton scriptHash script
          , txdats = TxDats mempty
          , txrdmrs = rdmrs
          }

      -- Construct tx directly using AlonzoTx to avoid MemoBytes staleness
      -- from lens modifications on mkBasicTx
      alonzoTx =
        AlonzoTx
          { atBody = finalBody
          , atWits = wits
          , atIsValid = IsValid True
          , atAuxData = SNothing
          }
      -- Use unsafeCoerce to wrap AlonzoTx as Tx ConwayEra
      -- (MkConwayTx constructor is not exported)
      signedTx = addKeyWitness genesisSignKey (unsafeCoerce alonzoTx :: Tx ConwayEra)
  submitTx sub signedTx

-- | Bracket that starts the local devnet and provides channels
withDevnetBracket :: ((LSQChannel, LTxSChannel) -> IO ()) -> IO ()
withDevnetBracket action = withDevnet $ \lsq ltxs ->
  action (lsq, ltxs)

-- | Load the pre-compiled Plutus script from the blueprint
loadScript :: (Script ConwayEra, ScriptHash)
loadScript =
  let scriptHex = compiledCodeHex
      scriptBytes = case B16.decode scriptHex of
        Right bs -> bs
        Left err -> error $ "Invalid hex: " <> show err
      -- Aiken compiledCode is double-CBOR: CBOR(bytes(flat_uplc))
      -- PlutusBinary expects the outer CBOR envelope intact
      plutus = Plutus @PlutusV3 $ PlutusBinary $ SBS.toShort scriptBytes
   in case mkPlutusScript @ConwayEra plutus of
        Just ps ->
          let s = fromPlutusScript ps
           in (s, hashScript @ConwayEra s)
        Nothing -> error "loadScript: invalid PlutusV3 script"

-- | Adjust the coin value of the last output in a sequence
-- | Adjust the coin value of the last output in a sequence
adjustLastOutput
  :: StrictSeq.StrictSeq (TxOut ConwayEra)
  -> (Coin -> Coin)
  -> StrictSeq.StrictSeq (TxOut ConwayEra)
adjustLastOutput outs f =
  let n = StrictSeq.length outs
   in case StrictSeq.lookup (n - 1) outs of
        Nothing -> outs
        Just lastOut ->
          let adjusted = lastOut & coinTxOutL .~ f (lastOut ^. coinTxOutL)
           in StrictSeq.take (n - 1) outs StrictSeq.|> adjusted

isSubmitted :: SubmitResult -> Bool
isSubmitted (Submitted _) = True
isSubmitted _ = False

isRejected :: SubmitResult -> Bool
isRejected (Rejected _) = True
isRejected _ = False

-- | Valid CBOR key: {"owner": <28 zero bytes>}
validKeyCbor :: BS.ByteString
validKeyCbor =
  BS.pack $
    [0xa1, 0x65, 0x6f, 0x77, 0x6e, 0x65, 0x72, 0x58, 0x1c]
      ++ replicate 28 0x00

-- | Valid CBOR value: {"amount": 1, "payload": <4 bytes>}
validValueCbor :: BS.ByteString
validValueCbor =
  BS.pack
    [ 0xa2
    , 0x66, 0x61, 0x6d, 0x6f, 0x75, 0x6e, 0x74 -- "amount"
    , 0x01 -- uint 1
    , 0x67, 0x70, 0x61, 0x79, 0x6c, 0x6f, 0x61, 0x64 -- "payload"
    , 0x44, 0xde, 0xad, 0xbe, 0xef -- bstr 4 bytes
    ]

-- | Invalid CBOR (uint, not a map)
invalidKeyCbor :: BS.ByteString
invalidKeyCbor = BS.pack [0x05]

invalidValueCbor :: BS.ByteString
invalidValueCbor = BS.pack [0x05]

compiledCodeHex :: BS.ByteString
compiledCodeHex = "59040901010029800aba2aba1aba0aab9faab9eaab9dab9a488888896600264646644b30013370e900218031baa00289919912cc004c03800a2646530012232325980099b87375a6026002900544c018cc048c04cc050004cc048c04cc0500092f5c11640386eb0c048004c038dd519801801000c88c8c8cc896600266e1cdd6980a801a400d130083301437533001001801401971833014375066e000040092f5c11640406eb4c04cc050004dd69809980a0011bac3012001300e37546600600400322323233225980099b87375a602a006900244c020cc050dd4cc0040060050065c60cc050dd419b800010024bd704590101bad30133014001375a602660280046eb0c048004c038dd519801801000cdd718078024dd71807802a44444b30013370e64b30013371290011bad30150018992cc004cdc79bae30160014881056f776e6572008992cc004cdc39b8d375c602e002901c44dd6980b980c000c5901218099baa33005003375a602c602e00316404460246ea8cc014008dd6980a980b000c5901018089baa3300500148000dc6800c56600266e1cc8c96600266e2520040018acc004cdc4800a400d1325980099b8f375c602e002910106616d6f756e7400899192cc004cdc79bae30190014881077061796c6f61640089bad3019301a301637546601000e6eb4c064c0680062c80a0c054dd5198040032cc004cdc4240080071325980099b8f375c6032002911056c6162656c0089bad3019301a301637546601200e6eb4c064c068006200480a0c054dd519804003000c40050131bad30173018301437546464b30013370e6eb4c0640052000898061980c180c980d0009980c180c980d00125eb822c80a0dd6180c000980a1baa33009005375a602e603000316404860266ea8cc018010dd6980b180b8014590114590111bad3015001301137546600a00490001b8d0028a518b201e8b201e1119194c004cdc1800a40813370c00290204dc0240049112cc004cdc4001240611300833014374e660286ea000ccc050dd400125eb80cc050dd4180080325eb82264b30013370e006901844c024cc054dd39980a9ba8004330153750600c600400e97ae0330153750600200e97ae08acc004cdc3801a40651300933015374e6602a6ea0010cc054dd419b8033704600c600400e90400218031800803a5eb80cc054dd419b80007480192f5c115980099b87003480d2260126602a6e9ccc054dd40021980a9ba83370066e00cdc019b823006300200748202020040cdc118031800803a4101001066e08c018cdc0003a400c904002180319b80007480212f5c06602a6ea0cdc0003a401497ae08b202240448088dc024008808060020046e38008dd2a400116402c6018002601660106ea800cdd61805001c59005180418048009804001180400098019baa0088a4d1365640041"
