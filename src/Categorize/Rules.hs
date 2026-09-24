{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}

-- | Keyword-based categorization.
--
-- A rule says "if the normalized merchant contains this substring, the
-- category is X". Matching is pure and total; persistence lives in
-- "Persistence.DB" and the interactive fallback in "Categorize.Prompt".
--
-- == Why substring matching on the normalized form
--
-- Rules are matched against 'Domain.Validation.normalizeMerchant' output, not
-- the raw description. That is the same canonical form the dedup key uses:
-- uppercased, whitespace-collapsed, digits stripped. It means a rule written
-- as @"trader joe"@ matches @"TRADER JOE'S #123 TEMPE AZ"@ without the user
-- having to think about case, spacing, or the store number.
module Categorize.Rules
  ( Rule (..)
  , mkRule
  , RuleError (..)
  , renderRuleError
  , matchRule
  , categorize
  , categorizeAll
  , firstMatch
  ) where

import           Data.List         (sortOn)
import           Data.Ord          (Down (..))
import           Data.Text         (Text)
import qualified Data.Text         as T

import           Domain.Types
import           Domain.Validation (normalizeMerchant)

-- | A single keyword rule.
--
-- @ruleNeedle@ is stored already normalized, so matching never has to
-- re-normalize it and a rule cannot be saved in a form that can never match.
data Rule = Rule
  { ruleNeedle   :: Text      -- ^ normalized substring to look for
  , ruleCategory :: Category
  } deriving stock (Eq, Ord, Show)

data RuleError
  = EmptyNeedle
  | NeedleAllDigits Text
    -- ^ Digits are stripped during normalization, so a purely numeric rule
    -- normalizes to the empty string and would match everything.
  deriving stock (Eq, Show)

renderRuleError :: RuleError -> Text
renderRuleError EmptyNeedle = "rule pattern is empty"
renderRuleError (NeedleAllDigits t) =
  "rule pattern \"" <> t <> "\" contains no matchable characters \
  \(digits are ignored when matching)"

-- | Smart constructor: normalizes the needle and rejects one that could never
-- usefully match.
--
-- The all-digits case is the dangerous one. @normalizeMerchant "12345"@ is
-- @""@, and every string contains the empty string, so such a rule would
-- silently categorize the entire ledger.
mkRule :: Text -> Category -> Either RuleError Rule
mkRule raw cat
  | T.null (T.strip raw) = Left EmptyNeedle
  | T.null needle        = Left (NeedleAllDigits raw)
  | otherwise            = Right (Rule needle cat)
  where needle = normalizeMerchant raw

-- | Does this rule match this (raw, un-normalized) merchant string?
matchRule :: Rule -> Text -> Bool
matchRule r merchant = ruleNeedle r `T.isInfixOf` normalizeMerchant merchant

-- | The winning rule for a merchant, if any.
--
-- Longer needles win. A specific rule (@"TRADER JOE"@) should beat a general
-- one (@"JOE"@) regardless of the order they were added, and length is a
-- reasonable proxy for specificity that does not require the user to manage
-- priorities by hand. Ties break on the needle text so the result is total
-- and deterministic rather than dependent on insertion order.
firstMatch :: [Rule] -> Text -> Maybe Rule
firstMatch rules merchant =
  case filter (`matchRule` merchant) (sortOn (\r -> (Down (T.length (ruleNeedle r)), ruleNeedle r)) rules) of
    (r:_) -> Just r
    []    -> Nothing

-- | Category for a merchant, falling back to 'Uncategorized'.
categorize :: [Rule] -> Text -> Category
categorize rules merchant = maybe Uncategorized ruleCategory (firstMatch rules merchant)

-- | Categorize a batch, pairing each merchant with its result.
categorizeAll :: [Rule] -> [Text] -> [(Text, Category)]
categorizeAll rules = map (\m -> (m, categorize rules m))
