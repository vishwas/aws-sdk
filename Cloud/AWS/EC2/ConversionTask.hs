{-# LANGUAGE FlexibleContexts, RecordWildCards #-}
module Cloud.AWS.EC2.ConversionTask
    ( describeConversionTasks
    , cancelConversionTask
    , importVolume
    , importInstance
    ) where

import Control.Applicative ((<$>), (<*>))
import Data.Conduit
import Data.Text (Text)
import Data.XML.Types (Event)

import Cloud.AWS.EC2.Internal
import Cloud.AWS.EC2.Query
import Cloud.AWS.EC2.Types
import Cloud.AWS.Lib.Parser

describeConversionTasks
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ ConversionTaskIds
    -> EC2 m (ResumableSource m ConversionTask)
describeConversionTasks ctids =
    ec2QuerySource "DescribeConversionTasks" params $
        itemConduit "conversionTasks" conversionTaskSink
  where
    params =
        [ "ConversionTaskId" |.#= ctids
        ]

conversionTaskSink
    :: MonadThrow m
    => Consumer Event m ConversionTask
conversionTaskSink = ConversionTask
    <$> getT "conversionTaskId"
    <*> getT "expirationTime"
    <*> elementM "importVolume" (
        ImportVolumeTaskDetails
        <$> getT "bytesConverted"
        <*> getT "availabilityZone"
        <*> getT "description"
        <*> element "image" diskImageDescriptionSink
        <*> element "volume" diskImageVolumeDescriptionSink
        )
    <*> elementM "importInstance" (
        ImportInstanceTaskDetails
        <$> itemsSet "volumes" (
            ImportInstanceTaskDetailItem
            <$> getT "bytesConverted"
            <*> getT "availabilityZone"
            <*> element "image" diskImageDescriptionSink
            <*> getT "description"
            <*> element "volume" diskImageVolumeDescriptionSink
            <*> getT "status"
            <*> getT "statusMessage"
            )
        <*> getT "instanceId"
        <*> getT "platform"
        <*> getT "description"
        )
    <*> getT "state"
    <*> getT "statusMessage"

diskImageDescriptionSink
    :: MonadThrow m
    => Consumer Event m DiskImageDescription
diskImageDescriptionSink = DiskImageDescription
    <$> getT "format"
    <*> getT "size"
    <*> getT "importManifestUrl"
    <*> getT "checksum"

diskImageVolumeDescriptionSink
    :: MonadThrow m
    => Consumer Event m DiskImageVolumeDescription
diskImageVolumeDescriptionSink = DiskImageVolumeDescription
    <$> getT "size"
    <*> getT "id"

cancelConversionTask
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ ConversionTaskId
    -> EC2 m Bool
cancelConversionTask =
    ec2Delete "CancelConversionTask" "ConversionTaskId"

importVolume
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ AvailabilityZone
    -> ImportVolumeRequestImage -- ^ Image
    -> Maybe Text -- ^ Description
    -> Int -- ^ Volume Size
    -> EC2 m ConversionTask
importVolume zone image desc size =
    ec2Query "ImportVolume" params $
        element "conversionTask" conversionTaskSink
  where
    params =
        [ "AvailabilityZone" |= zone
        , "Image" |. imageParams image
        , "Description" |=? desc
        , "Volume" |.+ "Size" |= size
        ]
    imageParams img =
        [ "Format" |= importVolumeRequestImageFormat img
        , "Bytes" |= importVolumeRequestImageBytes img
        , "ImportManifestUrl" |= importVolumeRequestImageImportManifestUrl img
        ]

importInstance
    :: (MonadResource m, MonadBaseControl IO m)
    => Maybe Text -- ^ Description
    -> LaunchSpecification -- ^ LaunchSpecification
    -> [DiskImage] -- ^ DiskImages
    -> Platform -- ^ Platform
    -> EC2 m ConversionTask
importInstance desc ls images platform =
    ec2Query "ImportInstance" params $
        element "conversionTask" conversionTaskSink
  where
    params =
        [ "Description" |=? desc
        , "LaunchSpecification" |. launchSpecificationParams ls
        , "DiskImage" |.#. diskImageParams <$> images
        , "Platform" |= platform
        ]
    launchSpecificationParams (LaunchSpecification{..}) =
        [ "Architecture" |=
            launchSpecificationArchitecture
        , "GroupName" |.#= launchSpecificationGroupNames
        , "UserData" |=? launchSpecificationUserData
        , "InstanceType" |= launchSpecificationInstanceType
        , "Placement" |.+ "AvailabilityZone" |=?
            launchSpecificationPlacementAvailabilityZone
        , "Monitoring" |.+ "Enabled" |=?
            launchSpecificationMonitoringEnabled
        , "SubnetId" |=? launchSpecificationSubnetId
        , "InstanceInitiatedShutdownBehavior" |=?
            launchSpecificationInstanceInitiatedShutdownBehavior
        , "PrivateIpAddress" |=?
            launchSpecificationPrivateIpAddress
        ]
    diskImageParams (DiskImage{..}) =
        [ "Image" |.
            [ "Format" |= diskImageFormat
            , "Bytes" |= diskImageBytes
            , "ImportManifestUrl" |= diskImageImportManifestUrl
            , "Description" |=? diskImageDescripsion
            ]
        , "Volume" |.+ "Size" |= diskImageVolumeSize
        ]
