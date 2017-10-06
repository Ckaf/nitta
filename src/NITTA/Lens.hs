{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs                  #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE RecordWildCards        #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE StandaloneDeriving     #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE UndecidableInstances   #-}
{-# OPTIONS -Wall -fno-warn-missing-signatures #-}

module NITTA.Lens where

import           Control.Lens      hiding (at, (...))
import           Data.Default
import qualified Data.List         as L
import qualified Data.Map          as M
import           Data.Maybe
import qualified Data.String.Utils as S
import           Data.Typeable
import           NITTA.Types
import           Numeric.Interval  hiding (elem)



class HasLeftBound a b | a -> b where
  leftBound :: Lens' a b

class HasRightBound a b | a -> b where
  rightBound :: Lens' a b

class HasAvailable a b | a -> b where
  available :: Lens' a b

class HasDur a b | a -> b where
  dur :: Lens' a b

instance HasAvailable (TimeConstrain t) (Interval t) where
  available = lens tcAvailable $ \e s -> e{ tcAvailable=s }
instance HasDur (TimeConstrain t) (Interval t) where
  dur = lens tcDuration $ \e s -> e{ tcDuration=s }


instance ( Time t ) =>  HasLeftBound (Interval t) t where
  leftBound = lens inf $ \e s -> s ... sup e
instance ( Time t ) => HasDur (Interval t) t where
  dur = lens width $ \e s -> inf e ... (inf e + s)


class HasAt a b | a -> b where
  at :: Lens' a b

instance HasAt (Option (Network title) v t) (TimeConstrain t) where
  at = lens toPullAt $ \variant v -> variant{ toPullAt=v }
instance HasAt (Action (Network title) v t) (Interval t) where
  at = lens taPullAt $ \variant v -> variant{ taPullAt=v }
instance HasAt (Option Passive v t) (TimeConstrain t) where
  at = lens eoAt $ \variant v -> variant{ eoAt=v }
instance HasAt (Action Passive v t) (Interval t) where
  at = lens eaAt $ \variant v -> variant{ eaAt=v }


class HasTime a b | a -> b where
  time :: Lens' a b

instance HasTime (Process v t) t where
  time = lens nextTick $ \s v -> s{ nextTick=v }


instance ( Time t ) => HasDur (Action Passive v t) t where
  dur = at . dur



class HasStart a b | a -> b where
  start :: Lens' a b

-- instance HasStart (CurrentJob io v t) t where
--   start = lens cStart $ \c s -> c{ cStart=s }
instance HasStart (Action Passive v t) t where
  start = lens (inf . eaAt) undefined --  \s v -> s{ eaAt=(eaAt s) & start .~ v }



class HasEffect a b | a -> b where
  effect :: Lens' a b

instance HasEffect (Action Passive v t) (Effect v) where
  effect = lens eaEffect $ \s v -> s{ eaEffect=v }
