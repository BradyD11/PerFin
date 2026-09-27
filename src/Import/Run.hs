{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}

-- | One import path, shared by the CLI (@ledger import@) and the web upload.
--
-- Parse, validate, dedup, insert, then apply existing rules. Keeping this in
-- one function means a statement imported from the browser and the same
-- statement imported from the terminal land identically, down to which rows
-- are skipped as already present.
module Import.Run
  ( ImportReport (..)
  , ImportFailure (..)
  , renderImportFailure
  , runImport
  , knownAccountType
  ) where

import qualified Data.ByteString.Lazy   as BL
import           Data.Text              (Text)
import           Data.Time              (Day)
import           Database.SQLite.Simple (Connection)

import           Domain.Types
import           Import.CSV
import           Persistence.DB

data ImportReport = ImportReport
  { irAccount    :: AccountName
  , irType       :: AccountType
  , irCreated    :: Bool       -- ^ the account did not exist and was created
  , irInserted   :: Int
  , irSkipped    :: Int        -- ^ already present: dedup at work
  , irMalformed  :: [RowError] -- ^ rows that could not be parsed; not imported
  , irByRules    :: Int        -- ^ categorized immediately by existing rules
  , irNewOpen    :: Int        -- ^ change in uncategorized rows
  } deriving stock (Eq, Show)

data ImportFailure
  = UnknownAccount AccountName
  | UnreadableFile Text
  | RejectedRows [Text]        -- ^ domain validation refused the batch
  | NoRows [RowError]          -- ^ nothing usable: empty, or every row malformed
  deriving stock (Eq, Show)

renderImportFailure :: ImportFailure -> [Text]
renderImportFailure (UnknownAccount n) =
  [ "unknown account: " <> unAccountName n
  , "run: ledger account init --name " <> unAccountName n
    <> " --type <asset|liability> --balance 0.00" ]
renderImportFailure (UnreadableFile e) = ["not a readable CSV: " <> e]
renderImportFailure (RejectedRows es) = es
renderImportFailure (NoRows errs) =
  "no transaction rows found; is this a statement export in the expected format?"
    : map renderRowError (take 5 errs)

-- | The two accounts the upload screen offers by name, and their types.
--
-- Uploading to one of these creates it when missing (with an undated zero
-- balance, reported back so the caller can say so). Any other name must be
-- created deliberately with @ledger account init@, because guessing an
-- account's type would guess whether its balance is money held or owed.
knownAccountType :: Text -> Maybe AccountType
knownAccountType "checking"    = Just Asset
knownAccountType "credit-card" = Just Liability
knownAccountType _             = Nothing

runImport
  :: Connection
  -> Day                -- ^ today, for validation
  -> Bool               -- ^ create a known account if it is missing
  -> AccountName
  -> BL.ByteString
  -> IO (Either ImportFailure ImportReport)
runImport conn today createKnown name bytes = do
  existing <- lookupAccount conn name
  let known = knownAccountType (unAccountName name)
      target = case (existing, known) of
        (Just a, _)                     -> Just (accType a, False)
        (Nothing, Just ty) | createKnown -> Just (ty, True)
        _                               -> Nothing
  case target of
    Nothing -> pure (Left (UnknownAccount name))
    Just (ty, create) -> do
      let spec = case ty of { Liability -> creditCardSpec; Asset -> checkingSpec }
      -- Parse before touching the database, so an unreadable file never
      -- leaves a half-made account behind.
      case parseCsv spec bytes of
        Left e -> pure (Left (UnreadableFile e))
        -- A file with no usable rows is almost always the wrong file (another
        -- bank's layout, a summary export). Refuse it rather than report a
        -- cheerful "0 imported" and create an account for nothing.
        Right parsed | null (pfRows parsed) -> pure (Left (NoRows (pfErrors parsed)))
        Right parsed -> do
          if create then initAccountBalance conn name ty (Cents 0) Nothing else pure ()
          before <- uncategorizedCount conn
          result <- importRows conn today name (pfRows parsed)
          case result of
            Left errs -> do
              -- The batch was refused as a whole; an account created for it
              -- would be an empty leftover, so it goes too.
              if create then removeAccountIfEmpty conn name else pure ()
              pure (Left (RejectedRows errs))
            Right s -> do
              cs <- applyRules conn
              after <- uncategorizedCount conn
              pure $ Right ImportReport
                { irAccount   = name
                , irType      = ty
                , irCreated   = create
                , irInserted  = isInserted s
                , irSkipped   = isSkipped s
                , irMalformed = pfErrors parsed
                , irByRules   = csUpdated cs
                , irNewOpen   = after - before
                }
