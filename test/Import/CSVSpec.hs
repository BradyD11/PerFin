{-# LANGUAGE OverloadedStrings #-}

module Import.CSVSpec (tests) where

import qualified Data.ByteString.Lazy.Char8 as BL8
import           Data.Time                  (fromGregorian)
import           Test.Tasty
import           Test.Tasty.HUnit

import           Domain.Types
import           Import.CSV

-- | Verbatim rows from the real export, including the empty unquoted CHECK #
-- column that naive splitting gets wrong.
sample :: BL8.ByteString
sample = BL8.unlines
  [ "\"DATE\",\"DESCRIPTION\",\"AMOUNT\",\"CHECK #\",\"STATUS\""
  , "\"09/12/2026\",\"SQ *TACO BOYS (S MILL AVETempe AZ\",\"-12.62\",,\"Posted\""
  , "\"09/10/2026\",\"ONLINE PAYMENT THANK YOU\",\"575.00\",,\"Posted\""
  , "\"09/09/2026\",\"KLM AIRLINE 0742143148993800-6180104 DC\",\"-209.40\",,\"Posted\""
  ]

tests :: TestTree
tests = testGroup "Import.CSV"
  [ testCase "parses the real credit card format" $
      case parseCsv creditCardSpec sample of
        Left e -> assertFailure (show e)
        Right pf -> do
          length (pfRows pf) @?= 3
          pfErrors pf @?= []

  , testCase "header row is not treated as data" $
      case parseCsv creditCardSpec sample of
        Left e   -> assertFailure (show e)
        Right pf -> map rrLine (pfRows pf) @?= [2, 3, 4]

  , testCase "a purchase stays negative (value-flow convention)" $
      case parseCsv creditCardSpec sample of
        Left e   -> assertFailure (show e)
        Right pf -> map rrAmount (pfRows pf)
                      @?= [Cents (-1262), Cents 57500, Cents (-20940)]

  , testCase "dates parse as MM/DD/YYYY, not DD/MM" $
      case parseCsv creditCardSpec sample of
        Left e   -> assertFailure (show e)
        Right pf -> map rrDate (pfRows pf)
                      @?= [ fromGregorian 2026 9 12
                          , fromGregorian 2026 9 10
                          , fromGregorian 2026 9 9 ]

  , testCase "a malformed row is reported, not fatal" $
      let bad = BL8.unlines
            [ "\"DATE\",\"DESCRIPTION\",\"AMOUNT\",\"CHECK #\",\"STATUS\""
            , "\"09/12/2026\",\"GOOD\",\"-1.00\",,\"Posted\""
            , "\"nonsense\",\"BAD DATE\",\"-2.00\",,\"Posted\""
            , "\"09/11/2026\",\"BAD AMOUNT\",\"abc\",,\"Posted\""
            , "\"09/10/2026\",\"ALSO GOOD\",\"-3.00\",,\"Posted\""
            ]
      in case parseCsv creditCardSpec bad of
           Left e   -> assertFailure (show e)
           Right pf -> do
             length (pfRows pf)   @?= 2
             length (pfErrors pf) @?= 2

  , testCase "blank trailing lines are ignored" $
      let withBlanks = sample <> "\n\n"
      in case parseCsv creditCardSpec withBlanks of
           Left e   -> assertFailure (show e)
           Right pf -> length (pfRows pf) @?= 3

  , testCase "DebitPositive inverts the sign" $
      let spec = creditCardSpec { csSign = DebitPositive }
      in case parseCsv spec sample of
           Left e   -> assertFailure (show e)
           Right pf -> map rrAmount (pfRows pf)
                         @?= [Cents 1262, Cents (-57500), Cents 20940]
  ]
