{-# LANGUAGE OverloadedStrings #-}

-- | A synthetic ledger for the public demo.
--
-- Every merchant, amount, and date here is invented. The owner's real
-- statements never leave their machine, so the demo has to be convincing on
-- its own: the descriptors reproduce the shapes that make categorizing real
-- bank data hard (POS prefixes like @SQ *@ and @TST*@, volatile reference
-- numbers, marketplace order codes that split one merchant into many, several
-- identical transit fares on one day), because those shapes are what the
-- review screen exists to handle.
--
-- Dates are relative to "today" so the demo never ages into the past, and the
-- data is a pure list so a reset reproduces it exactly.
module Server.Demo
  ( seedDemo
  , resetDemo
  , demoRows
  ) where

import           Control.Monad          (forM_, void)
import           Data.Text              (Text)
import           Data.Time              (Day, addDays)
import           Database.SQLite.Simple (Connection, execute_)

import           Categorize.Rules       (mkRule)
import           Domain.Types
import           Domain.Validation      (mkAccountName)
import           Import.CSV             (RawRow (..))
import           Persistence.DB

-- | (account, days before today, cents, descriptor)
type Seed = (Text, Integer, Integer, Text)

demoRows :: [Seed]
demoRows =
  -- credit card: value flow, purchases negative
  [ ("credit-card",  2,   -575, "SQ *BLUE HERON COFFEE PORTLAND OR")
  , ("credit-card",  5,   -525, "SQ *BLUE HERON COFFEE PORTLAND OR")
  , ("credit-card",  9,   -650, "SQ *BLUE HERON COFFEE PORTLAND OR")
  , ("credit-card", 16,   -575, "SQ *BLUE HERON COFFEE PORTLAND OR")
  , ("credit-card", 23,   -475, "SQ *BLUE HERON COFFEE PORTLAND OR")
  , ("credit-card", 30,   -575, "SQ *BLUE HERON COFFEE PORTLAND OR")
  , ("credit-card", 37,   -600, "SQ *BLUE HERON COFFEE PORTLAND OR")
  , ("credit-card", 44,   -525, "SQ *BLUE HERON COFFEE PORTLAND OR")
  , ("credit-card",  3,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card",  3,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card",  4,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card",  8,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card",  8,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card",  8,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card", 12,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card", 19,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card", 19,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card", 26,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card", 33,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card", 40,   -280, "TRIMET HOP FASTPASS PORTLAND OR")
  , ("credit-card",  6,  -1284, "LYFT   *RIDE THU 11PM 8839202 CA")
  , ("credit-card", 27,  -1907, "LYFT   *RIDE SAT 1AM 1027733 CA")
  , ("credit-card", 14, -21460, "ALASKA AIR 0272148813090 SEATTLE WA")
  , ("credit-card", 13, -38215, "BKG*HOTEL AT BOOKING 4471029 AMSTERDAM NL")
  , ("credit-card",  7,  -4718, "SAFEWAY #1447 PORTLAND OR")
  , ("credit-card", 15,  -6203, "SAFEWAY #1447 PORTLAND OR")
  , ("credit-card", 22,  -3891, "SAFEWAY #1447 PORTLAND OR")
  , ("credit-card", 24,    649, "SAFEWAY #1447 PORTLAND OR")
  , ("credit-card", 36,  -5530, "SAFEWAY #1447 PORTLAND OR")
  , ("credit-card", 10,  -2766, "NEW SEASONS MARKET #12 PORTLAND OR")
  , ("credit-card", 31,  -3312, "NEW SEASONS MARKET #12 PORTLAND OR")
  , ("credit-card",  1,  -1840, "TST* FIG AND THISTLE KITCHEN PORTLAND OR")
  , ("credit-card", 18,  -4210, "TST* FIG AND THISTLE KITCHEN PORTLAND OR")
  , ("credit-card", 11,  -1127, "SQ *TACOS LA SIERRA PORTLAND OR")
  , ("credit-card", 29,   -946, "SQ *TACOS LA SIERRA PORTLAND OR")
  , ("credit-card", 20,   -893, "TACO BELL #031187 PORTLAND OR")
  , ("credit-card", 34,  -1012, "CHIPOTLE 2291 PORTLAND OR")
  , ("credit-card", 41,  -1188, "CHIPOTLE 2291 PORTLAND OR")
  , ("credit-card",  9,  -2399, "AMAZON MKTPL*2K4L19 AMZN.COM/BILL WA")
  , ("credit-card", 17,  -1499, "AMAZON MKTPL*7Q2P01 AMZN.COM/BILL WA")
  , ("credit-card", 28,  -3645, "AMAZON MKTPL*RB8W33 AMZN.COM/BILL WA")
  , ("credit-card", 21,  -1199, "SPOTIFY P1A2B3C4D STOCKHOLM SE")
  , ("credit-card", 21,  -1549, "NETFLIX.COM LOS GATOS CA")
  , ("credit-card", 25,   -299, "APPLE.COM/BILL CUPERTINO CA")
  , ("credit-card", 39,   -312, "INTEREST CHARGE ON PURCHASES")
  , ("credit-card", 12,  40000, "ONLINE PAYMENT THANK YOU")
  , ("credit-card", 35,  65000, "ONLINE PAYMENT THANK YOU")
  -- checking: value flow, withdrawals negative
  , ("checking",  4, 164022, "NORTHWIND LABS PAYROLL PPD 000451")
  , ("checking", 18, 164022, "NORTHWIND LABS PAYROLL PPD 000451")
  , ("checking", 32, 164022, "NORTHWIND LABS PAYROLL PPD 000451")
  , ("checking",  2,-118000, "PINE STREET APTS RENT ACH 0925")
  , ("checking", 32,-118000, "PINE STREET APTS RENT ACH 0825")
  , ("checking", 16,  -8412, "CITY UTILITIES WEBPAY 0919")
  , ("checking", 12, -40000, "ONLINE TRANSFER TO CREDIT CARD XXXX4412")
  , ("checking", 35, -65000, "ONLINE TRANSFER TO CREDIT CARD XXXX4412")
  , ("checking",  6, -30000, "ONLINE TRANSFER TO SAVINGS REF #IB0Q7K")
  , ("checking", 26,  -6000, "ATM WITHDRAWAL 00482 SE HAWTHORNE BLVD")
  , ("checking", 30,   -500, "MONTHLY SERVICE FEE")
  , ("checking", 11,   2350, "VENMO CASHOUT 7741")
  ]

-- | Load the synthetic ledger into an empty, migrated database.
--
-- Two rules exist up front, so some rows arrive already filed. That keeps the
-- preview's "already filed, left alone" state reachable in the demo instead of
-- only in theory.
seedDemo :: Connection -> Day -> IO ()
seedDemo conn today = do
  let acct n = either (error "demo account") id (mkAccountName n)
      oldest = maximum [ d | (_, d, _, _) <- demoRows ]
  initAccountBalance conn (acct "checking") Asset (Cents 241830)
    (Just (addDays (negate (oldest + 1)) today))
  initAccountBalance conn (acct "credit-card") Liability (Cents 0) Nothing
  forM_ ["checking", "credit-card"] $ \name ->
    void $ importRows conn today (acct name)
      [ RawRow (addDays (negate ago) today) (Cents amt) desc i
      | (i, (a, ago, amt, desc)) <- zip [2 ..] demoRows, a == name ]
  forM_ [("PAYROLL", Income), ("NETFLIX", Monthly)] $ \(n, c) ->
    either (const (pure ())) (insertRule conn) (mkRule n c)
  void (applyRules conn)

-- | Wipe and reseed, so a public demo can be returned to its starting state.
resetDemo :: Connection -> Day -> IO ()
resetDemo conn today = do
  mapM_ (execute_ conn)
    [ "DELETE FROM decision_rows", "DELETE FROM decisions", "DELETE FROM rules"
    , "DELETE FROM transactions", "DELETE FROM accounts" ]
  seedDemo conn today
