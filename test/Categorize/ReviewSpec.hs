{-# LANGUAGE OverloadedStrings #-}

module Categorize.ReviewSpec (tests) where

import           Data.List             (sortOn)
import qualified Data.Set              as Set
import           Data.Text             (Text)
import           Data.Time             (fromGregorian)
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck as QC

import           Categorize.Review
import           Categorize.Rules
import           Domain.Types
import           Domain.Validation     (mkAccountName)
import           Import.CSV            (RawRow (..))
import           Persistence.DB

rv :: Text -> Text -> Integer -> Category -> ReviewRow
rv tid m amt cat = ReviewRow (TransactionId tid) "cc" (fromGregorian 2026 9 1)
                     (Cents amt) m cat

rule :: Text -> Category -> Rule
rule n c = either (error "bad rule") id (mkRule n c)

tests :: TestTree
tests = testGroup "Categorize.Review"
  [ testGroup "groupQueue"
    [ testCase "groups by normalized merchant, largest group first" $
        let rows = [ rv "1" "PATH TAPP PAYGO 1" (-325) Uncategorized
                   , rv "2" "PATH TAPP PAYGO 2" (-325) Uncategorized
                   , rv "3" "TACO BOYS"         (-1262) Uncategorized ]
            qs = groupQueue rows
        in do
          map mgKey qs @?= ["PATH TAPP PAYGO", "TACO BOYS"]
          map (length . mgRows) qs @?= [2, 1]
          map mgTotal qs @?= [Cents (-650), Cents (-1262)]
    , testCase "categorized rows are not in the queue" $
        groupQueue [rv "1" "TACO BOYS" (-100) Dining] @?= []
    ]

  , testGroup "preview"
    [ testCase "counts what the rule would file, by merchant" $
        let rows = [ rv "1" "PATH TAPP PAYGO CP JERSEY CITY NJ" (-325) Uncategorized
                   , rv "2" "PATH TAPP PAYGO CP NEWARK NJ"      (-325) Uncategorized
                   , rv "3" "TACO BOYS"                        (-1262) Uncategorized ]
            p = preview [] (rule "path tapp" TravelTransit) rows
        in do
          length (pvWouldFile p) @?= 2
          map mhCount (pvMerchants p) @?= [1, 1]
    , testCase "already-categorized matches are reported, never filed" $
        let rows = [ rv "1" "TACO BOYS" (-100) Dining
                   , rv "2" "TACO BOYS" (-200) Uncategorized ]
            p = preview [] (rule "taco" Groceries) rows
        in do
          map rvId (pvWouldFile p) @?= [TransactionId "2"]
          map rvId (pvLeftAlone p) @?= [TransactionId "1"]
    , testCase "a longer existing rule wins, and the preview says so" $
        let rows = [rv "1" "TACO BOYS TEMPE" (-100) Uncategorized]
            p = preview [rule "taco boys" Dining] (rule "taco" Groceries) rows
        in do
          pvWouldFile p @?= []
          map rvId (pvShadowed p) @?= [TransactionId "1"]
    , testCase "a candidate replaces an existing rule with the same needle" $
        let rows = [rv "1" "TACO BOYS" (-100) Uncategorized]
            p = preview [rule "taco boys" Dining] (rule "taco boys" Groceries) rows
        in map rvId (pvWouldFile p) @?= [TransactionId "1"]
    ]

  , testGroup "preview agrees with saving"
    [ QC.testProperty "the rows previewed are exactly the rows decide changes" $
        forAll (listOf1 genRow) $ \rows ->
        forAll (elements needles) $ \n -> ioProperty $
          withDb ":memory:" $ \conn -> do
            initAccountBalance conn acct Asset (Cents 0) Nothing
            _ <- importRows conn (fromGregorian 2026 9 30) acct
                   [ RawRow (fromGregorian 2026 9 1) (Cents a) m i
                   | (i, (m, a)) <- zip [2 ..] rows ]
            let r = rule n Dining
            Right p <- previewPattern conn n Dining
            before <- reviewRows conn
            d <- decide conn r
            after' <- reviewRows conn
            let changed = Set.fromList
                  [ rvId x | (x, y) <- zip (sort' before) (sort' after')
                           , rvCategory x /= rvCategory y ]
            pure $ (Set.fromList (map rvId (pvWouldFile p)) === changed)
                     .&&. (dcRows d === Set.size changed)
    ]
  ]
  where
    acct = either (error "bad") id (mkAccountName "checking")
    needles = ["taco", "path tapp", "mta", "coffee"]
    sort' = sortOn rvId

genRow :: Gen (Text, Integer)
genRow = (,) <$> elements merchants <*> (choose (-50000, 50000) `suchThat` (/= 0))
  where
    merchants =
      [ "SQ *TACO BOYS TEMPE AZ", "TACO BELL #036493", "MTA*NYCT PAYGO"
      , "PATH TAPP PAYGO CP", "BLUE BOTTLE COFFEE", "CORNER GROCER" ]
