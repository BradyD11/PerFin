{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}

-- | The JSON API behind the web review screen.
--
-- The API is deliberately thin over the library. Money is formatted here by
-- 'renderMagnitude', patterns are validated by 'mkRule', previews come from
-- 'Categorize.Review.preview', and saving goes through 'Persistence.DB.decide'.
-- The browser renders and collects decisions; it never recomputes one.
module Server.API
  ( API
  , ServerConfig (..)
  , app
  , runServer
  ) where

import           Control.Concurrent.MVar  (MVar, newMVar, withMVar)
import           Control.Monad.IO.Class   (liftIO)
import           Data.Aeson
import           Data.Text                (Text)
import           Data.Time                (getCurrentTime, utctDay)
import           Database.SQLite.Simple   (Connection)
import           Network.Wai.Application.Static (defaultWebAppSettings, ssIndices)
import           Network.Wai.Handler.Warp (run)
import           WaiAppStatic.Types       (unsafeToPiece)
import           Servant

import           Categorize.Review
import           Categorize.Rules
import           Domain.Types
import           Domain.Validation        (normalizeMerchant)
import           Persistence.DB
import           Server.Demo              (resetDemo)

type API =
       "api" :> "state" :> Get '[JSON] Value
  :<|> "api" :> "preview" :> ReqBody '[JSON] PatternReq :> Post '[JSON] Value
  :<|> "api" :> "decisions" :> ReqBody '[JSON] DecideReq :> Post '[JSON] Value
  :<|> "api" :> "undo" :> Post '[JSON] Value
  :<|> "api" :> "demo" :> "reset" :> Post '[JSON] Value
  :<|> Raw

newtype PatternReq = PatternReq Text

instance FromJSON PatternReq where
  parseJSON = withObject "PatternReq" $ \o -> PatternReq <$> o .: "pattern"

data DecideReq = DecideReq Text Text

instance FromJSON DecideReq where
  parseJSON = withObject "DecideReq" $ \o ->
    DecideReq <$> o .: "pattern" <*> o .: "category"

data ServerConfig = ServerConfig
  { scPort      :: Int
  , scStaticDir :: FilePath
  , scDemo      :: Bool
  }

-- | SQLite connections are not safe for concurrent use, and warp serves
-- requests concurrently, so every handler takes the connection through one
-- lock. The workload is one person reviewing; contention is not a concern.
app :: ServerConfig -> MVar Connection -> Application
app cfg lock = serve (Proxy :: Proxy API) server
  where
    withConn :: (Connection -> IO a) -> Handler a
    withConn f = liftIO (withMVar lock f)

    server =
           withConn (stateJson cfg)
      :<|> previewH
      :<|> decideH
      :<|> undoH
      :<|> resetH
      :<|> serveDirectoryWith staticSettings

    previewH (PatternReq raw) = withConn $ \conn ->
      previewPattern conn raw Uncategorized >>= \case
        Left e  -> pure (object ["ok" .= False, "error" .= ruleErrorJson raw e])
        Right p -> pure (previewJson p)

    decideH (DecideReq raw catTxt) = do
      cat <- case parseCategory catTxt of
        Right Uncategorized -> reject "uncategorized is the absence of a decision"
        Right c             -> pure c
        Left e              -> reject e
      rule <- either (reject . renderRuleError) pure (mkRule raw cat)
      withConn $ \conn -> do
        d <- decide conn rule
        st <- stateJson cfg conn
        pure (object ["decision" .= decisionJson d, "state" .= st])

    undoH = withConn $ \conn -> do
      r <- undoLast conn
      st <- stateJson cfg conn
      pure $ object
        [ "undone"   .= fmap (decisionJson . fst) r
        , "reverted" .= maybe 0 snd r
        , "state"    .= st
        ]

    resetH
      | not (scDemo cfg) = throwError err404
      | otherwise = withConn $ \conn -> do
          today <- utctDay <$> getCurrentTime
          resetDemo conn today
          stateJson cfg conn

    -- The built frontend, with / resolving to index.html.
    staticSettings = (defaultWebAppSettings (scStaticDir cfg))
      { ssIndices = [unsafeToPiece "index.html"] }

    reject :: Text -> Handler a
    reject msg = throwError err422
      { errBody = encode (object ["error" .= msg])
      , errHeaders = [("Content-Type", "application/json")]
      }

