{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}

-- | The review queue and rule previews, as pure functions over rows.
--
-- The web review screen shows a rule's reach before it is saved. That preview
-- must be computed by exactly the matching logic that saving uses, or the
-- screen would promise one set of rows and the database would change another.
-- So both 'preview' here and 'Persistence.DB.decide' go through
-- 'Categorize.Rules.firstMatch'; nothing re-implements matching.
module Categorize.Review
  ( ReviewRow (..)
  , MerchantGroup (..)
  , groupQueue
  , Preview (..)
  , MerchantHit (..)
  , preview
  ) where

import           Data.List         (sortOn)
import qualified Data.Map.Strict   as M
import           Data.Ord          (Down (..))
import           Data.Text         (Text)
import           Data.Time         (Day)

import           Categorize.Rules
import           Domain.Types
import           Domain.Validation (normalizeMerchant)

-- | One transaction as the review screen needs it.
data ReviewRow = ReviewRow
  { rvId       :: TransactionId
  , rvAccount  :: Text
  , rvDay      :: Day
  , rvAmount   :: Cents
  , rvMerchant :: Text        -- ^ raw descriptor, as the bank printed it
  , rvCategory :: Category
  } deriving stock (Eq, Show)

-- | Uncategorized rows sharing a normalized merchant: one decision's worth.
data MerchantGroup = MerchantGroup
  { mgKey   :: Text            -- ^ normalized merchant
  , mgRows  :: [ReviewRow]     -- ^ newest first
  , mgTotal :: Cents
  } deriving stock (Eq, Show)

-- | Group uncategorized rows into the review queue.
--
-- Largest groups first, because one decision there files the most rows; ties
-- break on the key so the order is stable between page loads.
groupQueue :: [ReviewRow] -> [MerchantGroup]
groupQueue rows =
  let uncategorized = filter ((== Uncategorized) . rvCategory) rows
      grouped = M.fromListWith (++)
        [ (normalizeMerchant (rvMerchant r), [r]) | r <- uncategorized ]
      build (k, rs) =
        let newest = sortOn (\r -> (Down (rvDay r), rvId r)) rs
        in MerchantGroup k newest (sum (map rvAmount rs))
  in sortOn (\g -> (Down (length (mgRows g)), mgKey g)) (map build (M.toList grouped))

-- | A merchant a pattern reaches, with how many of its rows.
data MerchantHit = MerchantHit
  { mhKey   :: Text
  , mhCount :: Int
  , mhTotal :: Cents
  } deriving stock (Eq, Show)

-- | What saving a rule would do, before it is saved.
data Preview = Preview
  { pvRule        :: Rule
  , pvWouldFile   :: [ReviewRow]    -- ^ uncategorized rows the rule would win
  , pvMerchants   :: [MerchantHit]  -- ^ those rows by merchant, largest first
  , pvLeftAlone   :: [ReviewRow]    -- ^ already-categorized rows it matches;
                                    --   saving never touches them
  , pvShadowed    :: [ReviewRow]    -- ^ uncategorized rows it matches but a
                                    --   longer existing rule wins
  } deriving stock (Eq, Show)

-- | Preview a candidate rule against the current rules and every row.
--
-- A candidate with the same needle as an existing rule replaces it, exactly
-- as saving does (rules are upserted by needle).
preview :: [Rule] -> Rule -> [ReviewRow] -> Preview
preview existing candidate rows =
  let rules = candidate : filter ((/= ruleNeedle candidate) . ruleNeedle) existing
      matches r = matchRule candidate (rvMerchant r)
      (open, filed) = foldr split ([], []) (filter matches rows)
      split r (o, f)
        | rvCategory r == Uncategorized = (r : o, f)
        | otherwise                     = (o, r : f)
      wins r = firstMatch rules (rvMerchant r) == Just candidate
      wouldFile = filter wins open
      shadowed  = filter (not . wins) open
      byMerchant = M.fromListWith merge
        [ (normalizeMerchant (rvMerchant r), (1 :: Int, rvAmount r)) | r <- wouldFile ]
      merge (a, x) (b, y) = (a + b, x + y)
      hits = sortOn (\h -> (Down (mhCount h), mhKey h))
        [ MerchantHit k n t | (k, (n, t)) <- M.toList byMerchant ]
  in Preview candidate wouldFile hits filed shadowed
