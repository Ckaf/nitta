{-# OPTIONS -Wall -fno-warn-missing-signatures -fno-warn-orphans #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-
Данный модуль реализует функции для генерации функциональных блоков.
-}
module NITTA.FunctionBlocksSpec where

import           Data.Default
import           Data.List               (nub)
import           NITTA.FunctionBlocks
import           NITTA.ProcessUnits.Fram
import           NITTA.Types
import           Test.QuickCheck


framDefSize = frSize (def :: Fram () ())
framAddrGen = choose (0, framDefSize - 1)


outputVarsGen = O <$> resize 3 (listOf1 $ vectorOf 3 $ elements ['a'..'z'])
inputVarGen = I <$> vectorOf 3 (elements ['a'..'z'])


uniqueVars fb = let vs = variables fb in length vs == length (nub vs)


instance Arbitrary (FramInput (Parcel String)) where
  arbitrary = suchThat (FramInput <$> framAddrGen <*> outputVarsGen) uniqueVars

instance Arbitrary (FramOutput (Parcel String)) where
  arbitrary = suchThat (FramOutput <$> framAddrGen <*> inputVarGen) uniqueVars

instance Arbitrary (Loop (Parcel String)) where
  arbitrary = suchThat (Loop <$> outputVarsGen <*> inputVarGen) uniqueVars

instance Arbitrary (Reg (Parcel String)) where
  arbitrary = suchThat (Reg <$> inputVarGen <*> outputVarsGen) uniqueVars

instance Arbitrary (Constant (Parcel String)) where
  arbitrary = suchThat (Constant <$> choose (10, 16) <*> outputVarsGen) uniqueVars
