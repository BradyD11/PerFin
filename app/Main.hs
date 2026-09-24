{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import           Control.Monad        (forM_, unless)
import qualified Data.ByteString.Lazy as BL
import           Data.Text            (Text)
import qualified Data.Text            as T
import qualified Data.Text.IO         as TIO
import           Data.Time            (Day, addGregorianMonthsClip,
                                       getCurrentTime, utctDay)
import           Options.Applicative
import           System.Exit          (exitFailure)

import           Categorize.Prompt
import           Categorize.Rules
import           Domain.Types
import           Domain.Validation
import           Import.CSV
import           Persistence.DB
import           Report.NetWorth
import           Report.Spending

data Command
  = CmdImport FilePath FilePath Text
  | CmdAccountInit FilePath Text Text Text
  | CmdAccounts FilePath
  | CmdNetWorth FilePath (Maybe Text)
  | CmdSpending FilePath (Maybe Text) (Maybe Text)
  | CmdRulesAdd FilePath Text Text
  | CmdRulesList FilePath
  | CmdRulesRemove FilePath Text
  | CmdReview FilePath
  | CmdRecategorize FilePath

dbOpt :: Parser FilePath
dbOpt = strOption
  (long "db" <> metavar "PATH" <> value "ledger.db" <> showDefault
   <> help "SQLite database file")

monthOpt :: String -> String -> Parser (Maybe Text)
monthOpt nm hlp = optional (strOption (long nm <> metavar "YYYY-MM" <> help hlp))

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
 <> command "rules"
      (info (hsubparser
              (command "add"
                (info (CmdRulesAdd <$> dbOpt
                        <*> strOption (long "contains" <> metavar "TEXT"
                              <> help "Substring to match in the merchant")
                        <*> strOption (long "category" <> metavar "CATEGORY"))
                      (progDesc "Add or update a categorization rule"))
            <> command "list"
                (info (CmdRulesList <$> dbOpt) (progDesc "List rules"))
            <> command "remove"
                (info (CmdRulesRemove <$> dbOpt
                        <*> strOption (long "contains" <> metavar "TEXT"))
                      (progDesc "Remove a rule"))))
            (progDesc "Manage categorization rules"))
 <> command "review"
      (info (CmdReview <$> dbOpt)
            (progDesc "Interactively categorize unmatched merchants"))
 <> command "recategorize"
      (info (CmdRecategorize <$> dbOpt)
            (progDesc "Re-apply all rules to uncategorized transactions"))
 <> command "report"
      (info (hsubparser
              (command "net-worth"
                (info (CmdNetWorth <$> dbOpt
                        <*> monthOpt "since" "Only show months from here on")
                      (progDesc "Net worth over time"))
            <> command "spending"
                (info (CmdSpending <$> dbOpt
                        <*> monthOpt "month" "Month to report (default: latest)"
                        <*> optional (strOption (long "category"
                              <> metavar "CATEGORY"
                              <> help "Show only this category")))
                      (progDesc "Spending by category"))))
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
                      <> T.justifyRight 14 ' ' (renderCents bal))

  CmdNetWorth db mSince -> withDb db $ \conn -> do
    series <- netWorthSeries <$> monthlyNetWorth conn
    since <- traverse (parseMonthOrDie) mSince
    let shown = case since of
          Nothing -> series
          Just s  -> filter ((>= s) . nwpMonth) series
    if null shown
      then TIO.putStrLn "no transactions yet"
      else do
        TIO.putStrLn (T.justifyLeft 10 ' ' "month"
                      <> T.justifyRight 14 ' ' "net worth"
                      <> T.justifyRight 14 ' ' "change")
        mapM_ TIO.putStrLn (renderSeries shown)
        TIO.putStrLn ("\nchange over window: " <> renderCents (seriesChange shown))

  CmdSpending db mMonth mCat -> withDb db $ \conn -> do
    month <- case mMonth of
      Just m  -> parseMonthOrDie m
      Nothing -> do
        ms <- distinctMonths conn
        case reverse ms of
          (m:_) -> pure m
          []    -> die "no transactions yet"
    let next = addGregorianMonthsClip 1 month
    txs <- transactionsIn conn (Just month) (Just next)
    prev <- transactionsIn conn (Just (addGregorianMonthsClip (-1) month)) (Just month)
    filtered <- case mCat of
      Nothing -> pure txs
      Just c  -> do
        cat <- orDie (parseCategory c) id
        pure (filter ((== cat) . trCategory) txs)
    if null filtered
      then TIO.putStrLn ("no transactions in " <> renderMonth month)
      else do
        TIO.putStrLn (renderMonth month <> "\n")
        forM_ (spendingByCategory filtered) $ \cl ->
          TIO.putStrLn (T.justifyLeft 16 ' ' (renderCategory (clCategory cl))
                        <> T.justifyRight 12 ' ' (renderCents (clTotal cl))
                        <> "   " <> T.pack (show (clCount cl)) <> " tx")
        TIO.putStrLn ("\nout: " <> renderCents (totalOutflow filtered)
                      <> "   in: " <> renderCents (totalInflow filtered))
        unless (null prev) $ do
          TIO.putStrLn "\nvs. previous month:"
          forM_ (take 5 (monthOverMonth filtered prev)) $ \md ->
            TIO.putStrLn (T.justifyLeft 16 ' ' (renderCategory (mdCategory md))
                          <> T.justifyRight 12 ' ' (signed (mdChange md)))

  CmdRulesAdd db needle catTxt -> do
    cat <- orDie (parseCategory catTxt) id
    rule <- orDie (mkRule needle cat) renderRuleError
    withDb db $ \conn -> do
      insertRule conn rule
      s <- applyRules conn
      TIO.putStrLn ("rule added: \"" <> ruleNeedle rule <> "\" -> "
                    <> renderCategory cat)
      TIO.putStrLn (T.pack (show (csUpdated s)) <> " transaction(s) recategorized, "
                    <> T.pack (show (csRemaining s)) <> " still uncategorized")

  CmdRulesList db -> withDb db $ \conn -> do
    rules <- listRules conn
    if null rules
      then TIO.putStrLn "no rules yet"
      else do
        -- Width the column to the longest needle so a long rule cannot run
        -- into the category and make the listing unreadable.
        let w = 2 + maximum (map (T.length . ruleNeedle) rules)
        forM_ rules $ \r ->
          TIO.putStrLn (T.justifyLeft w ' ' (ruleNeedle r)
                        <> renderCategory (ruleCategory r))

  CmdRulesRemove db needle -> withDb db $ \conn -> do
    removed <- deleteRule conn needle
    TIO.putStrLn (if removed then "rule removed" else "no such rule")

  CmdReview db -> withDb db reviewLoop

  CmdRecategorize db -> withDb db $ \conn -> do
    s <- applyRules conn
    TIO.putStrLn (T.pack (show (csUpdated s)) <> " transaction(s) recategorized, "
                  <> T.pack (show (csRemaining s)) <> " still uncategorized")

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
        Right s -> do
          TIO.putStrLn ("imported " <> tshow (isInserted s)
                        <> " new, skipped " <> tshow (isSkipped s)
                        <> " already present")
          -- Rules are applied automatically on import so a fresh statement is
          -- categorized as far as existing rules allow, without a second command.
          cs <- applyRules conn
          TIO.putStrLn (tshow (csUpdated cs) <> " categorized by rules, "
                        <> tshow (csRemaining cs) <> " need review")

signed :: Cents -> Text
signed c@(Cents n) | n > 0 = "+" <> renderCents c
                   | otherwise = renderCents c

parseMonthOrDie :: Text -> IO Day
parseMonthOrDie t = case parseMonth t of
  Just d  -> pure d
  Nothing -> die ("expected YYYY-MM, got: " <> t)

tshow :: Show a => a -> Text
tshow = T.pack . show

orDie :: Either e a -> (e -> Text) -> IO a
orDie (Right a) _ = pure a
orDie (Left e) f  = die (f e)

die :: Text -> IO a
die msg = TIO.putStrLn ("error: " <> msg) >> exitFailure
