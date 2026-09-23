{-# LANGUAGE OverloadedStrings #-}

-- | Shared generators.
module Gen where

import           Data.Text       (Text)
import           Data.Time       (Day, addDays, fromGregorian)
import           Test.QuickCheck

import           Domain.Types
import           Import.CSV      (RawRow (..))

newtype AnyCents = AnyCents Cents deriving Show

instance Arbitrary AnyCents where
  arbitrary = AnyCents . Cents <$> choose (-100000000, 100000000)

newtype NonZeroCents = NonZeroCents Cents deriving Show

instance Arbitrary NonZeroCents where
  arbitrary = NonZeroCents . Cents <$> (getNonZero <$> arbitrary `suchThat` (\(NonZero n) -> abs n < 100000000))

-- | A date at or before 'testToday', so that generated rows are valid input
-- to 'Domain.Validation.mkTransaction' rather than tripping its future-date
-- rejection.
genDay :: Gen Day
genDay = do
  offset <- choose (0, 2000)
  pure (addDays (negate offset) testToday)

-- | The fixed "today" every test validates against. Fixed rather than read
-- from the clock so the suite is deterministic and does not start failing on
-- a future date.
testToday :: Day
testToday = fromGregorian 2026 9 23

-- | Merchant strings drawn from shapes that actually appear in bank exports,
-- including the volatile digit-laden ones.
genMerchant :: Gen Text
genMerchant = elements
  [ "SQ *TACO BOYS (S MILL AVETempe AZ"
  , "MTA*NYCT PAYGO NEW YORK NY"
  , "PATH TAPP PAYGO CP JERSEY CITY NJ"
  , "KLM AIRLINE 0742143148993800-6180104 DC"
  , "ONLINE PAYMENT THANK YOU"
  , "TST* CHEBA HUT -TEMPE-UNITEMPE AZ"
  , "CHIPOTLE MEX GR ONLINE https://prod.CA"
  , "TRADER JOE'S #123 TEMPE AZ"
  ]

genRawRow :: Gen RawRow
genRawRow = RawRow
  <$> genDay
  <*> (Cents <$> choose (-50000, 50000) `suchThat` (/= 0))
  <*> genMerchant
  <*> choose (2, 400)
