module Main (main) where

import           Test.Tasty

import qualified Domain.TypesSpec
import qualified Domain.ValidationSpec
import qualified Import.CSVSpec
import qualified Import.DedupSpec
import qualified Persistence.DBSpec

main :: IO ()
main = defaultMain $ testGroup "ledger-cli"
  [ Domain.TypesSpec.tests
  , Domain.ValidationSpec.tests
  , Import.CSVSpec.tests
  , Import.DedupSpec.tests
  , Persistence.DBSpec.tests
  ]
