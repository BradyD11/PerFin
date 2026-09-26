{-# LANGUAGE OverloadedStrings #-}

module Persistence.DBSpec (tests) where

import qualified Data.Text         as T
import           Data.Text         (Text)
import           Data.Time         (Day, addDays, diffDays, fromGregorian)
import           Database.SQLite.Simple (Connection, close, execute_, open)
import           System.IO.Temp    (withSystemTempDirectory)
import           System.FilePath   ((</>))
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck as QC

import           Domain.Types
import           Domain.Validation (mkAccountName)
import           Import.CSV        (RawRow (..))
import           Persistence.DB

today :: Day
today = fromGregorian 2026 9 30

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
        initAccountBalance conn card Liability (Cents 0) Nothing
        r <- importRows conn today card cardRows
        case r of
          Left e  -> assertFailure (show e)
          Right s -> do
            isInserted s @?= 4
            isSkipped s  @?= 0

  , testCase "re-importing the same statement is a no-op" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0) Nothing
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
        initAccountBalance conn card Liability (Cents 0) Nothing
        _ <- importRows conn today card cardRows
        txs <- allTransactions conn
        length txs @?= 4

  , testCase "an overlapping later statement adds only the new rows" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0) Nothing
        _ <- importRows conn today card (take 2 cardRows)
        r <- importRows conn today card cardRows
        case r of
          Left e  -> assertFailure (show e)
          Right s -> do
            isInserted s @?= 2
            isSkipped s  @?= 2

  , testCase "balance is opening plus the sum of transactions" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0) Nothing
        _ <- importRows conn today card cardRows
        b <- accountBalance conn card
        -- -12.62 + 575.00 - 3.00 - 3.00 = 556.38
        b @?= Cents 55638

  , testCase "opening balance is respected" $
      withTestDb $ \conn -> do
        initAccountBalance conn checking Asset (Cents 123456) Nothing
        b <- accountBalance conn checking
        b @?= Cents 123456

  , testCase "an import never resets a deliberately set opening balance" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents (-50000)) Nothing
        _ <- importRows conn today card cardRows
        Just a <- lookupAccount conn card
        accOpening a @?= Cents (-50000)

  , testCase "net worth combines an asset and a liability correctly" $
      withTestDb $ \conn -> do
        initAccountBalance conn checking Asset     (Cents 200000) Nothing   -- $2000 held
        initAccountBalance conn card     Liability (Cents (-50000)) Nothing -- $500 owed
        nw <- netWorth conn
        nw @?= Cents 150000

  , testCase "a card payment leaves net worth unchanged" $
      withTestDb $ \conn -> do
        initAccountBalance conn checking Asset     (Cents 200000) Nothing
        initAccountBalance conn card     Liability (Cents (-50000)) Nothing
        nwBefore <- netWorth conn
        _ <- importRows conn today card
               [RawRow (fromGregorian 2026 9 10) (Cents 50000) "ONLINE PAYMENT" 2]
        _ <- importRows conn today checking
               [RawRow (fromGregorian 2026 9 10) (Cents (-50000)) "CC PAYMENT" 2]
        nwAfter <- netWorth conn
        nwAfter @?= nwBefore


  , testGroup "overlapping statements (drawn from two real exports)"
    [ testCase "the overlap is imported exactly once, either order" $ do
        -- June 17-20 appears in both of the real credit card exports, with
        -- identical rows -- including a duplicate PATH fare on 06/18, which
        -- is the collision case the occurrence index exists for.
        -- laterExport contains all 5 overlap rows plus 2 of its own, so the
        -- union is 7 -- not 12, which is what double-counting would give.
        forwards  <- runImports [earlierExport, laterExport]
        backwards <- runImports [laterExport, earlierExport]
        forwards  @?= 7
        backwards @?= 7

    , testCase "import order does not change the stored sum" $ do
        a <- runImportsSum [earlierExport, laterExport]
        b <- runImportsSum [laterExport, earlierExport]
        a @?= b

    , testCase "both duplicate PATH fares survive the overlap" $
        withTestDb $ \conn -> do
          initAccountBalance conn card Liability (Cents 0) Nothing
          _ <- importRows conn today card earlierExport
          _ <- importRows conn today card laterExport
          txs <- allTransactions conn
          let paths = [t | t@(_, _, _, m, _) <- txs, "PATH" `T.isPrefixOf` m]
          length paths @?= 2
    ]

  , testGroup "dated balance anchors"
    [ testCase "balances derive forward and backward from the anchor" $
        withTestDb $ \conn -> do
          initAccountBalance conn checking Asset (Cents 10000) (Just (d 8 25))
          importOk conn checking
                 [ row (d 8 26) 5000    "DEPOSIT" 2
                 , row (d 8 27) (-2000) "DEBIT"   3 ]
          at25 <- accountBalanceAt conn checking (Just (d 8 25))
          at26 <- accountBalanceAt conn checking (Just (d 8 26))
          now  <- accountBalance conn checking
          at25 @?= Cents 10000
          at26 @?= Cents 15000
          now  @?= Cents 13000

    , testCase "importing older history later does not change today's balance" $
        -- The bug an undated opening balance has: the anchor already reflects
        -- July, so adding July's rows on top would count them twice.
        withTestDb $ \conn -> do
          initAccountBalance conn checking Asset (Cents 10000) (Just (d 8 25))
          importOk conn checking [row (d 8 26) 5000 "DEPOSIT" 2]
          before <- accountBalance conn checking
          importOk conn checking [row (d 7 15) (-3000) "OLD DEBIT" 2]
          afterOld <- accountBalance conn checking
          afterOld @?= before
          -- ...and the older history makes earlier balances knowable.
          pre <- accountBalanceAt conn checking (Just (d 7 14))
          pre @?= Cents 13000

    , QC.testProperty "rows before the anchor never move balances after it" $
        forAll (listOf1 genDated) $ \older ->
        forAll (listOf1 genDated) $ \newer -> ioProperty $
          withDb ":memory:" $ \conn -> do
            let anchor = d 8 25
                olderRows = [ r { rrDate = addDays (negate k) anchor } | (k, r) <- older ]
                -- Kept between the anchor and 'today': a future date would be
                -- rejected, and a rejected import proves nothing.
                span' = diffDays today anchor
                newerRows = [ r { rrDate = addDays (1 + k `mod` span') anchor }
                            | (k, r) <- newer ]
            initAccountBalance conn checking Asset (Cents 10000) (Just anchor)
            importOk conn checking newerRows
            a <- accountBalance conn checking
            importOk conn checking olderRows
            b <- accountBalance conn checking
            pure (a === b)

    , testCase "an undated anchor keeps the original meaning" $
        withTestDb $ \conn -> do
          initAccountBalance conn checking Asset (Cents 10000) Nothing
          importOk conn checking [row (d 8 26) 5000 "DEPOSIT" 2]
          b <- accountBalance conn checking
          b @?= Cents 15000

    , testCase "the last month of the series equals current net worth" $
        withTestDb $ \conn -> do
          initAccountBalance conn checking Asset (Cents 10000) (Just (d 8 25))
          initAccountBalance conn card Liability (Cents 0) Nothing
          importOk conn checking [row (d 9 1) (-2500) "RENT" 2]
          importOk conn card [row (d 7 3) (-1200) "LUNCH" 2]
          series <- monthlyNetWorth conn
          nw <- netWorth conn
          fmap snd (lastMay series) @?= Just nw
    ]

  , testGroup "reconcile"
    [ testCase "a correct import reconciles to the statement" $
        withTestDb $ \conn -> do
          initAccountBalance conn checking Asset (Cents 100000) (Just (d 8 25))
          importOk conn checking statementRows
          r <- reconcileAccount conn checking (d 9 24) (Cents 125000)
          rcComputed r @?= rcExpected r

    , testCase "an inverted sign convention is caught" $
        -- What importing with the wrong SignConvention would store.
        withTestDb $ \conn -> do
          initAccountBalance conn checking Asset (Cents 100000) (Just (d 8 25))
          importOk conn checking
                 [ r { rrAmount = negate (rrAmount r) } | r <- statementRows ]
          r <- reconcileAccount conn checking (d 9 24) (Cents 125000)
          assertBool "should not reconcile" (rcComputed r /= rcExpected r)

    , testCase "a dropped row is caught" $
        withTestDb $ \conn -> do
          initAccountBalance conn checking Asset (Cents 100000) (Just (d 8 25))
          importOk conn checking (drop 1 statementRows)
          r <- reconcileAccount conn checking (d 9 24) (Cents 125000)
          assertBool "should not reconcile" (rcComputed r /= rcExpected r)

    , testCase "reconciling an earlier date checks the history before the anchor" $
        withTestDb $ \conn -> do
          -- Anchor on the ending balance, verify the beginning one.
          initAccountBalance conn checking Asset (Cents 125000) (Just (d 9 24))
          importOk conn checking statementRows
          r <- reconcileAccount conn checking (d 8 25) (Cents 100000)
          rcComputed r @?= rcExpected r
    ]

  , testCase "migrating a pre-anchor database keeps its accounts" $
      withSystemTempDirectory "ledger-test" $ \dir -> do
        let path = dir </> "old.db"
        -- The schema as it was before balance_as_of existed.
        old <- open path
        execute_ old "CREATE TABLE accounts (name TEXT PRIMARY KEY, \
                     \type TEXT NOT NULL, opening_balance INTEGER NOT NULL DEFAULT 0)"
        execute_ old "INSERT INTO accounts VALUES ('checking', 'asset', 12345)"
        close old
        withDb path $ \conn -> do
          a <- lookupAccount conn checking
          fmap accOpening a @?= Just (Cents 12345)
          fmap accAsOf a    @?= Just Nothing

  , testCase "a future-dated row is rejected at the domain boundary" $
      withTestDb $ \conn -> do
        initAccountBalance conn card Liability (Cents 0) Nothing
        r <- importRows conn today card
               [RawRow (fromGregorian 2027 1 1) (Cents (-100)) "TIME TRAVEL" 2]
        case r of
          Left _  -> pure ()
          Right _ -> assertFailure "should have rejected a future date"
  ]

-- | The June 17-20 window, verbatim from the earlier real export.
earlierExport :: [RawRow]
earlierExport =
  [ RawRow (fromGregorian 2026 6 17) (Cents (-5306)) "JUBILEE MARKET PLACE NEW YORK NY" 2
  , RawRow (fromGregorian 2026 6 17) (Cents  (-651)) "OKI MART & DELI JAPANESE NEW YORK NY" 3
  , RawRow (fromGregorian 2026 6 18) (Cents  (-325)) "PATH TAPP PAYGO CP JERSEY CITY NJ" 4
  , RawRow (fromGregorian 2026 6 18) (Cents  (-325)) "PATH TAPP PAYGO CP JERSEY CITY NJ" 5
  , RawRow (fromGregorian 2026 6 20) (Cents  (-543)) "LUCKIN COFFEE LKCOFFEE.COM NJ" 6
  ]

-- | The same window as it appears in the later export, plus rows only it has.
laterExport :: [RawRow]
laterExport = earlierExport ++
  [ RawRow (fromGregorian 2026 7 13) (Cents  50000) "ONLINE PAYMENT THANK YOU" 7
  , RawRow (fromGregorian 2026 9 12) (Cents  (-1262)) "SQ *TACO BOYS (S MILL AVETempe AZ" 8
  ]

runImports :: [[RawRow]] -> IO Int
runImports batches = withTestDb $ \conn -> do
  initAccountBalance conn card Liability (Cents 0) Nothing
  mapM_ (importRows conn today card) batches
  length <$> allTransactions conn

runImportsSum :: [[RawRow]] -> IO Cents
runImportsSum batches = withTestDb $ \conn -> do
  initAccountBalance conn card Liability (Cents 0) Nothing
  mapM_ (importRows conn today card) batches
  accountBalance conn card

d :: Int -> Int -> Day
d = fromGregorian 2026

row :: Day -> Integer -> Text -> Int -> RawRow
row day amt m ln = RawRow day (Cents amt) m ln

-- | A synthetic statement period: 1,000.00 at the end of 8/25, net +250.00,
-- 1,250.00 at the end of 9/24.
statementRows :: [RawRow]
statementRows =
  [ row (d 8 31) 300000    "PAYROLL"             2
  , row (d 9 8)  (-150000) "BROKERAGE TRANSFER"  3
  , row (d 9 11) (-57500)  "CREDIT CARD PAYMENT" 4
  , row (d 9 24) (-67500)  "OTHER WITHDRAWALS"   5
  ]

genDated :: Gen (Integer, RawRow)
genDated = do
  k   <- choose (0, 300)
  amt <- choose (-50000, 50000) `suchThat` (/= 0)
  m   <- elements ["A", "B", "C"]
  ln  <- choose (2, 500)
  pure (k, RawRow (fromGregorian 2026 1 1) (Cents amt) m ln)

lastMay :: [a] -> Maybe a
lastMay = foldl (\_ x -> Just x) Nothing

-- | Import, failing the test if validation rejects anything. A reconcile test
-- whose import silently failed would compare against an untouched balance and
-- could pass for the wrong reason.
importOk :: Connection -> AccountName -> [RawRow] -> IO ()
importOk conn acct rows = do
  r <- importRows conn today acct rows
  case r of
    Left errs -> assertFailure ("import rejected: " <> show errs)
    Right _   -> pure ()
