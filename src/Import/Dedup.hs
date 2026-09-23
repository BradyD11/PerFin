{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Deterministic transaction identity, and therefore idempotent imports.
--
-- == The design constraint, measured on real data
--
-- A key of (date, amount, account, merchant) is not injective over an actual
-- statement. In the sample credit card export, 67 of 339 rows collide under
-- that key — mostly transit fares, where several identical charges post on the
-- same day:
--
-- > 4x  08/07/2026  -3.00  MTA*NYCT PAYGO NEW YORK NY
-- > 2x  08/06/2026  -3.25  PATH TAPP PAYGO CP JERSEY CITY NJ
--
-- These are distinct transactions. A key that cannot tell them apart makes the
-- importer drop 20% of the file and under-report spending — a silent failure,
-- which is the worst kind.
--
-- So the key includes an __occurrence index__: the 0-based position of this row
-- among the rows in the same import that share its other key fields. Four
-- identical subway fares get indices 0..3 and four distinct ids.
--
-- == Why this stays idempotent
--
-- The index is assigned by a deterministic scan over rows sorted by a total
-- order. Re-importing the same statement reproduces the same order, hence the
-- same indices, hence the same ids — so every row is recognized as already
-- present. A later statement that overlaps the first reproduces the indices for
-- the overlapping days too, because the sort is over the row content, not over
-- file position.
--
-- == The residual limitation
--
-- If a /partial/ statement is imported (say, a mid-day export that contains 2
-- of the day's 4 subway fares) and later a complete one, the 2 already-imported
-- rows match indices 0 and 1, and rows 2 and 3 are correctly seen as new. That
-- is the desired behavior. The failure case is the reverse: if a bank
-- /removes/ a transaction from a later export (a reversed pending charge), the
-- indices shift and the tail rows look new. Statements are append-only in
-- practice, so this is accepted rather than solved; 'Persistence.DB' stores the
-- import batch so it can be audited if it ever bites.
module Import.Dedup
  ( DedupKey (..)
  , dedupKey
  , deriveIds
  , assignOccurrences
  , merchantPrefixLen
  ) where

import qualified Crypto.Hash.SHA256     as SHA256
import qualified Data.ByteString.Base16 as B16
import           Data.List              (sortOn)
import qualified Data.Map.Strict        as M
import           Data.Text              (Text)
import qualified Data.Text              as T
import qualified Data.Text.Encoding     as TE
import           Data.Time              (Day)

import           Domain.Types
import           Domain.Validation      (normalizeMerchant)
import           Import.CSV             (RawRow (..))

-- | How much of the normalized merchant string feeds the key.
--
-- Truncation defends against the tail of the description changing between
-- exports (appended reference numbers, varying trailing whitespace, a store
-- name gaining a city suffix). 20 characters keeps enough to distinguish
-- genuinely different merchants while cutting the volatile tail.
merchantPrefixLen :: Int
merchantPrefixLen = 20

data DedupKey = DedupKey
  { dkAccount    :: Text
  , dkDate       :: Day
  , dkAmount     :: Cents
  , dkMerchant   :: Text   -- ^ normalized, truncated
  , dkOccurrence :: Int
  } deriving stock (Eq, Ord, Show)

dedupKey :: AccountName -> RawRow -> Int -> DedupKey
dedupKey account row occ = DedupKey
  { dkAccount    = unAccountName account
  , dkDate       = rrDate row
  , dkAmount     = rrAmount row
  , dkMerchant   = T.take merchantPrefixLen (normalizeMerchant (rrMerchant row))
  , dkOccurrence = occ
  }

-- | Hash a key into a 'TransactionId'.
--
-- Fields are joined with a delimiter that cannot occur in any of them, so
-- @("AB","C")@ and @("A","BC")@ cannot hash alike.
hashKey :: DedupKey -> TransactionId
hashKey k =
  TransactionId
    . TE.decodeUtf8
    . B16.encode
    . SHA256.hash
    . TE.encodeUtf8
    . T.intercalate "\US"
    $ [ dkAccount k
      , T.pack (show (dkDate k))
      , renderCents (dkAmount k)
      , dkMerchant k
      , T.pack (show (dkOccurrence k))
      ]

-- | Assign occurrence indices deterministically.
--
-- Rows are grouped by everything /except/ occurrence, then each group is
-- ordered by a total order on the row content and numbered from 0. The sort is
-- on content rather than file position so that the same transaction gets the
-- same index no matter where it appears in a given export.
assignOccurrences :: AccountName -> [RawRow] -> [(RawRow, Int)]
assignOccurrences account rows =
  let keyed = [ (dedupKey account r 0, r) | r <- rows ]
      -- Stable total order within a collision group: the untruncated merchant
      -- then the source line, so ties are still broken deterministically.
      ordered = sortOn (\(k, r) -> (k, rrMerchant r, rrLine r)) keyed
      go _    []            = []
      go seen ((k, r) : xs) =
        let n = M.findWithDefault 0 k seen
        in (r, n) : go (M.insert k (n + 1) seen) xs
  in go M.empty ordered

-- | Full pipeline: raw rows in, ids assigned, back in the original file order.
deriveIds :: AccountName -> [RawRow] -> [(RawRow, TransactionId)]
deriveIds account rows =
  let withOcc = assignOccurrences account rows
      ids = [ (r, hashKey (dedupKey account r occ)) | (r, occ) <- withOcc ]
  in sortOn (rrLine . fst) ids
