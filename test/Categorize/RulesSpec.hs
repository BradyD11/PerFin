{-# LANGUAGE OverloadedStrings #-}

module Categorize.RulesSpec (tests) where

import           Data.Either           (isLeft)
import           Data.Text             (Text)
import           Test.Tasty
import           Test.Tasty.HUnit
import           Test.Tasty.QuickCheck as QC

import           Categorize.Prompt
import           Categorize.Rules
import           Domain.Types
import           Gen

rule :: Text -> Category -> Rule
rule n c = either (error "bad rule") id (mkRule n c)

tests :: TestTree
tests = testGroup "Categorize"
  [ testGroup "mkRule"
    [ testCase "normalizes the needle" $
        fmap ruleNeedle (mkRule "  trader joe's  " Groceries)
          @?= Right "TRADER JOE'S"
    , testCase "rejects an empty pattern" $
        assertBool "" (isLeft (mkRule "" Groceries))
    , testCase "rejects a whitespace-only pattern" $
        assertBool "" (isLeft (mkRule "   " Groceries))
    , testCase "rejects an all-digits pattern" $
        -- Would normalize to "" and match every merchant.
        assertBool "" (isLeft (mkRule "12345" Groceries))
    ]

  , testGroup "matching"
    [ testCase "matches case-insensitively" $
        assertBool "" (matchRule (rule "trader joe" Groceries)
                        "TRADER JOE'S #123 TEMPE AZ")
    , testCase "matches despite the store number" $
        assertBool "" (matchRule (rule "chipotle" Dining)
                        "CHIPOTLE MEX GR ONLINE https://prod.CA")
    , testCase "does not match an unrelated merchant" $
        assertBool "" (not (matchRule (rule "trader joe" Groceries)
                        "MTA*NYCT PAYGO NEW YORK NY"))

    , testCase "the more specific rule wins regardless of insertion order" $
        let general  = rule "taco" Dining
            specific = rule "taco boys" Groceries
        in do
          categorize [general, specific] "SQ *TACO BOYS TEMPE" @?= Groceries
          categorize [specific, general] "SQ *TACO BOYS TEMPE" @?= Groceries

    , testCase "unmatched merchants fall back to Uncategorized" $
        categorize [rule "rent" Rent] "MTA*NYCT PAYGO" @?= Uncategorized

    , testCase "no rules means everything is uncategorized" $
        categorize [] "ANYTHING" @?= Uncategorized

    , QC.testProperty "categorize agrees with firstMatch" $
        forAll genMerchant $ \m ->
          let rs = [rule "taco" Dining, rule "mta" Transfer]
          in categorize rs m === maybe Uncategorized ruleCategory (firstMatch rs m)

    , QC.testProperty "a rule always matches its own needle" $
        forAll genMerchant $ \m ->
          case mkRule m Dining of
            Right r -> matchRule r m
            Left _  -> True   -- rejected patterns are not required to match
    ]

  , testGroup "prompt parsing"
    [ testCase "full name" $ parseAnswer "groceries" @?= Just (Chose Groceries)
    , testCase "is case-insensitive" $ parseAnswer "GROCERIES" @?= Just (Chose Groceries)
    , testCase "unique prefix" $ parseAnswer "gro" @?= Just (Chose Groceries)
    , testCase "menu number" $ parseAnswer "1" @?= Just (Chose Groceries)
    , testCase "empty input skips" $ parseAnswer "" @?= Just Skip
    , testCase "q quits" $ parseAnswer "q" @?= Just Quit
    , testCase "nonsense is rejected, not guessed" $
        parseAnswer "zzzz" @?= Nothing
    , testCase "an out-of-range number is rejected" $
        parseAnswer "99" @?= Nothing
    , testCase "Uncategorized is not selectable" $
        -- Offering it would let the user 'choose' the state that means
        -- 'no choice made', and write a rule that does nothing.
        parseAnswer "uncategorized" @?= Nothing
    ]
  ]
