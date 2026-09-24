{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}

-- | Net worth over time.
module Report.NetWorth
  ( NetWorthPoint (..)
  , netWorthSeries
  , seriesChange
  , renderSeries
  ) where

import           Data.Text      (Text)
import qualified Data.Text      as T
import           Data.Time      (Day)

import           Domain.Types
import           Report.Spending (renderMonth)

data NetWorthPoint = NetWorthPoint
  { nwpMonth :: Day     -- ^ first day of the month
  , nwpValue :: Cents   -- ^ cumulative net worth at month end
  , nwpDelta :: Cents   -- ^ change from the previous point
  } deriving stock (Eq, Show)

-- | Turn cumulative month-end values into points carrying their delta.
--
-- The first point's delta is zero rather than its absolute value: there is no
-- previous month to have changed from, and reporting the opening position as
-- a gain would overstate the first month of every ledger.
netWorthSeries :: [(Day, Cents)] -> [NetWorthPoint]
netWorthSeries []                 = []
netWorthSeries points@((_, v0):_) =
  [ NetWorthPoint m v (v - prev)
  -- Seeded with the first month's own value, so its delta is zero. Seeding
  -- with 0 would report the entire opening position as a first-month gain.
  | ((m, v), prev) <- zip points (v0 : map snd points)
  ]

-- | Change from the first displayed month to the last.
--
-- Deliberately @last - first@, not the sum of the deltas. The first point's
-- delta is zero by construction (see 'netWorthSeries'), so summing deltas
-- would silently drop whatever happened during that first month. Measuring
-- endpoint to endpoint states exactly what it means: how much the position
-- moved across the window being shown.
--
-- Note this is the movement /between/ the displayed months, so a single-month
-- series is always zero.
seriesChange :: [NetWorthPoint] -> Cents
seriesChange []     = Cents 0
seriesChange (p:ps) = nwpValue (lastPoint p ps) - nwpValue p
  where
    lastPoint x []       = x
    lastPoint _ (y : ys) = lastPoint y ys

renderSeries :: [NetWorthPoint] -> [Text]
renderSeries = map line
  where
    line p =
      T.justifyLeft 10 ' ' (renderMonth (nwpMonth p))
        <> T.justifyRight 14 ' ' (renderCents (nwpValue p))
        <> T.justifyRight 14 ' ' (signed (nwpDelta p))
    signed c@(Cents n)
      | n > 0     = "+" <> renderCents c
      | otherwise = renderCents c
