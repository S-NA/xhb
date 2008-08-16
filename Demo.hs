import Data.Binary.Put
import Foreign.C.String
import Control.Concurrent.STM
import Data.Word

import qualified Data.ByteString.Lazy as BS

import qualified XHB.Connection as X
import qualified XHB.Connection.Open as X
import qualified XHB.Connection.Types as X
import qualified XHB.Shared as X

import qualified XHB.Gen.Xproto.Types as X
import XHB.Gen.Xproto

import System.IO

main = do
  h <- X.openMac

  hSetBuffering h NoBuffering

  connectionM <- X.mkConnection h

  case connectionM of
    Nothing -> putStrLn "failed to get connection"
    Just c -> demo c

demo :: X.Connection -> IO ()
demo c = do

  -- send two requests
  listReceipt <- listExtensions c
  ssReceipt <- getScreenSaver c

  -- create a window
  wid <- X.newResource c
  createWindow c $ demoCreateWindowReq c wid
  mapWindow c wid  

  -- process first request
  replyOrError <- X.getReply listReceipt
  case replyOrError of
    Left e -> putStrLn $ "error in extensions request" ++ showError e
    Right listRep -> printExtReply listRep

  -- process second request
  replyOrError <- X.getReply ssReceipt
  case replyOrError of
    Left e -> putStrLn $ "error in screen saver request" ++ showError e
    Right ssRep -> printSSRep ssRep

  putStrLn ""
  putStrLn "Press any key to continue"
  hSetBuffering stdin NoBuffering
  getChar
  putStrLn ""

printExtReply :: X.ListExtensionsReply -> IO ()
printExtReply r =
    let names = map strToString (X.names_ListExtensionsReply r)
    in sequence_ $ map putStrLn $ "" : names

printSSRep :: X.GetScreenSaverReply -> IO ()
printSSRep r = sequence_ $ map putStrLn
  [""
  ,"Screen saver info:"
  ," Interval: " ++ show (X.interval_GetScreenSaverReply r)
  ," Timeout: " ++ show (X.timeout_GetScreenSaverReply r)
  ]

-- this could be in a library somewhere
strToString :: X.STR -> String
strToString = map castCCharToChar . X.name_STR

demoCreateWindowReq :: X.Connection -> X.WINDOW -> X.CreateWindow
demoCreateWindowReq c w
    = X.MkCreateWindow
      0
      w
      (getRoot c)
      0
      0
      100
      100
      5
      0
      0
      (X.toValueParam ([] :: [(Integer,Word32)]))

-- errors are returned as bytestrings, currently
showError :: X.RawError -> String
showError = show . BS.unpack

getRoot :: X.Connection -> X.WINDOW
getRoot = X.root_SCREEN . head . X.roots_Setup . X.conf_setup . X.conn_conf
