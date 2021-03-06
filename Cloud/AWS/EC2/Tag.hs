{-# LANGUAGE FlexibleContexts #-}

module Cloud.AWS.EC2.Tag
    ( describeTags
    , createTags
    , deleteTags
    ) where

import Data.Text (Text)
import Data.Conduit
import Control.Applicative

import Cloud.AWS.EC2.Internal
import Cloud.AWS.EC2.Types
import Cloud.AWS.EC2.Query
import Cloud.AWS.Lib.Parser

describeTags
    :: (MonadResource m, MonadBaseControl IO m)
    => [Filter] -- ^ Filters
    -> EC2 m (ResumableSource m Tag)
describeTags filters =
    ec2QuerySource "DescribeTags" params $ itemConduit "tagSet" $
        Tag
        <$> getT "resourceId"
        <*> getT "resourceType"
        <*> getT "key"
        <*> getT "value"
  where
    params = [filtersParam filters]

createTags
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ ResourceId (instance-id, image-id,..)
    -> [(Text, Text)] -- ^ (Key, Value)
    -> EC2 m Bool
createTags rids kvs =
    ec2Query "CreateTags" params $ getT "return"
  where
    params =
        [ "ResourceId" |.#= rids
        , "Tag" |.#. map tagParams kvs
        ]
    tagParams (k, v) =
        [ "Key" |= k
        , "Value" |= v
        ]

deleteTags
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ ResourceId (instance-id, image-id,..)
    -> [ResourceTag]
    -> EC2 m Bool
deleteTags rids tags =
    ec2Query "DeleteTags" params $ getT "return"
  where
    params =
        [ "ResourceId" |.#= rids
        , "Tag" |.#. map tagParams tags
        ]
    tagParams tag =
        [ "Key" |= resourceTagKey tag
        , "Value" |=? resourceTagValue tag
        ]
