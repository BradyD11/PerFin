{-# LANGUAGE OverloadedStrings #-}

module Persistence.DBSpec (tests) where

import           Data.Time         (Day, fromGregorian)
import           Database.SQLite.Simple (Connection)
import           System.IO.Temp    (withSystemTempDirectory)
import           System.FilePath   ((</>))
import           Test.Tasty
import           Test.Tasty.HUnit

import           Domain.Types
import           Domain.Validation (mkAccountName)
import           Import.CSV        (RawRow (..))
import           Persistence.DB

today :: Day
today = fromGregorian 2026 9 23

checking, card :: AccountName
checking = either (error "bad") id (mkAccountName "checking")
card     = either (error "bad") id (mkAccountName "credit-card")

cardRows :: [RawRow]
cardRows =
  [ RawRow (fromGregorian 2026 9 12) (Cents (-1262)) "SQ *TACO BOYS" 2
  , RawRow (fromGregorian 2026 9 10) (Cents 57500)   "ONLINE PAYMENT THANK YOU" 3
  , RawRow (fromGregorian 2026 8  7) (Cents (-300))  "MTA*NYCT PAYGO NEW YORK NY" 4
  , RawRow (fromGregorian 2026 8  7) (Cents (-300))  "MTA*NYCT PAYGO NEW YORK NY" 5
  ]

withTestDb :: (Connection -> IO a) -> IO a
withTestDb action =
  withSystemTempDirectory "ledger-test" $ \dir ->
    withDb (dir </> "test.db") action

tests :: TestTree
tests = testGroup "Persistence.DB"
  [ testCase "migrate is idempotent" $
      withTestDb $ \conn -> do
        migrate conn
        migrate conn
        accts <- listAccounts conn
        accts @?= []

  , testCase "import into an unknown account fails loudly" $
      withTestDb $ \conn -> do
        r <- importRows conn today card cardRows
        case r of
          Left _  -> pure ()
          Right _ -> assertFailure "should have rejected unknown account"

  , testCase "a first import inserts every row" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0)
        r <- importRows conn today card cardRows
        case r of
          Left e  -> assertFailure (show e)
          Right s -> do
            isInserted s @?= 4
            isSkipped s  @?= 0

  , testCase "re-importing the same statement is a no-op" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0)
        _ <- importRows conn today card cardRows
        r <- importRows conn today card cardRows
        case r of
          Left e  -> assertFailure (show e)
          Right s -> do
            isInserted s @?= 0
            isSkipped s  @?= 4

  , testCase "both identical subway fares survive the round trip" $
      -- The regression test for the dedup collision: a key without an
      -- occurrence index would store only one of these.
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0)
        _ <- importRows conn today card cardRows
        txs <- allTransactions conn
        length txs @?= 4

  , testCase "an overlapping later statement adds only the new rows" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0)
        _ <- importRows conn today card (take 2 cardRows)
        r <- importRows conn today card cardRows
        case r of
          Left e  -> assertFailure (show e)
          Right s -> do
            isInserted s @?= 2
            isSkipped s  @?= 2

  , testCase "balance is opening plus the sum of transactions" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0)
        _ <- importRows conn today card cardRows
        b <- accountBalance conn card
        -- -12.62 + 575.00 - 3.00 - 3.00 = 556.38
        b @?= Cents 55638

  , testCase "opening balance is respected" $
      withTestDb $ \conn -> do
        initAccountBalance conn checking Asset (Cents 123456)
        b <- accountBalance conn checking
        b @?= Cents 123456

  , testCase "an import never resets a deliberately set opening balance" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents (-50000))
        _ <- importRows conn today card cardRows
        Just a <- lookupAccount conn card
        accOpening a @?= Cents (-50000)

  , testCase "net worth combines an asset and a liability correctly" $
      withTestDb $ \conn -> do
        initAccountBalance conn checking Asset     (Cents 200000)  -- $2000 held
        initAccountBalance conn card     Liability (Cents (-50000)) -- $500 owed
        nw <- netWorth conn
        nw @?= Cents 150000

  , testCase "a card payment leaves net worth unchanged" $
      withTestDb $ \conn -> do
        initAccountBalance conn checking Asset     (Cents 200000)
        initAccountBalance conn card     Liability (Cents (-50000))
        nwBefore <- netWorth conn
        _ <- importRows conn today card
               [RawRow (fromGregorian 2026 9 10) (Cents 50000) "ONLINE PAYMENT" 2]
        _ <- importRows conn today checking
               [RawRow (fromGregorian 2026 9 10) (Cents (-50000)) "CC PAYMENT" 2]
        nwAfter <- netWorth conn
        nwAfter @?= nwBefore

  , testCase "a future-dated row is rejected at the domain boundary" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0)
        r <- importRows conn today card
               [RawRow (fromGregorian 2027 1 1) (Cents (-100)) "TIME TRAVEL" 2]
        case r of
          Left _  -> pure ()
          Right _ -> assertFailure "should have rejected a future date"
  ]
