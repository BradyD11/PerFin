{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Domain.TypesSpec (tests) where

import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck as QC

import           Domain.Types
import           Gen

instance Arbitrary AccountType where
  arbitrary = elements [minBound .. maxBound]

tests :: TestTree
tests = testGroup "Domain.Types"
  [ testGroup "Cents round-trip"
    [ QC.testProperty "renderCents then centsFromDecimal is identity" $
        \(AnyCents c) -> centsFromDecimal (renderCents c) === Right c

    , QC.testProperty "addition is exact (no float drift)" $
        \(AnyCents a) (AnyCents b) ->
          -- The classic float failure is 0.1 + 0.2 /= 0.3. With integer cents
          -- the sum must round-trip exactly, for every pair, with no epsilon.
          centsFromDecimal (renderCents (a + b)) === Right (a + b)
    ]

  , testGroup "Cents parsing"
    [ testCase "purchase from the real export" $
        centsFromDecimal "-12.62" @?= Right (Cents (-1262))
    , testCase "payment from the real export" $
        centsFromDecimal "575.00" @?= Right (Cents 57500)
    , testCase "large payment" $
        centsFromDecimal "1457.50" @?= Right (Cents 145750)
    , testCase "one decimal place is padded" $
        centsFromDecimal "5.5" @?= Right (Cents 550)
    , testCase "no decimal place" $
        centsFromDecimal "42" @?= Right (Cents 4200)
    , testCase "currency symbols and separators are tolerated" $
        centsFromDecimal "$1,234.56" @?= Right (Cents 123456)
    , testCase "three decimals are rejected, not truncated" $
        assertBool "should reject" (isLeft (centsFromDecimal "1.234"))
    , testCase "non-numeric is rejected" $
        assertBool "should reject" (isLeft (centsFromDecimal "abc"))
    , testCase "empty is rejected" $
        assertBool "should reject" (isLeft (centsFromDecimal ""))
    , testCase "lone minus is rejected" $
        assertBool "should reject" (isLeft (centsFromDecimal "-"))
    ]

  , testGroup "Cents rendering"
    [ testCase "sub-dollar negative keeps its sign" $
        renderCents (Cents (-5)) @?= "-0.05"
    , testCase "sub-dollar positive" $ renderCents (Cents 5) @?= "0.05"
    , testCase "zero" $ renderCents (Cents 0) @?= "0.00"
    , testCase "exact dollar" $ renderCents (Cents 100) @?= "1.00"
    ]

  , testGroup "net worth"
    [ QC.testProperty "an outflow always reduces net worth, on any account type" $
        \(AnyCents c) ty -> c < Cents 0 QC.==> netWorthDelta ty c < Cents 0

    , testCase "a card payment nets to zero against the checking outflow" $
        -- This is the regression test for the sign bug: negating liability
        -- deltas would make this -1150.00 instead of 0.
        let cardSide     = netWorthDelta Liability (Cents 57500)
            checkingSide = netWorthDelta Asset     (Cents (-57500))
        in cardSide + checkingSide @?= Cents 0

    , testCase "a card purchase reduces net worth by its amount" $
        netWorthDelta Liability (Cents (-1262)) @?= Cents (-1262)

    , QC.testProperty "any transfer between two accounts is net-worth neutral" $
        \(AnyCents c) ta tb ->
          netWorthDelta ta c + netWorthDelta tb (negate' c) === Cents 0
    ]

  , testGroup "enums round-trip"
    [ QC.testProperty "category render/parse" $
        forAll (elements allCategories) $ \c ->
          parseCategory (renderCategory c) === Right c
    , testCase "account type aliases" $ do
        parseAccountType "asset"       @?= Right Asset
        parseAccountType "liability"   @?= Right Liability
        parseAccountType "credit-card" @?= Right Liability
        parseAccountType "checking"    @?= Right Asset
    ]
  ]

negate' :: Cents -> Cents
negate' (Cents n) = Cents (negate n)

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False
