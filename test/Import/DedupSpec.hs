{-# LANGUAGE OverloadedStrings #-}

module Import.DedupSpec (tests) where

import           Data.List             (nub, sort)
import           Data.Time             (fromGregorian)
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck as QC

import           Domain.Types
import           Domain.Validation     (mkAccountName)
import           Import.CSV            (RawRow (..))
import           Import.Dedup
import           Gen

acct :: AccountName
acct = either (error "bad") id (mkAccountName "credit-card")

-- | The real collision case: four identical subway fares on one day.
firstFare :: RawRow
firstFare = RawRow (fromGregorian 2026 8 7) (Cents (-300))
              "MTA*NYCT PAYGO NEW YORK NY" 10

subwayFares :: [RawRow]
subwayFares =
  [ RawRow (fromGregorian 2026 8 7) (Cents (-300)) "MTA*NYCT PAYGO NEW YORK NY" n
  | n <- [10, 11, 12, 13] ]

tests :: TestTree
tests = testGroup "Import.Dedup"
  [ testGroup "the collision case measured on real data"
    [ testCase "four identical same-day fares get four distinct ids" $
        let ids = map snd (deriveIds acct subwayFares)
        in length (nub ids) @?= 4

    , testCase "occurrence indices are 0..n-1" $
        let occs = map snd (assignOccurrences acct subwayFares)
        in sort occs @?= [0, 1, 2, 3]
    ]

  , testGroup "idempotency"
    [ testCase "re-deriving over the same rows yields the same ids" $
        let a = map snd (deriveIds acct subwayFares)
            b = map snd (deriveIds acct subwayFares)
        in a @?= b

    , testCase "ids do not depend on row order in the file" $
        let a = sort (map snd (deriveIds acct subwayFares))
            b = sort (map snd (deriveIds acct (reverse subwayFares)))
        in a @?= b

    , QC.testProperty "deriving ids twice is stable for any input" $
        forAll (listOf genRawRow) $ \rows ->
          map snd (deriveIds acct rows) === map snd (deriveIds acct rows)

    , QC.testProperty "every row in an import gets a unique id" $
        forAll (listOf genRawRow) $ \rows ->
          let ids = map snd (deriveIds acct rows)
          in length (nub ids) === length ids

    , QC.testProperty "output preserves input line order" $
        forAll (listOf genRawRow) $ \rows ->
          let out = map (rrLine . fst) (deriveIds acct rows)
          in out === sort out
    ]

  , testGroup "key sensitivity"
    [ testCase "a changed volatile reference number does not change the id" $
        -- Same transaction, bank reformatted the trailing ref between exports.
        let r1 = RawRow (fromGregorian 2026 9 9) (Cents (-20940))
                   "KLM AIRLINE 0742143148993800-6180104 DC" 6
            r2 = r1 { rrMerchant = "KLM AIRLINE 0999999999999999-1111111 DC" }
        in map snd (deriveIds acct [r1]) @?= map snd (deriveIds acct [r2])

    , testCase "a different amount changes the id" $
        let r1 = firstFare
            r2 = r1 { rrAmount = Cents (-325) }
        in assertBool "should differ"
             (map snd (deriveIds acct [r1]) /= map snd (deriveIds acct [r2]))

    , testCase "a different date changes the id" $
        let r1 = firstFare
            r2 = r1 { rrDate = fromGregorian 2026 8 8 }
        in assertBool "should differ"
             (map snd (deriveIds acct [r1]) /= map snd (deriveIds acct [r2]))

    , testCase "a different account changes the id" $
        let other = either (error "bad") id (mkAccountName "checking")
            r = firstFare
        in assertBool "should differ"
             (map snd (deriveIds acct [r]) /= map snd (deriveIds other [r]))

    , testCase "field boundaries cannot be confused" $
        -- ("AB","C") and ("A","BC") must not hash alike.
        let r1 = RawRow (fromGregorian 2026 8 7) (Cents (-300)) "AB C" 1
            r2 = RawRow (fromGregorian 2026 8 7) (Cents (-300)) "A BC" 1
        in assertBool "should differ"
             (map snd (deriveIds acct [r1]) /= map snd (deriveIds acct [r2]))
    ]
  ]
