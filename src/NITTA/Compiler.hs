{-# LANGUAGE BangPatterns           #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE LambdaCase             #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE PartialTypeSignatures  #-}
{-# LANGUAGE RecordWildCards        #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE StandaloneDeriving     #-}
{-# LANGUAGE UndecidableInstances   #-}
{-# OPTIONS -Wall -fno-warn-missing-signatures #-}

module NITTA.Compiler
  ( naive
  , bindAll
  , bindAllAndNaiveSelects
  , effectVar2act
  )
where

import           Data.List        (find, intersect, nub, sortBy)
import qualified Data.Map         as M
import           Data.Maybe       (catMaybes, isJust)
import           NITTA.BusNetwork
import           NITTA.Flows
import           NITTA.Types
import           NITTA.Utils

import           Debug.Trace


bindAll pu alg = fromRight undefined $ foldl nextBind (Right pu) alg
  where
    nextBind (Right pu') fb = bind fb pu'
    nextBind (Left r) _     = error r

bindAllAndNaiveSelects pu0 alg = naive' $ bindAll pu0 alg
  where
    naive' pu
      | var:_ <- options pu =
          naive'
          -- $ trace (concatMap ((++ "\n") . show) $ elems $ frMemory pu)
          $ select pu $ effectVar2act var
      | otherwise = pu

-- manualSteps pu acts = foldl (\pu' act -> step pu' act) pu acts

effectVar2act EffectOpt{ eoAt=TimeConstrain{..}, .. } = EffectAct eoEffect $ Event tcFrom tcDuration




timeSplitOptions ControlModel{..} availableVars
  = let splits = filter isSplit $ (\(Parallel ss) -> ss) $ controlFlow
    in filter isAvalilable splits
  where
    isAvalilable (Split c vs _) = all (`elem` availableVars) $ c : vs
    isAvalilable _              = error "selectSplit internal error."

splitProcess Fork{..} (Split _cond _is branchs)
  = let ControlModel{..} = controlModel
        t = tick $ process net
        f : fs = map (\SplitBranch{..} -> Fork
                       { net=setTime t{ tag=sTag } net
                       , controlModel=controlModel{ controlFlow=sControlFlow }
                       , timeTag=sTag
                       , forceInputs=sForceInputs
                       }
                     ) branchs
        usedVariables' = nub $ concatMap (variables . sControlFlow) branchs
    in Forks{ current=f
            , remains=fs
            , completed=[]
            , merge=f{ controlModel=controlModel
                                    { usedVariables=usedVariables' ++ usedVariables
                                    }
                     }
            }
splitProcess _ _ = error "Can't split process."




threshhold = 2

isOver Forks{..} = isOver current && null remains
isOver Fork{..}
  = let opts = sensibleOptions $ filterByControlModel controlModel $ options net
        bindOpts = bindingOptions net
    in null opts && null bindOpts


naive !f@Forks{..}
  = let current'@Fork{ net=net' } = naive current
        t = maximum $ map (tick . process . net) $ current' : completed
        parallelSteps = concatMap
          (\Fork{ net=n
                , timeTag=forkTag
                } -> filter (\Step{ sTime=Event{..} } -> forkTag == (tag eStart)
                            ) $ steps $ process n
          ) completed
    in case (isOver current', remains) of
         (True, r:rs) -> f{ current=r, remains=rs, completed=current' : completed }
         (True, _)    -> let net''@BusNetwork{ bnProcess=p }
                               = setTime t{ tag=timeTag merge } net'
                         in merge{ net=net''{ bnProcess=snd $ modifyProcess p $ do
                                                mapM_ (\Step{..} -> add sTime sDesc) parallelSteps
                                            }
                                 }
         (False, _)   -> f{ current=current' }


naive !f@Fork{..}
  = let opts = sensibleOptions $ filterByControlModel controlModel $ options net
        bindOpts = bindingOptions net
        splits = timeSplitOptions controlModel availableVars
    in case (splits, opts, bindOpts) of
         ([], [], [])    -> trace "over" f
         (_, _o : _, _)  | length opts >= threshhold -> afterStep
         (_bo, _, _ : _) -> f{ net=autoBind net }
         (_, _o : _, _)  -> afterStep
         (s : _, _, _)   -> trace ("split: " ++ show s) $ splitProcess f s
  where
    availableVars = nub $ concatMap (M.keys . toPush) $ options net
    afterStep
      = case sortBy (\a b -> start a `compare` start b)
             $ sensibleOptions $ filterByControlModel controlModel $ options net of
        v:_ -> let act = option2action v
                   cm' = foldl controlModelStep controlModel
                         $ map fst $ filter (isJust . snd) $ M.assocs $ taPush act
               in trace ("step: " ++ show act)
                  f{ net=select net act
                   , controlModel=cm'
                   }
        _   -> error "No variants!"
    start = tcFrom . toPullAt
    -- mostly mad implementation
    option2action TransportOpt{ toPullAt=TimeConstrain{..}, ..}
      = TransportAct
      -- = trace (">" ++ show forceInputs) $ TransportAct
        { taPullFrom=toPullFrom
        , taPullAt=Event tcFrom tcDuration
        , taPush=M.fromList $ map (\(v, o) -> ( v
                                              , case o of
                                                  Just o' -> Just $ tc2e o'
                                                  Nothing | v `elem` forceInputs -> Just $ tc2e opt
                                                  _ -> tc2e <$> o
                                              )
                            ) $ M.assocs toPush
        }
      where
        tc2e (title, TimeConstrain{ tcDuration=dur}) = (title, Event (tcFrom + tcDuration) dur)
        (_, event) : _ = catMaybes $ M.elems toPush
        opt = ("", event)



filterByControlModel controlModel opts
  = let cfOpts = controlModelOptions controlModel
    in map (\t@TransportOpt{..} -> t
             { toPush=M.fromList $ map (\(v, desc) -> (v, if v `elem` cfOpts
                                                          then desc
                                                          else Nothing)
                                       ) $ M.assocs toPush
             }) opts



sensibleOptions = filter $
  \TransportOpt{..} -> not $ null $ filter isJust $ M.elems toPush



data BindOption title v = BindOption
  { fb       :: FB v
  , puTitle  :: title
  , priority :: Maybe BindPriority
  } deriving (Show)

data BindPriority
  = Exclusive
  | Restless Int
  | Input Int
  -- Must be binded before a other, because otherwise can cause runtime error.
  | Critical
  deriving (Show, Eq)

instance Ord BindPriority where
  Critical `compare` _ = GT
  _ `compare` Critical = LT
  (Input    a) `compare` (Input    b) = a `compare` b -- чем больше, тем лучше
  (Input    _) `compare`  _           = GT
  (Restless _) `compare` (Input    _) = LT
  (Restless a) `compare` (Restless b) = b `compare` a -- чем меньше, тем лучше
  (Restless _) `compare`  _           = GT
  Exclusive `compare` Exclusive = EQ
  Exclusive `compare` _ = LT





autoBind net@BusNetwork{..} =
  let prioritized = sortBV $ map mkBV bOpts
  in case prioritized of
      (BindOption fb puTitle _) : _ -> trace ("bind: " ++ show fb ++ " " ++ show puTitle) $
                                       subBind fb puTitle net
      _                             -> error "Bind variants is over!"
  where
    bOpts = bindingOptions net
    mkBV (fb, titles) = prioritize $ BindOption fb titles Nothing
    sortBV = reverse . sortBy (\a b -> priority a `compare` priority b)

    mergedBOpts = foldl (\m (fb, puTitle) -> M.alter
                          (\case
                              Just puTitles -> Just $ puTitle : puTitles
                              Nothing -> Just [puTitle]
                          ) fb m
                   ) (M.fromList []) bOpts

    prioritize bv@BindOption{..}
      -- В настоящий момент данная операци приводит к тому, что часть FB перестают быть вычислимыми.
      -- | isCritical fb = bv{ priority=Just Critical }

      | dependency fb == []
      , pulls <- filter isPull $ optionsAfterBind bv
      , length pulls > 0
      = bv{ priority=Just $ Input $ sum $ map (length . variables) pulls}

      | Just (_variable, tcFrom) <- find (\(v, _) -> v `elem` variables fb) restlessVariables
      = bv{ priority=Just $ Restless $ fromEnum tcFrom }

      | length (mergedBOpts M.! fb) == 1
      = bv{ priority=Just Exclusive }

      | otherwise = bv

    restlessVariables = [ (variable, tcFrom)
      | TransportOpt{ toPullAt=TimeConstrain{..}, ..} <- options net
      , (variable, Nothing) <- M.assocs toPush
      ]

    optionsAfterBind BindOption{..} = case bind fb $ bnPus M.! puTitle of
      Right pu' -> filter (\(EffectOpt act _) -> act `optionOf` fb) $ options pu'
      _  -> []
      where
        act `optionOf` fb' = not $ null (variables act `intersect` variables fb')

    -- trace' vs = trace ("---------"++ show (restlessVariables)
               -- ++ "\n" ++ (concatMap (\v -> show v ++ "\n") vs)) vs
