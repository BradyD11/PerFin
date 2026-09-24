{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}

-- | Spending breakdowns by category, and month-over-month deltas.
--
-- The aggregation functions are pure over a list of rows; the SQL that
-- produces those rows lives in "Persistence.DB". That split is what lets the
-- interesting arithmetic be property-tested without a database.
module Report.Spending
  ( CategoryLine (..)
  , spendingByCategory
  , MonthDelta (..)
  , monthOverMonth
  , monthOf
  , renderMonth
  , parseMonth
  , totalOutflow
  , totalInflow
  ) where

import           Data.List     (sortOn)
import qualified Data.Map.Strict as M
import           Data.Ord      (Down (..))
import           Data.Text     (Text)
import qualified Data.Text     as T
import           Data.Time     (Day, defaultTimeLocale, formatTime,
                                fromGregorian, parseTimeM, toGregorian)

import           Domain.Types
import           Persistence.DB (TxRow (..))

data CategoryLine = CategoryLine
  { clCategory :: Category
  , clTotal    :: Cents   -- ^ signed; outflows are negative
  , clCount    :: Int
  } deriving stock (Eq, Show)

-- | Totals per category, largest outflow first.
--
-- Sorting by the raw signed total puts the biggest spending at the top
-- (most negative) and income at the bottom, which is the order you want when
-- the question is "where did the money go".
spendingByCategory :: [TxRow] -> [CategoryLine]
spendingByCategory txs =
  let tally = M.fromListWith merge
        [ (trCategory t, (trAmount t, 1 :: Int)) | t <- txs ]
      merge (a1, c1) (a2, c2) = (a1 + a2, c1 + c2)
  in sortOn (\cl -> (clTotal cl, renderCategory (clCategory cl)))
       [ CategoryLine cat total n | (cat, (total, n)) <- M.toList tally ]

-- | Only the money that left: outflows summed as a positive magnitude.
totalOutflow :: [TxRow] -> Cents
totalOutflow txs = negate' (sum [trAmount t | t <- txs, trAmount t < Cents 0])
  where negate' (Cents n) = Cents (negate n)

totalInflow :: [TxRow] -> Cents
totalInflow txs = sum [trAmount t | t <- txs, trAmount t > Cents 0]

data MonthDelta = MonthDelta
  { mdCategory :: Category
  , mdCurrent  :: Cents
  , mdPrevious :: Cents
  , mdChange   :: Cents   -- ^ current - previous
  } deriving stock (Eq, Show)

-- | Compare two months category by category.
--
-- The union of both months' categories is used, not just the current month's:
-- a category you spent on last month and not at all this month is exactly the
-- change worth seeing, and intersecting would hide it.
monthOverMonth :: [TxRow] -> [TxRow] -> [MonthDelta]
monthOverMonth current previous =
  let cur  = M.fromListWith (+) [(trCategory t, trAmount t) | t <- current]
      prev = M.fromListWith (+) [(trCategory t, trAmount t) | t <- previous]
      cats = M.keys (M.union cur prev)
  in sortOn (\md -> (Down (absCents (mdChange md)), renderCategory (mdCategory md)))
       [ MonthDelta cat c p (c - p)
       | cat <- cats
       , let c = M.findWithDefault (Cents 0) cat cur
       , let p = M.findWithDefault (Cents 0) cat prev
       ]
  where absCents (Cents n) = abs n

-- | First day of the month containing a date.
monthOf :: Day -> Day
monthOf d = let (y, m, _) = toGregorian d in fromGregorian y m 1

renderMonth :: Day -> Text
renderMonth = T.pack . formatTime defaultTimeLocale "%Y-%m"

-- | Parse a @YYYY-MM@ string into the first day of that month.
parseMonth :: Text -> Maybe Day
parseMonth = parseTimeM True defaultTimeLocale "%Y-%m" . T.unpack . T.strip
