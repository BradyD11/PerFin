{-# LANGUAGE DerivingStrategies #-}
{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

-- | SQLite persistence: schema, migrations, and the idempotent import path.
module Persistence.DB
  ( withDb
  , openDb
  , migrate
  , Account (..)
  , upsertAccount
  , initAccountBalance
  , lookupAccount
  , listAccounts
  , ImportSummary (..)
  , importRows
  , insertTransaction
  , existingIds
  , allTransactions
  , accountBalance
  , netWorth
  ) where

import           Control.Exception        (bracket)
import           Control.Monad            (forM, forM_)
import           Data.Maybe               (mapMaybe)
import qualified Data.Set                 as Set
import           Data.Text                (Text)
import qualified Data.Text                as T
import           Data.Time                (Day)
import           Database.SQLite.Simple
import           Database.SQLite.Simple.FromField (FromField (..))
import           Database.SQLite.Simple.ToField   (ToField (..))

import           Domain.Types
import           Domain.Validation        (mkAccountName, mkTransaction,
                                           renderValidationError)
import           Import.CSV               (RawRow (..))
import           Import.Dedup             (deriveIds)

-- Orphans by necessity: @Domain.Types@ deliberately does not depend on
-- sqlite-simple, so that the domain layer stays free of any persistence
-- concern. This module is the only place that persists these types, so the
-- usual orphan hazard (two conflicting instances in one program) cannot arise.
instance ToField Cents where
  toField (Cents n) = toField n

instance FromField Cents where
  fromField f = Cents <$> fromField f

instance ToField TransactionId where
  toField (TransactionId t) = toField t

instance FromField TransactionId where
  fromField f = TransactionId <$> fromField f

data Account = Account
  { accName    :: AccountName
  , accType    :: AccountType
  , accOpening :: Cents
  } deriving stock (Eq, Show)

withDb :: FilePath -> (Connection -> IO a) -> IO a
withDb path action = bracket (openDb path) close action

-- | Open and migrate. Foreign keys are off by default in SQLite, so they are
-- enabled explicitly — otherwise the transaction/account reference is
-- decorative.
openDb :: FilePath -> IO Connection
openDb path = do
  conn <- open path
  execute_ conn "PRAGMA foreign_keys = ON"
  migrate conn
  pure conn

migrate :: Connection -> IO ()
migrate conn = do
  execute_ conn
    "CREATE TABLE IF NOT EXISTS accounts \
    \( name            TEXT PRIMARY KEY \
    \, type            TEXT NOT NULL CHECK (type IN ('asset','liability')) \
    \, opening_balance INTEGER NOT NULL DEFAULT 0 \
    \)"
  -- amount is INTEGER cents. Storing money as REAL here would undo the whole
  -- point of the Cents newtype at the one boundary where it is easiest to miss.
  execute_ conn
    "CREATE TABLE IF NOT EXISTS transactions \
    \( id       TEXT PRIMARY KEY \
    \, account  TEXT NOT NULL REFERENCES accounts(name) \
    \, day      TEXT NOT NULL \
    \, amount   INTEGER NOT NULL \
    \, merchant TEXT NOT NULL \
    \, category TEXT NOT NULL \
    \)"
  execute_ conn
    "CREATE INDEX IF NOT EXISTS idx_tx_account_day ON transactions(account, day)"
  execute_ conn
    "CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category)"

upsertAccount :: Connection -> AccountName -> AccountType -> IO ()
upsertAccount conn name ty =
  execute conn
    "INSERT INTO accounts (name, type) VALUES (?, ?) \
    \ON CONFLICT(name) DO UPDATE SET type = excluded.type"
    (unAccountName name, renderAccountType ty)

-- | Set the opening balance. Separate from 'upsertAccount' so that re-running
-- an import never silently resets a balance the user set deliberately.
initAccountBalance :: Connection -> AccountName -> AccountType -> Cents -> IO ()
initAccountBalance conn name ty bal = do
  upsertAccount conn name ty
  execute conn "UPDATE accounts SET opening_balance = ? WHERE name = ?"
    (bal, unAccountName name)

lookupAccount :: Connection -> AccountName -> IO (Maybe Account)
lookupAccount conn name = do
  rows <- query conn
    "SELECT name, type, opening_balance FROM accounts WHERE name = ?"
    (Only (unAccountName name))
  pure (firstOf (mapMaybe toAccount rows))
  where firstOf = \case { (x:_) -> Just x; [] -> Nothing }

listAccounts :: Connection -> IO [Account]
listAccounts conn = do
  rows <- query_ conn "SELECT name, type, opening_balance FROM accounts ORDER BY name"
  pure (mapMaybe toAccount rows)

toAccount :: (Text, Text, Cents) -> Maybe Account
toAccount (n, t, bal) =
  case (mkAccountName n, parseAccountType t) of
    (Right nm, Right ty) -> Just (Account nm ty bal)
    _                    -> Nothing

data ImportSummary = ImportSummary
  { isInserted :: Int
  , isSkipped  :: Int    -- ^ already present: the idempotency guarantee at work
  } deriving stock (Eq, Show)

-- | Import rows for an account, skipping any whose derived id is already
-- stored.
--
-- Runs in a single SQLite transaction: a crash mid-import leaves the database
-- as it was, rather than half a statement that the next run would have to
-- reconcile.
importRows
  :: Connection
  -> Day               -- ^ today, for validation
  -> AccountName
  -> [RawRow]
  -> IO (Either [Text] ImportSummary)
importRows conn today account rows = do
  acct <- lookupAccount conn account
  case acct of
    Nothing -> pure (Left ["unknown account: " <> unAccountName account
                          <> " (run `ledger account init` first)"])
    Just _ -> do
      let withIds = deriveIds account rows
      seen <- existingIds conn account
      let fresh = [ p | p@(_, tid) <- withIds, not (Set.member tid seen) ]
          skipped = length withIds - length fresh
      built <- forM fresh $ \(r, tid) ->
        pure (buildTransaction today tid account r)
      let errs = [ e | Left e <- built ]
          oks  = [ t | Right t <- built ]
      if not (null errs)
        then pure (Left errs)
        else do
          withTransaction conn $
            forM_ oks (insertTransaction conn)
          pure (Right (ImportSummary (length oks) skipped))

buildTransaction :: Day -> TransactionId -> AccountName -> RawRow -> Either Text Transaction
buildTransaction today tid account r =
  case mkTransaction today tid account (rrDate r) (rrAmount r) (rrMerchant r) Uncategorized of
    Left err -> Left ("line " <> T.pack (show (rrLine r)) <> ": " <> renderValidationError err)
    Right t  -> Right t

insertTransaction :: Connection -> Transaction -> IO ()
insertTransaction conn t =
  execute conn
    "INSERT OR IGNORE INTO transactions (id, account, day, amount, merchant, category) \
    \VALUES (?, ?, ?, ?, ?, ?)"
    ( txId t
    , unAccountName (txAccount t)
    , show (txDate t)
    , txAmount t
    , unMerchant (txMerchant t)
    , renderCategory (txCategory t)
    )

existingIds :: Connection -> AccountName -> IO (Set.Set TransactionId)
existingIds conn account = do
  rows <- query conn "SELECT id FROM transactions WHERE account = ?"
            (Only (unAccountName account))
  pure (Set.fromList (map fromOnly rows))

allTransactions :: Connection -> IO [(Text, Day, Cents, Text, Text)]
allTransactions conn =
  query_ conn
    "SELECT account, day, amount, merchant, category FROM transactions ORDER BY day, id"

-- | Opening balance plus the sum of every transaction in the account.
accountBalance :: Connection -> AccountName -> IO Cents
accountBalance conn name = do
  acct <- lookupAccount conn name
  let opening = maybe (Cents 0) accOpening acct
  rows <- query conn "SELECT COALESCE(SUM(amount), 0) FROM transactions WHERE account = ?"
            (Only (unAccountName name))
  let summed = case rows of { (Only c : _) -> c; [] -> Cents 0 }
  pure (opening + summed)

-- | Net worth across every account.
--
-- Because amounts are stored under the value-flow convention, a liability
-- account's accumulated balance is already negative while debt is carried, so
-- the accounts sum directly. See 'netWorthDelta' for why this is the correct
-- combination and not an oversight.
netWorth :: Connection -> IO Cents
netWorth conn = do
  accts <- listAccounts conn
  bals <- forM accts $ \a -> do
    b <- accountBalance conn (accName a)
    pure (netWorthDelta (accType a) b)
  pure (sum bals)
