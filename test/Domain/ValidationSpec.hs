{-# LANGUAGE OverloadedStrings #-}

module Domain.ValidationSpec (tests) where

import qualified Data.Text             as T
import           Data.Time             (addDays, fromGregorian)
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck as QC

import           Domain.Types
import           Domain.Validation
import           Gen

tests :: TestTree
tests = testGroup "Domain.Validation"
  [ testGroup "mkAccountName"
    [ testCase "rejects empty" $
        assertBool "" (isLeft (mkAccountName ""))
    , testCase "rejects whitespace-only" $
        assertBool "" (isLeft (mkAccountName "   \t "))
    , testCase "trims" $
        fmap unAccountName (mkAccountName "  checking ") @?= Right "checking"
    ]

  , testGroup "mkMerchant"
    [ testCase "rejects empty after trimming" $
        assertBool "" (isLeft (mkMerchant "   "))
    , testCase "collapses internal whitespace" $
        fmap unMerchant (mkMerchant "TACO   BOYS\tTEMPE") @?= Right "TACO BOYS TEMPE"
    ]

  , testGroup "mkTransaction rejects invalid states"
    [ testCase "future date" $
        assertBool "" (isLeft (mk (fromGregorian 2027 1 1) (Cents (-100)) "X"))
    , testCase "zero amount" $
        assertBool "" (isLeft (mk (fromGregorian 2026 9 1) (Cents 0) "X"))
    , testCase "empty merchant" $
        assertBool "" (isLeft (mk (fromGregorian 2026 9 1) (Cents (-100)) "   "))
    , testCase "today itself is accepted (boundary, not future)" $
        assertBool "" (isRight (mk testToday (Cents (-100)) "TODAY"))
    , testCase "tomorrow is rejected" $
        assertBool "" (isLeft (mk (addDays 1 testToday) (Cents (-100)) "TOMORROW"))
    , testCase "a valid row is accepted" $
        assertBool "" (isRight (mk (fromGregorian 2026 9 12) (Cents (-1262)) "SQ *TACO BOYS"))

    , QC.testProperty "no transaction is ever built with a zero amount" $
        forAll genDay $ \d -> forAll genMerchant $ \m ->
          isLeft (mk d (Cents 0) m)

    , QC.testProperty "valid inputs always succeed and preserve the amount" $
        forAll genDay $ \d -> forAll genMerchant $ \m ->
          forAll (choose (-50000, 50000) `suchThat` (/= 0)) $ \n ->
            case mk d (Cents n) m of
              Right t -> txAmount t === Cents n
              Left _  -> property False
    ]

  , testGroup "normalizeMerchant"
    [ testCase "strips the volatile reference number" $
        normalizeMerchant "KLM AIRLINE 0742143148993800-6180104 DC"
          @?= "KLM AIRLINE - DC"
    , testCase "uppercases and collapses" $
        normalizeMerchant "  Trader  joe's  " @?= "TRADER JOE'S"
    , QC.testProperty "is idempotent" $
        forAll genMerchant $ \m ->
          normalizeMerchant (normalizeMerchant m) === normalizeMerchant m
    , QC.testProperty "output never contains a digit" $
        forAll genMerchant $ \m ->
          T.all (\c -> c `notElem` ("0123456789" :: String)) (normalizeMerchant m)
    ]
  ]
  where
    mk d amt m =
      mkTransaction testToday (TransactionId "t")
        (either (error "bad acct") id (mkAccountName "checking"))
        d amt m Uncategorized

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _         = False
