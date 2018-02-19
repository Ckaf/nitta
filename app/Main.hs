{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE UndecidableInstances  #-}

module Main where

import           Control.Monad
import qualified Data.Array               as A
import           Data.Default
import qualified Data.Map                 as M
import           Data.Maybe
import           Data.Proxy
import qualified Data.String.Utils        as U
import           Data.Typeable
import           Debug.Trace
import           Network.Wai.Handler.Warp
import           NITTA.API
import           NITTA.BusNetwork
import           NITTA.Compiler
import           NITTA.Flows
import qualified NITTA.FunctionBlocks     as FB
import qualified NITTA.ProcessUnits.Accum as A
import qualified NITTA.ProcessUnits.Fram  as FR
import qualified NITTA.ProcessUnits.Shift as S
import qualified NITTA.ProcessUnits.SPI   as SPI
import           NITTA.TestBench
import           NITTA.Timeline
import           NITTA.Types
import           NITTA.Utils
import           System.FilePath.Posix    (joinPath)
import           Text.StringTemplate


nitta :: BusNetwork String String (TaggedTime String Int)
nitta = busNetwork 24
  [ ("fram1", PU def FR.Link{ FR.oe=Index 11, FR.wr=Index 10, FR.addr=map Index [9, 8, 7, 6] })
  , ("fram2", PU def FR.Link{ FR.oe=Index 5, FR.wr=Index 4, FR.addr=map Index [3, 2, 1, 0] })
  , ("shift", PU def S.Link{ S.work=Index 12, S.direction=Index 13, S.mode=Index 14, S.step=Index 15, S.init=Index 16, S.oe=Index 17 } )
  , ("accum", PU def A.Link{ A.init=Index 18, A.load=Index 19, A.neg=Index 20, A.oe=Index 21 } )
  , ("spi", PU def SPI.Link{ SPI.wr=Index 22, SPI.oe=Index 23
                           , SPI.start=Name "start", SPI.stop=Name "stop"
                           , SPI.mosi=Name "mosi", SPI.miso=Name "miso", SPI.sclk=Name "sclk", SPI.cs=Name "cs"
                           })
  ]


-- | Пример работы с ветвящимся временем.
--
-- - TODO: планирование вычислительного процесса (пропуск переменных, колизии потоков управления и
--   данных, привязок функциональных блоков).
-- - TODO: генерация машинного кода.
-- - TODO: генерация аппаратуры.
-- - TODO: testbench.
scheduledBush
  = let dataFlow = Stage
          [ Actor $ FB.framInput 0 $ O [ "cond", "cond'" ]
          , Actor $ FB.framInput 1 $ O [ "x1", "x2" ]
          , Actor $ FB.framOutput 2 $ I "cond'"
          , Paths "cond"
            [ (0, Stage [ Actor $ FB.reg (I "x1") $ O ["y1"], Actor $ FB.framOutput 10 $ I "y1" ])
            , (1, Stage [ Actor $ FB.reg (I "x2") $ O ["y2"], Actor $ FB.framOutput 11 $ I "y2" ])
            ]
          ]
        nitta' = bindAll (functionalBlocks dataFlow) nitta
        initialBranch = Branch nitta' (dataFlow2controlFlow dataFlow) Nothing []
        Branch{ topPU=pu } = foldl (\b _ -> naive def b) initialBranch $ replicate 50 ()
    in pu

-- | Пример работы с единым временем.
scheduledBranch
  = let alg = [ FB.framInput 3 $ O [ "a"
                                   , "d"
                                   ]
              , FB.framInput 4 $ O [ "b"
                                   , "c"
                                   , "e"
                                   ]
              , FB.reg (I "a") $ O ["x"]
              , FB.reg (I "b") $ O ["y"]
              , FB.reg (I "c") $ O ["z"]
              , FB.framOutput 5 $ I "x"
              , FB.framOutput 6 $ I "y"
              , FB.framOutput 7 $ I "z"
              , FB.framOutput 0 $ I "sum"
              , FB $ FB.Constant 42 $ O ["const"]
              , FB.framOutput 9 $ I "const"
              , FB.loop (O ["f"]) $ I "g"
              , FB $ FB.ShiftL (I "f") $ O ["g"]
              , FB $ FB.Add (I "d") (I "e") (O ["sum"])
              ]
        dataFlow = Stage $ map Actor alg
        nitta' = bindAll (functionalBlocks dataFlow) nitta
        initialBranch = Branch nitta' (dataFlow2controlFlow dataFlow) Nothing []
        Branch{ topPU=pu } = foldl (\b _ -> naive def b) initialBranch $ replicate 50 ()
    in pu

-- | Пример работы с единым временем.
scheduledBranchSPI
  = let alg = [ FB $ FB.Receive $ O ["a"] :: FB (Parcel String) String
              , FB $ FB.Send (I "b")
              , FB.reg (I "a") $ O ["b"]
              ]
        dataFlow = Stage $ map Actor alg
        nitta' = bindAll (functionalBlocks dataFlow) nitta
        initialBranch = Branch nitta' (dataFlow2controlFlow dataFlow) Nothing []
        Branch{ topPU=pu } = foldl (\b _ -> naive def b) initialBranch $ replicate 50 ()
    in pu

---------------------------------------------------------------------------------


main = do
  -- test scheduledBranch
  --   (def{ cntxVars=M.fromList []
  --       } :: Cntx String Int)
  -- test scheduledBranchSPI
  --   (def{ cntxVars=M.fromList [("b", [0])]
  --       , cntxInputs=M.fromList [("a", [1, 2, 3])]
  --       } :: Cntx String Int)
  -- simulateSPI 3
  putStrLn "Server start on 8080..."
  run 8080 app


test pu cntx = do
  timeline "resource/data.json" pu
  r <- testBench ".." (joinPath ["hdl", "gen"]) pu cntx
  if r then putStrLn "Success"
  else putStrLn "Fail"
  print "ok"


simulateSPI n = do
  mapM_ putStrLn $ take n $ map show $ FB.simulateAlg (def{ cntxVars=M.fromList [("b", [0])]
                                                          , cntxInputs=M.fromList [("a", [1, 2, 3])]
                                                          } :: Cntx String Int)
    [ FB $ FB.Receive $ O ["a"] :: FB (Parcel String) String
    , FB $ FB.Add (I "a") (I "b") (O ["c1", "c2"])
    , FB $ FB.Loop (O ["b"]) (I "c1")
    , FB $ FB.Send (I "c2")
    ]
  print "ok"



getPU puTitle net = fromMaybe (error "Wrong PU type!") $ castPU $ bnPus net M.! puTitle
