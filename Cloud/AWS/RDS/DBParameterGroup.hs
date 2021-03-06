{-# LANGUAGE FlexibleContexts, RecordWildCards #-}

module Cloud.AWS.RDS.DBParameterGroup
    ( describeDBParameterGroups
    , createDBParameterGroup
    , deleteDBParameterGroup
    , describeDBParameters
    , modifyDBParameterGroup
    , resetDBParameterGroup
    , describeDBEngineVersions
    , describeEngineDefaultParameters
    ) where

import Control.Applicative ((<$>), (<*>))
import Data.Conduit (Consumer, MonadBaseControl, MonadResource, MonadThrow)
import Data.Text (Text)
import Data.XML.Types (Event)

import Cloud.AWS.Lib.Parser (getT, element, elementM)
import Cloud.AWS.Lib.Query ((|=), (|=?), (|.#.))
import Cloud.AWS.RDS.Internal (RDS, rdsQuery, rdsQueryOnlyMetadata, elements, elements')
import Cloud.AWS.RDS.Types hiding (Event)

describeDBParameterGroups
    :: (MonadBaseControl IO m, MonadResource m)
    => Maybe Text -- ^ DBParameterGroupName
    -> Maybe Text -- ^ Marker
    -> Maybe Int -- ^ MaxRecords
    -> RDS m [DBParameterGroup]
describeDBParameterGroups name marker maxRecords =
    rdsQuery "DescribeDBParameterGroups" params $
        elements "DBParameterGroup" dbParameterGroupSink
  where
    params =
        [ "DBParameterGroupName" |=? name
        , "Marker" |=? marker
        , "MaxRecords" |=? maxRecords
        ]

dbParameterGroupSink
    :: MonadThrow m
    => Consumer Event m DBParameterGroup
dbParameterGroupSink = DBParameterGroup
    <$> getT "DBParameterGroupFamily"
    <*> getT "Description"
    <*> getT "DBParameterGroupName"

createDBParameterGroup
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ DBParameterGroupFamily
    -> Text -- ^ DBParameterGroupName
    -> Text -- ^ Description
    -> RDS m DBParameterGroup
createDBParameterGroup family name desc =
    rdsQuery "CreateDBParameterGroup" params $
        element "DBParameterGroup" dbParameterGroupSink
  where
    params =
        [ "DBParameterGroupFamily" |= family
        , "DBParameterGroupName" |= name
        , "Description" |= desc
        ]

deleteDBParameterGroup
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ DBParameterGroupName
    -> RDS m ()
deleteDBParameterGroup name =
    rdsQueryOnlyMetadata "DeleteDBParameterGroup"
        ["DBParameterGroupName" |= name]

describeDBParameters
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ DBParameterGroupName
    -> Maybe Text -- ^ Marker
    -> Maybe Int -- ^ MaxRecords
    -> Maybe Text -- ^ Source
    -> RDS m (Maybe Text, [Parameter]) -- ^ (Marker, Parameters)
describeDBParameters name marker maxRecords src =
    rdsQuery "DescribeDBParameters" params $ (,)
        <$> getT "Marker"
        <*> elements "Parameter" parameterSink
  where
    params =
        [ "DBParameterGroupName" |= name
        , "Marker" |=? marker
        , "MaxRecords" |=? maxRecords
        , "Source" |=? src
        ]

parameterSink
    :: MonadThrow m
    => Consumer Event m Parameter
parameterSink = Parameter
    <$> getT "ParameterValue"
    <*> getT "DataType"
    <*> getT "Source"
    <*> getT "IsModifiable"
    <*> getT "Description"
    <*> getT "ApplyType"
    <*> getT "AllowedValues"
    <*> getT "ParameterName"
    <*> getT "MinimumEngineVersion"

modifyDBParameterGroup
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ DBParameterGroupName
    -> [ModifyParameter] -- ^ Parameters
    -> RDS m Text
modifyDBParameterGroup name parameters =
    rdsQuery "ModifyDBParameterGroup" params $
        getT "DBParameterGroupName"
  where
    params =
        [ "DBParameterGroupName" |= name
        , "Parameters.member" |.#.
            map modifyParameterParams parameters
        ]
    modifyParameterParams ModifyParameter{..} =
        [ "ParameterName" |= modifyParameterName
        , "ParameterValue" |= modifyParameterValue
        , "ApplyMethod" |= modifyParameterApplyMethod
        ]

resetDBParameterGroup
    :: (MonadBaseControl IO m, MonadResource m)
    => Text
    -> ResetParameterRequest
    -> RDS m Text
resetDBParameterGroup name req =
    rdsQuery "ResetDBParameterGroup" params $
        getT "DBParameterGroupName"
  where
    params =
        [ "DBParameterGroupName" |= name
        ] ++ reqParams req
    reqParams ResetAllParameters =
        [ "ResetAllParameters" |= True ]
    reqParams (ResetParameters parameters) =
        [ "Parameters.member" |.#.
            map resetParameterParams parameters
        , "ResetAllParameters" |= False
        ]
    resetParameterParams ResetParameter{..} =
        [ "ParameterName" |= resetParameterName
        , "ApplyMethod" |= resetParameterApplyMethod
        ]

describeDBEngineVersions
    :: (MonadBaseControl IO m, MonadResource m)
    => Maybe Text -- ^ DBParameterGroupFamily
    -> Maybe Bool -- ^ DefaultOnly
    -> Maybe Text -- ^ Engine
    -> Maybe Text -- ^ EngineVersion
    -> Maybe Bool -- ^ ListSupportedCharacterSets
    -> Maybe Text -- ^ Marker
    -> Maybe Int -- ^ MaxRecords
    -> RDS m [DBEngineVersion]
describeDBEngineVersions family only engine ver list marker maxRec =
    rdsQuery "DescribeDBEngineVersions" params $
        elements "DBEngineVersion" dbEngineVersionSink
  where
    params =
        [ "DBParameterGroupFamily" |=? family
        , "DefaultOnly" |=? only
        , "Engine" |=? engine
        , "EngineVersion" |=? ver
        , "ListSupportedCharacterSets" |=? list
        , "Marker" |=? marker
        , "MaxRecords" |=? maxRec
        ]

dbEngineVersionSink
    :: MonadThrow m
    => Consumer Event m DBEngineVersion
dbEngineVersionSink = DBEngineVersion
    <$> getT "DBParameterGroupFamily"
    <*> getT "Engine"
    <*> elements' "SupportedCharacterSets" "CharacterSet" characterSetSink
    <*> getT "DBEngineDescription"
    <*> elementM "DefaultCharacterSet" characterSetSink
    <*> getT "EngineVersion"
    <*> getT "DBEngineVersionDescription"

characterSetSink
    :: MonadThrow m
    => Consumer Event m CharacterSet
characterSetSink = CharacterSet
    <$> getT "CharacterSetName"
    <*> getT "CharacterSetDescription"

describeEngineDefaultParameters
    :: (MonadBaseControl IO m, MonadResource m)
    => Text -- ^ DBparameterGroupFamily
    -> Maybe Text -- ^ Marker
    -> Maybe Int -- ^ MaxRecords
    -> RDS m (Maybe Text, EngineDefaults) -- ^ (Marker, EngineDefaults)
describeEngineDefaultParameters family marker maxRecords =
    rdsQuery "DescribeEngineDefaultParameters" params $
        element "EngineDefaults" $ (,)
            <$> getT "Marker"
            <*> (EngineDefaults
                <$> getT "DBParameterGroupFamily"
                <*> elements "Parameter" parameterSink
                )
  where
    params =
        [ "DBParameterGroupFamily" |= family
        , "Marker" |=? marker
        , "MaxRecords" |=? maxRecords
        ]
