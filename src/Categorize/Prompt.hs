{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}

-- | Interactive fallback for merchants no rule matches.
--
-- The decision logic is separated from the I/O so it can be tested without a
-- terminal: 'parseAnswer' is pure and total, and 'reviewLoop' is the thin
-- shell around it.
module Categorize.Prompt
  ( Answer (..)
  , parseAnswer
  , promptText
  , reviewLoop
  ) where

import           Control.Monad      (forM_)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           Database.SQLite.Simple (Connection)
import           System.IO          (hFlush, stdout)

import           Categorize.Rules
import           Domain.Types
import           Persistence.DB

-- | What the user typed at the review prompt.
data Answer
  = Chose Category   -- ^ categorize, and remember as a rule
  | Skip             -- ^ leave uncategorized, ask again next time
  | Quit
  deriving stock (Eq, Show)

-- | Parse a prompt response.
--
-- Accepts a category name (@groceries@), a unique case-insensitive prefix
-- (@gro@), or the 1-based number shown in the menu. Ambiguous prefixes are
-- rejected rather than guessed — silently picking @Groceries@ when the user
-- typed @"s"@ and meant @Subscriptions@ would write a wrong rule that then
-- mis-categorizes every future import.
parseAnswer :: Text -> Maybe Answer
parseAnswer raw = case T.toLower (T.strip raw) of
  ""  -> Just Skip
  "s" -> Just Skip
  "skip" -> Just Skip
  "q" -> Just Quit
  "quit" -> Just Quit
  t   -> byNumber t `orElse` byName t
  where
    orElse (Just a) _ = Just a
    orElse Nothing  b = b

    selectable = filter (/= Uncategorized) allCategories

    byNumber t = case reads (T.unpack t) :: [(Int, String)] of
      [(n, "")] | n >= 1 && n <= length selectable ->
        Just (Chose (selectable !! (n - 1)))
      _ -> Nothing

    byName t =
      case filter (\c -> t `T.isPrefixOf` renderCategory c) selectable of
        [c] -> Just (Chose c)
        _   -> Nothing   -- zero matches, or ambiguous

-- | The menu shown above the prompt.
promptText :: Text
promptText =
  T.intercalate "\n"
    [ "  " <> T.pack (show i) <> ") " <> renderCategory c
    | (i, c) <- zip [1 :: Int ..] (filter (/= Uncategorized) allCategories)
    ]
  <> "\n  s) skip    q) quit"

-- | Walk every uncategorized merchant, asking once per merchant.
--
-- An answer is persisted as a rule and immediately applied, so the same
-- merchant is never asked about twice — including for rows imported later.
reviewLoop :: Connection -> IO ()
reviewLoop conn = do
  merchants <- uncategorizedMerchants conn
  if null merchants
    then TIO.putStrLn "nothing to review: every transaction is categorized"
    else do
      TIO.putStrLn (T.pack (show (length merchants))
                    <> " merchant(s) need a category.\n")
      go merchants
  where
    go [] = TIO.putStrLn "\nreview complete"
    go ((merchant, n) : rest) = do
      TIO.putStrLn (merchant <> "  (" <> T.pack (show n) <> " transaction(s))")
      TIO.putStrLn promptText
      TIO.putStr "> "
      hFlush stdout
      line <- TIO.getLine
      case parseAnswer line of
        Nothing -> do
          TIO.putStrLn "  not a valid choice, try again\n"
          go ((merchant, n) : rest)
        Just Quit -> TIO.putStrLn "\nstopped"
        Just Skip -> TIO.putStrLn "" >> go rest
        Just (Chose cat) ->
          case mkRule merchant cat of
            Left e -> do
              TIO.putStrLn ("  " <> renderRuleError e <> "\n")
              go rest
            Right r -> do
              insertRule conn r
              summary <- applyRules conn
              TIO.putStrLn ("  -> " <> renderCategory cat
                            <> " (" <> T.pack (show (csUpdated summary))
                            <> " transaction(s) updated)\n")
              go rest
