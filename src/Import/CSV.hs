{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | CSV ingestion.
--
-- Two concerns live here and nowhere else:
--
-- 1. __Column layout__, which differs per institution ('ColumnSpec').
-- 2. __Sign normalization__, which differs per institution and is the more
--    dangerous of the two. Everything downstream assumes negative = value out.
--    If that assumption is established wrongly here, every report is wrong and
--    nothing else in the system can detect it.
module Import.CSV
  ( ColumnSpec (..)
  , SignConvention (..)
  , checkingSpec
  , creditCardSpec
  , RawRow (..)
  , ParsedFile (..)
  , RowError (..)
  , renderRowError
  , parseCsv
  , parseCsvWith
  ) where

import           Data.Bifunctor       (first)
import qualified Data.ByteString.Lazy as BL
import           Data.Csv             (HasHeader (..))
import qualified Data.Csv             as Csv
import           Data.Text            (Text)
import qualified Data.Text            as T
import           Data.Time            (Day, defaultTimeLocale, parseTimeM)
import qualified Data.Vector          as V

import           Domain.Types
import           Domain.Validation

-- | How an institution signs its amounts.
data SignConvention
  = ValueFlow
    -- ^ Already the domain convention: negative is money out. Your credit card
    -- export uses this — a purchase is @-12.62@, a payment is @+575.00@.
  | DebitPositive
    -- ^ Inverted: a positive number means money left the account. Common on
    -- statement-style exports. Amounts are negated on ingest.
  deriving stock (Eq, Show)

-- | Where the fields live, and how to read them.
--
-- Adding a new bank means adding a 'ColumnSpec', not a new parser. The column
-- indices are 0-based into the raw CSV record.
data ColumnSpec = ColumnSpec
  { csName           :: Text
  , csDateCol        :: Int
  , csDescriptionCol :: Int
  , csAmountCol      :: Int
  , csDateFormats    :: [String]
    -- ^ Tried in order; first success wins.
  , csSign           :: SignConvention
  , csHasHeader      :: Bool
  , csExpectedCols   :: Int
  } deriving stock (Eq, Show)

-- | Matches the real export:
-- @"DATE","DESCRIPTION","AMOUNT","CHECK #","STATUS"@ with @MM\/DD\/YYYY@ dates
-- and value-flow signs.
creditCardSpec :: ColumnSpec
creditCardSpec = ColumnSpec
  { csName           = "credit-card"
  , csDateCol        = 0
  , csDescriptionCol = 1
  , csAmountCol      = 2
  , csDateFormats    = ["%m/%d/%Y", "%Y-%m-%d"]
  , csSign           = ValueFlow
  , csHasHeader      = True
  , csExpectedCols   = 5
  }

-- | Provisional. The checking export has not been seen yet; this assumes the
-- same shape as the credit card file minus the trailing columns. Verify
-- against a real file before trusting a checking import — in particular
-- 'csSign', which cannot be inferred from the header row.
checkingSpec :: ColumnSpec
checkingSpec = ColumnSpec
  { csName           = "checking"
  , csDateCol        = 0
  , csDescriptionCol = 1
  , csAmountCol      = 2
  , csDateFormats    = ["%m/%d/%Y", "%Y-%m-%d"]
  , csSign           = ValueFlow
  , csHasHeader      = True
  , csExpectedCols   = 3
  }

-- | A structurally valid row, not yet a domain 'Transaction': it still needs
-- an id, which "Import.Dedup" assigns.
data RawRow = RawRow
  { rrDate     :: Day
  , rrAmount   :: Cents
  , rrMerchant :: Text
  , rrLine     :: Int
  } deriving stock (Eq, Show)

data RowError = RowError
  { reLine   :: Int
  , reDetail :: ValidationError
  } deriving stock (Eq, Show)

renderRowError :: RowError -> Text
renderRowError (RowError ln d) =
  "line " <> T.pack (show ln) <> ": " <> renderValidationError d

-- | Result of parsing a whole file.
--
-- Good and bad rows are returned together rather than failing the import on
-- the first bad row: one malformed line in a 339-row statement should be
-- reported, not a reason to reject the other 338.
data ParsedFile = ParsedFile
  { pfRows   :: [RawRow]
  , pfErrors :: [RowError]
  } deriving stock (Eq, Show)

parseCsv :: ColumnSpec -> BL.ByteString -> Either Text ParsedFile
parseCsv = parseCsvWith

parseCsvWith :: ColumnSpec -> BL.ByteString -> Either Text ParsedFile
parseCsvWith spec bytes = do
  records <- first (T.pack) (Csv.decode NoHeader bytes)
  let allRows = V.toList (records :: V.Vector (V.Vector Text))
      -- Line numbers are 1-based and count the header, so they match what a
      -- text editor shows when the user goes to look at a reported error.
      numbered = zip [1 :: Int ..] allRows
      body = if csHasHeader spec then drop 1 numbered else numbered
      nonEmpty = filter (not . isBlank . snd) body
      results = map (parseRow spec) nonEmpty
  pure ParsedFile
    { pfRows   = [r | Right r <- results]
    , pfErrors = [e | Left  e <- results]
    }
  where
    isBlank v = all (T.null . T.strip) (V.toList v)

parseRow :: ColumnSpec -> (Int, V.Vector Text) -> Either RowError RawRow
parseRow spec (lineNo, v) = first (RowError lineNo) $ do
  rawDate  <- col (csDateCol spec)
  rawDesc  <- col (csDescriptionCol spec)
  rawAmt   <- col (csAmountCol spec)
  day      <- maybe (Left (MalformedDate rawDate)) Right (parseDay spec rawDate)
  amount   <- first (const (MalformedAmount rawAmt)) (centsFromDecimal rawAmt)
  merchant <- mkMerchant rawDesc
  pure RawRow
    { rrDate     = day
    , rrAmount   = applySign (csSign spec) amount
    , rrMerchant = unMerchant merchant
    , rrLine     = lineNo
    }
  where
    col i = case v V.!? i of
      Just t  -> Right t
      Nothing -> Left (MalformedRow ("expected at least "
                  <> T.pack (show (i + 1)) <> " columns, got "
                  <> T.pack (show (V.length v))))

parseDay :: ColumnSpec -> Text -> Maybe Day
parseDay spec raw =
  let s = T.unpack (T.strip raw)
  in firstJust [parseTimeM True defaultTimeLocale fmt s | fmt <- csDateFormats spec]
  where
    firstJust = \case
      []             -> Nothing
      (Just x  : _)  -> Just x
      (Nothing : xs) -> firstJust xs

applySign :: SignConvention -> Cents -> Cents
applySign ValueFlow     c         = c
applySign DebitPositive (Cents n) = Cents (negate n)
