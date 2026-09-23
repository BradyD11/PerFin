{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Smart constructors: the only way into the invariant-carrying types in
-- "Domain.Types".
--
-- Every function here returns 'Either' rather than throwing or silently
-- repairing. A malformed CSV row becomes a reported error next to its line
-- number, never a wrong number in a report.
module Domain.Validation
  ( ValidationError (..)
  , renderValidationError
  , mkAccountName
  , mkMerchant
  , mkTransaction
  , normalizeMerchant
  ) where

import           Data.Char     (isSpace)
import           Data.Text     (Text)
import qualified Data.Text     as T
import           Data.Time     (Day)

import           Domain.Types

data ValidationError
  = EmptyAccountName
  | EmptyMerchant
  | FutureDate Day Day        -- ^ offending date, today
  | ZeroAmount Text           -- ^ merchant, for context
  | MalformedAmount Text
  | MalformedDate Text
  | MalformedRow Text
  deriving stock (Eq, Show)

renderValidationError :: ValidationError -> Text
renderValidationError = \case
  EmptyAccountName  -> "account name is empty"
  EmptyMerchant     -> "merchant is empty after trimming"
  FutureDate d today ->
    "date " <> tshow d <> " is in the future (today is " <> tshow today <> ")"
  ZeroAmount m      -> "zero-amount transaction with no memo: " <> m
  MalformedAmount t -> "malformed amount: " <> t
  MalformedDate t   -> "malformed date: " <> t
  MalformedRow t    -> "malformed row: " <> t
  where tshow = T.pack . show

mkAccountName :: Text -> Either ValidationError AccountName
mkAccountName raw =
  let t = T.strip raw
  in if T.null t then Left EmptyAccountName else Right (unsafeAccountName t)

mkMerchant :: Text -> Either ValidationError Merchant
mkMerchant raw =
  let t = collapseSpaces (T.strip raw)
  in if T.null t then Left EmptyMerchant else Right (unsafeMerchant t)

-- | Build a validated transaction.
--
-- @today@ is passed in rather than read from the system clock so that
-- validation stays a pure function — which is what makes it property-testable.
--
-- Rejects:
--
-- * dates after @today@ (a statement cannot contain tomorrow's spending;
--   this catches a swapped MM\/DD and a mis-parsed year)
-- * zero amounts (no real posted transaction moves $0; in practice this is
--   a parse failure that produced a 0)
-- * merchants that are empty once trimmed
--
-- The caller supplies 'TransactionId' because deriving it is "Import.Dedup"'s
-- job, and it needs the already-validated fields.
mkTransaction
  :: Day                  -- ^ today, for the future-date check
  -> TransactionId
  -> AccountName
  -> Day
  -> Cents
  -> Text                 -- ^ raw merchant
  -> Category
  -> Either ValidationError Transaction
mkTransaction today tid account day amount rawMerchant category = do
  merchant <- mkMerchant rawMerchant
  if day > today
    then Left (FutureDate day today)
    else if amount == Cents 0
      then Left (ZeroAmount (unMerchant merchant))
      else Right Transaction
        { txId       = tid
        , txDate     = day
        , txAmount   = amount
        , txMerchant = merchant
        , txAccount  = account
        , txCategory = category
        }

-- | Canonical merchant form used for dedup keys and rule matching.
--
-- Uppercases, collapses whitespace, and strips digits. Digits go because banks
-- append volatile reference numbers to the description
-- (@"KLM AIRLINE 0742143148993800-6180104 DC"@), and those change between
-- exports of the same transaction — which would make a re-import look like new
-- spending.
normalizeMerchant :: Text -> Text
normalizeMerchant =
  collapseSpaces
    . T.strip
    . T.map (\c -> if c `elem` ("0123456789" :: String) then ' ' else c)
    . T.toUpper

collapseSpaces :: Text -> Text
collapseSpaces = T.unwords . T.words . T.map (\c -> if isSpace c then ' ' else c)
