module Data.HashMap.Strict.Extended
  ( module M,
    fromListOn,
    groupOn,
    groupOnNE,
    differenceOn,
    insertWithM,
    isInverseOf,
    unionWithM,
    unionsAll,
    homogenise,
  )
where

import Control.Monad (foldM)
import Data.Foldable qualified as F
import Data.Function (on)
import Data.HashMap.Strict as M
import Data.HashSet (HashSet)
import Data.HashSet qualified as S
import Data.Hashable (Hashable)
import Data.List qualified as L
import Data.List.NonEmpty (NonEmpty (..))
import Prelude

fromListOn :: Hashable k => (v -> k) -> [v] -> HashMap k v
fromListOn f = M.fromList . Prelude.map (\v -> (f v, v))

-- | Given a 'Foldable' sequence of values and a function that extracts a key from each value,
-- returns a 'HashMap' that maps each key to a list of all values in the sequence for which the
-- given function produced it.
--
-- >>> groupOn (take 1) ["foo", "bar", "baz"]
-- fromList [("f", ["foo"]), ("b", ["bar", "baz"])]
groupOn :: (Hashable k, Foldable t) => (v -> k) -> t v -> HashMap k [v]
groupOn f = fmap F.toList . groupOnNE f

groupOnNE ::
  (Hashable k, Foldable t) => (v -> k) -> t v -> HashMap k (NonEmpty v)
groupOnNE f =
  Prelude.foldr
    (\v -> M.alter (Just . (v :|) . maybe [] F.toList) (f v))
    M.empty

differenceOn ::
  (Hashable k, Foldable t) => (v -> k) -> t v -> t v -> HashMap k v
differenceOn f = M.difference `on` (fromListOn f . F.toList)

-- | Monadic version of https://hackage.haskell.org/package/unordered-containers-0.2.18.0/docs/Data-HashMap-Internal.html#v:insertWith
insertWithM :: (Monad m, Hashable k) => (v -> v -> m v) -> k -> v -> HashMap k v -> m (HashMap k v)
insertWithM f k v m =
  sequence $
    M.insertWith
      ( \a b -> do
          x <- a
          y <- b
          f x y
      )
      k
      (return v)
      (return <$> m)

-- | Determines whether the left-hand-side and the right-hand-side are inverses of each other.
--
-- More specifically, for two maps @A@ and @B@, 'isInverseOf' is satisfied when both of the
-- following are true:
-- 1. @∀ key ∈ A. A[key] ∈  B ∧ B[A[key]] == key@
-- 2. @∀ key ∈ B. B[key] ∈  A ∧ A[B[key]] == key@
isInverseOf ::
  (Hashable k, Hashable v) => HashMap k v -> HashMap v k -> Bool
lhs `isInverseOf` rhs = lhs `invertedBy` rhs && rhs `invertedBy` lhs
  where
    invertedBy ::
      forall s t.
      (Eq s, Hashable t) =>
      HashMap s t ->
      HashMap t s ->
      Bool
    a `invertedBy` b = and $ do
      (k, v) <- M.toList a
      pure $ M.lookup v b == Just k

-- | The union of two maps.
--
-- If a key occurs in both maps, the provided function (first argument) will be
-- used to compute the result. Unlike 'unionWith', 'unionWithM' performs the
-- computation in an arbitratry monad.
unionWithM ::
  (Monad m, Hashable k) =>
  (k -> v -> v -> m v) ->
  HashMap k v ->
  HashMap k v ->
  m (HashMap k v)
unionWithM f m1 m2 = foldM step m1 (M.toList m2)
  where
    step m (k, new) = case M.lookup k m of
      Nothing -> pure $ M.insert k new m
      Just old -> do
        combined <- f k new old
        pure $ M.insert k combined m

-- | Like 'M.unions', but keeping all elements in the result.
unionsAll ::
  (Hashable k, Foldable t) => t (HashMap k v) -> HashMap k (NonEmpty v)
unionsAll = F.foldl' (\a b -> M.unionWith (<>) a (fmap (:| []) b)) M.empty

-- | Homogenise maps, such that all maps range over the full set of
-- keys, inserting a default value as needed.
homogenise :: Hashable a => b -> [HashMap a b] -> (HashSet a, [HashMap a b])
homogenise defaultValue maps =
  let ks = S.unions $ L.map M.keysSet maps
      defaults = M.fromList [(k, defaultValue) | k <- S.toList ks]
   in (ks, L.map (<> defaults) maps)
