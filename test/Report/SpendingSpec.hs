{-# LANGUAGE OverloadedStrings #-}

module Report.SpendingSpec (tests) where

import           Data.List             (sort)
import           Data.Time             (fromGregorian)
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck as QC

import           Domain.Types
import           Persistence.DB        (TxRow (..))
import           Report.NetWorth
import           Report.Spending

tx :: Integer -> Category -> TxRow
tx amt cat = TxRow (TransactionId "x") "cc" (fromGregorian 2026 9 1)
               (Cents amt) "M" cat

tests :: TestTree
tests = testGroup "Report"
  [ testGroup "spendingByCategory"
    [ testCase "sums and counts per category" $
        let rows = [tx (-1000) Dining, tx (-500) Dining, tx (-2000) Groceries]
            out  = spendingByCategory rows
        in do
          lookup' Dining out    @?= Just (Cents (-1500), 2)
          lookup' Groceries out @?= Just (Cents (-2000), 1)

    , testCase "biggest outflow sorts first" $
        let rows = [tx (-1000) Dining, tx (-5000) Rent, tx 20000 Income]
        in map clCategory (spendingByCategory rows) @?= [Rent, Dining, Income]

    , testCase "an empty ledger yields no lines" $
        spendingByCategory [] @?= []

    , QC.testProperty "category totals sum to the grand total" $
        forAll (listOf genTx) $ \rows ->
          sum (map clTotal (spendingByCategory rows))
            === sum (map trAmount rows)

    , QC.testProperty "counts sum to the number of rows" $
        forAll (listOf genTx) $ \rows ->
          sum (map clCount (spendingByCategory rows)) === length rows
    ]

  , testGroup "inflow / outflow"
    [ testCase "splits by sign" $
        let rows = [tx (-1262) Dining, tx 57500 Transfer, tx (-300) Transfer]
        in do
          totalOutflow rows @?= Cents 1562    -- reported as a magnitude
          totalInflow rows  @?= Cents 57500

    , QC.testProperty "inflow minus outflow is the net total" $
        forAll (listOf genTx) $ \rows ->
          let Cents i = totalInflow rows
              Cents o = totalOutflow rows
          in Cents (i - o) === sum (map trAmount rows)
    ]

  , testGroup "monthOverMonth"
    [ testCase "reports a category that vanished this month" $
        -- The case an intersection would hide.
        let prev = [tx (-5000) Rent]
            cur  = [tx (-1000) Dining]
            out  = monthOverMonth cur prev
        in lookupDelta Rent out @?= Just (Cents 5000)

    , testCase "reports a brand-new category" $
        let out = monthOverMonth [tx (-1000) Dining] []
        in lookupDelta Dining out @?= Just (Cents (-1000))

    , testCase "no change is zero" $
        let rows = [tx (-1000) Dining]
        in lookupDelta Dining (monthOverMonth rows rows) @?= Just (Cents 0)
    ]

  , testGroup "netWorthSeries"
    [ testCase "the first point has no delta" $
        let s = netWorthSeries [(fromGregorian 2026 6 1, Cents 10000)]
        in map nwpDelta s @?= [Cents 0]

    , testCase "deltas are differences between consecutive months" $
        let s = netWorthSeries
                  [ (fromGregorian 2026 6 1, Cents 10000)
                  , (fromGregorian 2026 7 1, Cents 15000)
                  , (fromGregorian 2026 8 1, Cents 12000) ]
        in map nwpDelta s @?= [Cents 0, Cents 5000, Cents (-3000)]

    , testCase "an empty series is empty" $
        netWorthSeries [] @?= []

    , testCase "seriesChange is first-to-last, and zero for one month" $ do
        let one = netWorthSeries [(fromGregorian 2026 6 1, Cents 10000)]
            three = netWorthSeries
                      [ (fromGregorian 2026 6 1, Cents 10000)
                      , (fromGregorian 2026 7 1, Cents 15000)
                      , (fromGregorian 2026 8 1, Cents 12000) ]
        seriesChange []    @?= Cents 0
        seriesChange one   @?= Cents 0
        seriesChange three @?= Cents 2000

    , QC.testProperty "seriesChange equals the sum of all deltas" $
        forAll (listOf1 (choose (-100000, 100000))) $ \vals ->
          let pts = zip [fromGregorian 2026 m 1 | m <- [1 ..]] (map Cents vals)
              s   = netWorthSeries pts
          in seriesChange s === sum (map nwpDelta s)

    , QC.testProperty "cumulative values are recoverable from deltas" $
        forAll (listOf (choose (-100000, 100000))) $ \vals ->
          let pts = zip [fromGregorian 2026 m 1 | m <- [1 ..]] (map Cents vals)
              s   = netWorthSeries pts
          in map nwpValue s === map snd pts
    ]

  , testGroup "month parsing"
    [ testCase "round-trips" $
        (renderMonth <$> parseMonth "2026-09") @?= Just "2026-09"
    , testCase "monthOf truncates to the first" $
        monthOf (fromGregorian 2026 9 22) @?= fromGregorian 2026 9 1
    , testCase "rejects nonsense" $ parseMonth "nope" @?= Nothing
    , testCase "rejects a full date" $ parseMonth "2026-09-22" @?= Nothing
    ]
  ]
  where
    lookup' c out =
      case [ (clTotal l, clCount l) | l <- out, clCategory l == c ] of
        (x:_) -> Just x
        []    -> Nothing
    lookupDelta c out =
      case [ mdChange d | d <- out, mdCategory d == c ] of
        (x:_) -> Just x
        []    -> Nothing

genTx :: Gen TxRow
genTx = tx <$> choose (-100000, 100000) <*> elements allCategories
