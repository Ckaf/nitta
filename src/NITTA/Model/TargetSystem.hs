{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

{-|
Module      : NITTA.Model.TargetSystem
Description : Model of target system for synthesis and so on.
Copyright   : (c) Aleksandr Penskoi, 2019
License     : BSD3
Maintainer  : aleksandr.penskoi@gmail.com
Stability   : experimental
-}
module NITTA.Model.TargetSystem
-- TODO: rename to ModelState
    ( ModelState(..)
    , DataFlowGraph(..), fsToDataFlowGraph
    ) where

import           Control.Exception ( assert )
import qualified Data.List as L
import qualified Data.Set as S
import           GHC.Generics
import           NITTA.Intermediate.Functions ( reg)
import           NITTA.Intermediate.Functions
import           NITTA.Intermediate.Types
import           NITTA.Model.Networks.Bus
import           NITTA.Model.Problems
import           NITTA.Model.ProcessorUnits.Time
import           NITTA.Model.Types
import           NITTA.Utils
import           Debug.Trace


-- |Model of target unit, which is a main subject of synthesis process and
-- synthesis graph.
data ModelState u v x
    = ModelState
        { mUnit          :: u -- ^model of target unit
        , mDataFlowGraph :: DataFlowGraph v x -- ^whole application algorithm
        }
    deriving ( Generic )

instance WithFunctions (ModelState (BusNetwork tag v x t) v x) (F v x) where
    functions ModelState{ mUnit, mDataFlowGraph }
        = assert (S.fromList (functions mUnit) == S.fromList (functions mDataFlowGraph)) -- inconsistent ModelState
            $ functions mUnit

instance ( UnitTag tag, VarValTime v x t
        ) => BindProblem (ModelState (BusNetwork tag v x t) v x) tag v x where
    bindOptions ModelState{ mUnit }      = bindOptions mUnit
    bindDecision f@ModelState{ mUnit } d = f{ mUnit=bindDecision mUnit d }

instance ( UnitTag tag, VarValTime v x t
        ) => DataflowProblem (ModelState (BusNetwork tag v x t) v x) tag v t
        where
    dataflowOptions ModelState{ mUnit }      = dataflowOptions mUnit
    dataflowDecision f@ModelState{ mUnit } d = f{ mUnit=dataflowDecision mUnit d }

instance ( UnitTag tag, VarValTime v x t
        ) => RefactorProblem (ModelState (BusNetwork tag v x t) v x) v x where
    refactorOptions ModelState{ mUnit } = refactorOptions mUnit

    refactorDecision ModelState{ mUnit, mDataFlowGraph } r@ResolveDeadlock{}
        = ModelState
            { mDataFlowGraph=refactorDecision mDataFlowGraph r
            , mUnit=refactorDecision mUnit r
            }

    refactorDecision ModelState{ mUnit, mDataFlowGraph } bl@BreakLoop{}
        = ModelState
            { mDataFlowGraph=refactorDecision mDataFlowGraph bl
            , mUnit=refactorDecision mUnit bl
            }


-- |Data flow graph - intermediate representation of application algorithm.
-- Right now can be replaced by @[F v x]@, but for future features like
-- conduction statement, we don't do that.
data DataFlowGraph v x
    = DFLeaf (F v x)
    | DFCluster [ DataFlowGraph v x ]
    deriving ( Show, Generic )

instance Eq ( DataFlowGraph v x) where
    (DFCluster c1) == (DFCluster c2) = S.fromList (map show c1) == S.fromList (map show c2)
    (DFLeaf f1) == (DFLeaf f2) = f1 == f2
    _ == _ = False

instance ( Var v, Val x ) => Patch (DataFlowGraph v x) (v, v) where
    patch diff@(v, v') (DFCluster cluster) = let
            newReg = DFLeaf $ reg v [v']
            cluster' = map (patch diff) cluster
        in assert (all (\case DFLeaf _ -> True; _ -> False) cluster) -- patch DataFlowGraph with subclusters is not support
            $ DFCluster $ newReg : cluster'
    patch diff@(v, _) n@(DFLeaf f)
        | v `S.member` inputs f = DFLeaf $ patch diff f
        | otherwise = n

instance ( Var v ) => Variables (DataFlowGraph v x) v where
    variables (DFLeaf fb)   = variables fb
    variables (DFCluster g) = unionsMap variables g

instance WithFunctions (DataFlowGraph v x) (F v x) where
    functions (DFLeaf f)    = [ f ]
    functions (DFCluster g) = concatMap functions g

instance ( Var v, Val x
        ) => RefactorProblem (DataFlowGraph v x) v x where
    refactorOptions dfg = trace (show $ filterAddSub [] (dataFlowGraphToFs dfg)) []

    refactorDecision dfg r@ResolveDeadlock{} = let
            ( buffer, diff ) = prepareBuffer r
            fs' = buffer : map (patch diff) (functions dfg)
        in fsToDataFlowGraph fs'
    refactorDecision (DFCluster leafs) bl@BreakLoop{} = let
            origin = recLoop bl
        in DFCluster
            $ DFLeaf (recLoopIn bl){ funHistory=[origin] }
            : DFLeaf (recLoopOut bl){ funHistory=[origin] }
            : ( leafs L.\\ [ DFLeaf origin ] )

    refactorDecision _ _ = error "DataFlowGraph "

instance ( UnitTag tag, VarValTime v x t
         ) => SynthesisProblem (ModelState (BusNetwork tag v x t) v x) tag v x t where
    synthesisOptions m@ModelState{ mUnit } = concat
        [ map generalizeBinding $ bindOptions m
        , map generalizeDataflow $ dataflowOptions mUnit
        , map Refactor $ refactorOptions m
        ]

    synthesisDecision m (Binding f tag) = bindDecision m $ Bind f tag
    synthesisDecision m@ModelState{ mUnit } (Dataflow src trg) = m{ mUnit=dataflowDecision mUnit $ DataflowSt src trg }
    synthesisDecision m (Refactor d) = refactorDecision m d


-- |Convert @[ F v x ]@ to 'DataFlowGraph'.
fsToDataFlowGraph alg = DFCluster $ map DFLeaf alg

-- |Convert 'DataFlowGraph' to @[ F v x ]@.
dataFlowGraphToFs (DFCluster leafs) = map
    (\case
        DFLeaf f -> f
        _        -> error "Data flow graph structure error"
    )
    leafs
dataFlowGraphToFs _ = error "Data flow graph structure error"

filterAddSub state []      = let
           newState = filterAddSub state (concatMap snd state)
       in
           if state == newState
              then state
              else filterAddSub state (concatMap snd newState)

filterAddSub state (f:fs)
    | Just Add{} <- castF f = filterAddSub (writeToState state f) fs
    | Just Sub{} <- castF f = filterAddSub (writeToState state f) fs
    | otherwise             = filterAddSub (notMatchedF state f) fs
        where
            notMatchedF state' f' = (S.empty, [f']) : state'

            writeToState [] f = [(inputs f, [f])]
            writeToState state f = let
                    (v1':v2':_) = S.toList $ inputs f
                    res' = outputs f

                in
                    case L.partition (\(s, fList) -> not $ S.null $ S.intersection s res' ) state of
                        ([], last) -> (S.fromList [v1', v2'], [f]) : last
                        (filtered, last) -> (map (\(s, fList) -> (S.union (s S.\\ res') (S.fromList [v1', v2']) , f : fList)) filtered) ++ last