runServer :: ServerConfig -> Connection -> IO ()
runServer cfg conn = do
  lock <- newMVar conn
  putStrLn ("ledger review on http://localhost:" <> show (scPort cfg)
            <> (if scDemo cfg then "  (demo: synthetic data)" else ""))
  run (scPort cfg) (app cfg lock)

-- ---------------------------------------------------------------------------
-- JSON shapes
-- ---------------------------------------------------------------------------

stateJson :: ServerConfig -> Connection -> IO Value
stateJson cfg conn = do
  rows <- reviewRows conn
  lastD <- lastDecision conn
  let queue = groupQueue rows
      days = map rvDay rows
      filed = length (filter ((/= Uncategorized) . rvCategory) rows)
  pure $ object
    [ "demo"       .= scDemo cfg
    , "categories" .= [ categoryJson i c | (i, c) <- zip [1 :: Int ..] selectable ]
    , "queue"      .= map groupJson queue
    , "totals"     .= object
        [ "items"          .= length rows
        , "filed"          .= filed
        , "openItems"      .= (length rows - filed)
        , "openMerchants"  .= length queue
        ]
    , "period"     .= object
        [ "from" .= (if null days then Nothing else Just (show (minimum days)))
        , "to"   .= (if null days then Nothing else Just (show (maximum days)))
        ]
    , "lastDecision" .= fmap decisionJson lastD
    ]
  where
    selectable = filter (/= Uncategorized) allCategories

categoryJson :: Int -> Category -> Value
categoryJson key c = object
  [ "id" .= renderCategory c, "label" .= categoryLabel c, "key" .= key ]

moneyJson :: Cents -> Value
moneyJson c@(Cents n) = object
  [ "cents"     .= n
  , "magnitude" .= renderMagnitude c
  , "direction" .= (if n < 0 then "out" else "in" :: Text)
  ]

rowJson :: ReviewRow -> Value
rowJson r = object
  [ "id"       .= (let TransactionId t = rvId r in t)
  , "account"  .= rvAccount r
  , "date"     .= show (rvDay r)
  , "amount"   .= moneyJson (rvAmount r)
  , "merchant" .= rvMerchant r
    -- The normalized form the server groups and matches on, so the browser
    -- never has to re-derive it (and can never derive it differently).
  , "key"      .= normalizeMerchant (rvMerchant r)
  , "category" .= renderCategory (rvCategory r)
  ]

groupJson :: MerchantGroup -> Value
groupJson g = object
  [ "key"   .= mgKey g
  , "count" .= length (mgRows g)
  , "total" .= moneyJson (mgTotal g)
  , "rows"  .= map rowJson (mgRows g)
  ]

previewJson :: Preview -> Value
previewJson p = object
  [ "ok"        .= True
  , "needle"    .= ruleNeedle (pvRule p)
  , "wouldFile" .= map rowJson (pvWouldFile p)
  , "merchants" .= [ object [ "key" .= mhKey h, "count" .= mhCount h
                            , "total" .= moneyJson (mhTotal h) ]
                   | h <- pvMerchants p ]
  , "leftAlone" .= map rowJson (pvLeftAlone p)
  , "shadowed"  .= map rowJson (pvShadowed p)
  ]

decisionJson :: Decision -> Value
decisionJson d = object
  [ "id"       .= dcId d
  , "needle"   .= ruleNeedle (dcRule d)
  , "category" .= renderCategory (ruleCategory (dcRule d))
  , "rows"     .= dcRows d
  ]

-- | A rejected pattern is an ordinary state of the editor, not a failure, so
-- it comes back as data with a stable code the screen can design around.
ruleErrorJson :: Text -> RuleError -> Value
ruleErrorJson raw e = object
  [ "code"    .= (case e of { EmptyNeedle -> "empty"; NeedleAllDigits _ -> "all-digits" } :: Text)
  , "message" .= renderRuleError e
  , "pattern" .= raw
  ]
