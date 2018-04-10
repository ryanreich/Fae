module FaeServer.Fae where

import Blockchain.Fae.FrontEnd

import Control.Concurrent
import Control.Concurrent.STM

import Control.Monad
import Control.Monad.IO.Class
import Control.Monad.State
import Control.Monad.Trans.Class

import qualified Data.ByteString as B
import qualified Data.Serialize as S
import qualified Data.Map as Map

import FaeServer.Concurrency
import FaeServer.Git
import FaeServer.History
import FaeServer.Modules

import System.Directory
import System.Exit

runFae :: ThreadId -> TXQueueT IO ()
runFae mainTID = reThrow mainTID $ runFaeInterpretWithHistory $ 
  forever $ do
    txExecData <- readTXExecData
    reThrowExit mainTID (callerTID txExecData) $ runTXExecData mainTID txExecData

runTXExecData :: 
  (MonadIO m, MonadMask m) => 
  ThreadId -> TXExecData -> FaeInterpretWithHistoryT m ()
runTXExecData mainTID TXExecData{tx=tx@TX{..}, ..} = do
  dup <- gets $ Map.member txID . txStorageAndCounts
  when dup $ error $ "Duplicate transaction ID: " ++ show txID

  txCount <- recallHistory parentM
  liftIO $ writeModules mainFile modules txID
  lift $ interpretTX reward tx
  txResult <-
    if lazy
    then return $ "Transaction " ++ show txID
    else lift $ showTransaction txID
  if fake
  then liftIO gitClean
  else updateHistory txID txCount
  ioAtomically $ putTMVar resultVar txResult

runTXExecData mainTID View{..} = do
  void $ recallHistory parentM
  txResult <- lift $ showTransaction viewTXID
  ioAtomically $ putTMVar resultVar txResult

