{-# LANGUAGE FlexibleContexts #-}

module Cloud.AWS.RDS.Event
    ( describeEvents
    , describeEventCategories
    ) where

import Control.Applicative ((<$>), (<*>))
import Data.Conduit
import Data.Text (Text)
import Data.Time (UTCTime)
import qualified Data.XML.Types as XML

import Cloud.AWS.Lib.Parser
import Cloud.AWS.Lib.Query
import Cloud.AWS.RDS.Internal
import Cloud.AWS.RDS.Types
import Debug.Trace

describeEvents
    :: (MonadBaseControl IO m, MonadResource m)
    => Maybe Text -- ^ SourceIdentifier
    -> Maybe SourceType -- ^ SourceType
    -> Maybe Int -- ^ Duration
    -> Maybe UTCTime -- ^ StartTime
    -> Maybe UTCTime -- ^ EndTime
    -> [Text] -- ^ EventCategories.member
    -> Maybe Text -- ^ Marker
    -> Maybe Int -- ^ MaxRecords
    -> RDS m [Event]
describeEvents sid stype d start end categories marker maxRecords =
    rdsQuery "DescribeEvents" params $
        elements "Event" eventSink
  where
    params =
        [ "SourceIdentifier" |=? sid
        , "SourceType" |=? stype
        , "Duration" |=? d
        , "StartTime" |=? start
        , "EndTime" |=? end
        , "EventCategories" |.+ "member" |.#= categories
        , "Marker" |=? marker
        , "MaxRecords" |=? maxRecords
        ]

eventSink
    :: MonadThrow m
    => Consumer XML.Event m Event
eventSink = Event
    <$> do
        a <- getT "Message"
        traceShow a $ return a
    <*> getT "SourceType"
    <*> elements' "EventCategories" "EventCategory" text
    <*> getT "Date"
    <*> getT "SourceIdentifier"

describeEventCategories
    :: (MonadBaseControl IO m, MonadResource m)
    => Maybe SourceType -- ^ SourceType
    -> RDS m [EventCategoriesMap]
describeEventCategories stype =
    rdsQuery "DescribeEventCategories" params $
        elements' "EventCategoriesMapList" "EventCategoriesMap" eventCategoriesMapSink
  where
    params = [ "SourceType" |=? stype ]

eventCategoriesMapSink
    :: MonadThrow m
    => Consumer XML.Event m EventCategoriesMap
eventCategoriesMapSink = EventCategoriesMap
    <$> getT "SourceType"
    <*> elements' "EventCategories" "EventCategory" text
