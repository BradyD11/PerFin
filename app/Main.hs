{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import           Control.Monad        (forM_, unless)
import qualified Data.ByteString.Lazy as BL
import           Data.Text            (Text)
import qualified Data.Text            as T
import qualified Data.Text.IO         as TIO
import           Data.Time            (Day, getCurrentTime, utctDay)
import           Options.Applicative
import           System.Exit          (exitFailure)

import           Domain.Types
import           Domain.Validation
import           Import.CSV
import           Persistence.DB

data Command
  = CmdImport FilePath FilePath Text        -- ^ db, csv, account
  | CmdAccountInit FilePath Text Text Text  -- ^ db, name, type, balance
  | CmdAccounts FilePath
  | CmdNetWorth FilePath

dbOpt :: Parser FilePath
dbOpt = strOption
  (long "db" <> metavar "PATH" <> value "ledger.db" <> showDefault
   <> help "SQLite database file")

commandParser :: Parser Command
commandParser = hsubparser
  ( command "import"
      (info (CmdImport <$> dbOpt
                       <*> argument str (metavar "CSV")
                       <*> strOption (long "account" <> metavar "NAME"
                                      <> help "Account to import into"))
            (progDesc "Import a CSV statement (idempotent)"))
 <> command "account"
      (info (hsubparser
              (command "init"
                (info (CmdAccountInit <$> dbOpt
                        <*> strOption (long "name" <> metavar "NAME")
                        <*> strOption (long "type" <> metavar "TYPE"
                              <> help "asset | liability | checking | credit-card")
                        <*> strOption (long "balance" <> metavar "AMOUNT"
                              <> value "0.00" <> showDefault
                              <> help "Opening balance, e.g. 1234.56"))
                      (progDesc "Create an account and set its opening balance"))
            <> command "list"
                (info (CmdAccounts <$> dbOpt) (progDesc "List accounts"))))
            (progDesc "Manage accounts"))
 <> command "report"
      (info (hsubparser
              (command "net-worth"
                (info (CmdNetWorth <$> dbOpt) (progDesc "Current net worth"))))
            (progDesc "Reports"))
  )

main :: IO ()
main = do
  cmd <- execParser (info (commandParser <**> helper)
          (fullDesc <> progDesc "Personal finance tracker"))
  today <- utctDay <$> getCurrentTime
  run today cmd

run :: Day -> Command -> IO ()
run today = \case
  CmdAccountInit db name ty bal -> do
    accName' <- orDie (mkAccountName name) renderValidationError
    accType' <- orDie (parseAccountType ty) id
    cents    <- orDie (centsFromDecimal bal) id
    withDb db $ \conn -> do
      initAccountBalance conn accName' accType' cents
      TIO.putStrLn ("initialized " <> unAccountName accName'
                    <> " (" <> renderAccountType accType'
                    <> ") opening balance " <> renderCents cents)

  CmdAccounts db -> withDb db $ \conn -> do
    accts <- listAccounts conn
    if null accts
      then TIO.putStrLn "no accounts yet"
      else forM_ accts $ \a -> do
        bal <- accountBalance conn (accName a)
        TIO.putStrLn (T.justifyLeft 18 ' ' (unAccountName (accName a))
                      <> T.justifyLeft 12 ' ' (renderAccountType (accType a))
                      <> renderCents bal)

  CmdNetWorth db -> withDb db $ \conn -> do
    nw <- netWorth conn
    TIO.putStrLn ("net worth: " <> renderCents nw)

  CmdImport db csvPath account -> do
    accName' <- orDie (mkAccountName account) renderValidationError
    withDb db $ \conn -> do
      acct <- lookupAccount conn accName'
      spec <- case acct of
        Nothing -> die ("unknown account: " <> account
                        <> "\nrun: ledger account init --name " <> account
                        <> " --type <asset|liability> --balance 0.00")
        Just a -> pure $ case accType a of
          Liability -> creditCardSpec
          Asset     -> checkingSpec
      bytes <- BL.readFile csvPath
      parsed <- orDie (parseCsv spec bytes) id
      unless (null (pfErrors parsed)) $ do
        TIO.putStrLn ("skipped " <> tshow (length (pfErrors parsed)) <> " malformed row(s):")
        forM_ (pfErrors parsed) (TIO.putStrLn . ("  " <>) . renderRowError)
      result <- importRows conn today accName' (pfRows parsed)
      case result of
        Left errs -> do
          TIO.putStrLn "import failed:"
          forM_ errs (TIO.putStrLn . ("  " <>))
          exitFailure
        Right s ->
          TIO.putStrLn ("imported " <> tshow (isInserted s)
                        <> " new, skipped " <> tshow (isSkipped s)
                        <> " already present")

tshow :: Show a => a -> Text
tshow = T.pack . show

orDie :: Either e a -> (e -> Text) -> IO a
orDie (Right a) _ = pure a
orDie (Left e) f  = die (f e)

die :: Text -> IO a
die msg = TIO.putStrLn ("error: " <> msg) >> exitFailure
