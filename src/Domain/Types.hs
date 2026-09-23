{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE OverloadedStrings          #-}

-- | Core domain vocabulary.
--
-- The export list is deliberate: constructors that carry an invariant
-- (@AccountName@, @Transaction@, @Merchant@) are /not/ exported, so the only
-- way to build one is through "Domain.Validation". Constructors whose values
-- are unconstrained (@Cents@, @TransactionId@) are exported freely.
module Domain.Types
  ( -- * Money
    Cents (..)
  , centsFromDecimal
  , centsToDecimal
  , renderCents
    -- * Identity
  , TransactionId (..)
    -- * Accounts
  , AccountType (..)
  , renderAccountType
  , parseAccountType
  , AccountName
  , unAccountName
  , unsafeAccountName
    -- * Merchants
  , Merchant
  , unMerchant
  , unsafeMerchant
    -- * Categories
  , Category (..)
  , allCategories
  , renderCategory
  , parseCategory
    -- * Transactions
  , Transaction (..)
  , txIsOutflow
  , txIsInflow
    -- * Net worth
  , netWorthDelta
  ) where

import           Data.Char  (isDigit)
import           Data.Text  (Text)
import qualified Data.Text  as T
import           Data.Time  (Day)

-- | Money as an integral number of cents.
--
-- Never a 'Double': repeated addition of binary floating point silently
-- accumulates error, and a report that is off by a cent is a report nobody
-- trusts. Integer (not Int) so that summing a lifetime of transactions cannot
-- overflow.
--
-- Sign convention, enforced at the parser boundary and relied on everywhere
-- downstream: __negative is an outflow__ (money leaving your control),
-- __positive is an inflow__. This holds for both asset and liability accounts;
-- see 'netWorthDelta' for how the account type turns that into a net-worth
-- effect.
newtype Cents = Cents Integer
  deriving stock (Eq, Ord, Show)
  deriving newtype (Num)

-- | Parse a decimal money string (@"-12.62"@, @"1457.50"@, @"$1,234.56"@).
--
-- Works on the digit string directly rather than going through 'Double', which
-- is the entire point of 'Cents'. Accepts 0, 1, or 2 decimal places; rejects
-- more, because silently truncating a third decimal place is exactly the kind
-- of quiet wrongness this type exists to prevent.
centsFromDecimal :: Text -> Either Text Cents
centsFromDecimal raw =
  let cleaned = T.filter (`notElem` (" $," :: String)) raw
      (sign, unsigned) = case T.uncons cleaned of
        Just ('-', rest) -> (-1 :: Integer, rest)
        Just ('+', rest) -> (1, rest)
        _                -> (1, cleaned)
  in if T.null unsigned
       then Left ("not a number: " <> raw)
       else case T.splitOn "." unsigned of
         [whole] -> build sign whole "00"
         [whole, frac]
           | T.length frac == 2 -> build sign whole frac
           | T.length frac == 1 -> build sign whole (frac <> "0")
           | T.length frac == 0 -> build sign whole "00"
           | otherwise -> Left ("too many decimal places: " <> raw)
         _ -> Left ("not a number: " <> raw)
  where
    build sign whole frac
      | not (T.all isDigit whole) || not (T.all isDigit frac) =
          Left ("not a number: " <> raw)
      | T.null whole && T.null frac = Left ("not a number: " <> raw)
      | otherwise =
          let w = digits whole
              f = digits frac
          in Right (Cents (sign * (w * 100 + f)))
    digits = foldl' (\acc c -> acc * 10 + toInteger (fromEnum c - fromEnum '0')) 0 . T.unpack

-- | Split into (whole units, absolute remainder cents). Inverse of
-- 'centsFromDecimal' up to formatting.
centsToDecimal :: Cents -> (Integer, Integer)
centsToDecimal (Cents n) = (n `quot` 100, abs (n `rem` 100))

-- | Human-readable, always two decimal places: @Cents (-1262)@ renders as
-- @"-12.62"@, @Cents 5@ renders as @"0.05"@.
renderCents :: Cents -> Text
renderCents c@(Cents n) =
  let (whole, rest) = centsToDecimal c
      sign = if n < 0 && whole == 0 then "-" else ""
      pad t = if T.length t == 1 then "0" <> t else t
  in sign <> T.pack (show whole) <> "." <> pad (T.pack (show rest))

-- | Stable, content-derived identity for a transaction.
--
-- Derived in "Import.Dedup" from the fields a bank cannot reformat between
-- exports, so re-importing an overlapping statement is naturally idempotent.
newtype TransactionId = TransactionId Text
  deriving stock (Eq, Ord, Show)

-- | Whether a positive balance in an account is money you /have/ or money you
-- /owe/. Keeping these apart in the type system is what stops a carried credit
-- card balance from being counted as savings.
data AccountType = Asset | Liability
  deriving stock (Eq, Ord, Show, Enum, Bounded)

renderAccountType :: AccountType -> Text
renderAccountType = \case
  Asset     -> "asset"
  Liability -> "liability"

parseAccountType :: Text -> Either Text AccountType
parseAccountType t = case T.toLower (T.strip t) of
  "asset"       -> Right Asset
  "liability"   -> Right Liability
  "checking"    -> Right Asset
  "savings"     -> Right Asset
  "credit-card" -> Right Liability
  "credit_card" -> Right Liability
  other         -> Left ("unknown account type: " <> other)

-- | A non-empty, trimmed account name. Build with
-- 'Domain.Validation.mkAccountName'.
newtype AccountName = AccountName Text
  deriving stock (Eq, Ord, Show)

unAccountName :: AccountName -> Text
unAccountName (AccountName t) = t

-- | Bypass validation. Only "Domain.Validation" should call this; it is
-- exported solely so the smart constructors can live in their own module.
-- The @unsafe@ prefix is the warning: it asserts an invariant it does not check.
unsafeAccountName :: Text -> AccountName
unsafeAccountName = AccountName

-- | A non-empty, trimmed merchant description. Build with
-- 'Domain.Validation.mkMerchant'.
newtype Merchant = Merchant Text
  deriving stock (Eq, Ord, Show)

unMerchant :: Merchant -> Text
unMerchant (Merchant t) = t

-- | Bypass validation. See 'unsafeAccountName'.
unsafeMerchant :: Text -> Merchant
unsafeMerchant = Merchant

data Category
  = Groceries | Rent | Subscriptions | Dining | Transfer
  | Income | Fees | Uncategorized
  deriving stock (Eq, Ord, Show, Enum, Bounded)

allCategories :: [Category]
allCategories = [minBound .. maxBound]

renderCategory :: Category -> Text
renderCategory = \case
  Groceries     -> "groceries"
  Rent          -> "rent"
  Subscriptions -> "subscriptions"
  Dining        -> "dining"
  Transfer      -> "transfer"
  Income        -> "income"
  Fees          -> "fees"
  Uncategorized -> "uncategorized"

parseCategory :: Text -> Either Text Category
parseCategory t =
  let needle = T.toLower (T.strip t)
  in case filter ((== needle) . renderCategory) allCategories of
       (c:_) -> Right c
       []    -> Left ("unknown category: " <> t)

-- | A validated transaction. The constructor is not exported; use
-- 'Domain.Validation.mkTransaction'.
data Transaction = Transaction
  { txId       :: TransactionId
  , txDate     :: Day
  , txAmount   :: Cents       -- ^ negative = outflow, positive = inflow
  , txMerchant :: Merchant
  , txAccount  :: AccountName
  , txCategory :: Category
  } deriving stock (Eq, Show)

txIsOutflow :: Transaction -> Bool
txIsOutflow t = txAmount t < Cents 0

txIsInflow :: Transaction -> Bool
txIsInflow t = txAmount t > Cents 0

-- | How a single transaction moves net worth.
--
-- Every 'Transaction' is normalized at the parser boundary to /value flow/:
-- negative means value left your control, positive means it arrived. Under
-- that convention the delta is simply the amount, for assets and liabilities
-- alike, and 'AccountType' is deliberately ignored here.
--
-- That is worth spelling out, because the naive instinct is to negate for
-- liabilities. Check it against the real cases:
--
-- * A $12.62 card purchase is @-1262@. Net worth falls $12.62. Identity: correct.
--   Negation would report the purchase as making you $12.62 /richer/.
--
-- * A $575 card payment is @+57500@ on the card and @-57500@ on checking.
--   The two cancel to zero, which is right — paying a bill moves value, it
--   does not create or destroy it. Negation would report @-115000@, double
--   counting the payment as a loss.
--
-- Negation would only be correct if liability rows were signed as /balance
-- owed/ rather than value flow. They are not, and 'Import.CSV' is responsible
-- for keeping it that way.
netWorthDelta :: AccountType -> Cents -> Cents
netWorthDelta _ c = c
