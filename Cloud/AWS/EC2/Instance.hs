{-# LANGUAGE FlexibleContexts, RankNTypes #-}

module Cloud.AWS.EC2.Instance
    ( describeInstances
    , runInstances
    , defaultRunInstancesRequest
    , terminateInstances
    , startInstances
    , stopInstances
    , rebootInstances
    , getConsoleOutput
    , getPasswordData
    , describeInstanceStatus
    , describeInstanceAttribute
    , resetInstanceAttribute
    , modifyInstanceAttribute
    , monitorInstances
    , unmonitorInstances
    , describeSpotInstanceRequests
    , requestSpotInstances
    , defaultRequestSpotInstancesParam
    , cancelSpotInstanceRequests
    ) where

import Data.Text (Text)
import Data.XML.Types (Event)
import Data.Conduit
import Control.Applicative
import Data.Maybe (fromMaybe, fromJust)
import qualified Data.Map as Map
import Control.Monad

import Cloud.AWS.EC2.Internal
import Cloud.AWS.EC2.Types
import Cloud.AWS.EC2.Params
import Cloud.AWS.EC2.Query
import Cloud.AWS.Lib.Parser
import Cloud.AWS.Lib.ToText (toText)

------------------------------------------------------------
-- DescribeInstances
------------------------------------------------------------
describeInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> [Filter] -- ^ Filters
    -> EC2 m (ResumableSource m Reservation)
describeInstances instances filters = do
--    ec2QueryDebug "DescribeInstances" params
    ec2QuerySource "DescribeInstances" params $
        itemConduit "reservationSet" reservationSink
  where
    params =
        [ "InstanceId" |.#= instances
        , filtersParam filters
        ]

reservationSink :: MonadThrow m
    => Consumer Event m Reservation
reservationSink =
    Reservation
    <$> getT "reservationId"
    <*> getT "ownerId"
    <*> groupSetSink
    <*> instanceSetSink
    <*> getT "requesterId"

instanceSetSink :: MonadThrow m
    => Consumer Event m [Instance]
instanceSetSink = itemsSet "instancesSet" $
    Instance
    <$> getT "instanceId"
    <*> getT "imageId"
    <*> instanceStateSink "instanceState"
    <*> getT "privateDnsName"
    <*> getT "dnsName"
    <*> getT "reason"
    <*> getT "keyName"
    <*> getT "amiLaunchIndex"
    <*> productCodeSink
    <*> getT "instanceType"
    <*> getT "launchTime"
    <*> element "placement" (
        Placement
        <$> getT "availabilityZone"
        <*> getT "groupName"
        <*> getT "tenancy"
        )
    <*> getT "kernelId"
    <*> getT "ramdiskId"
    <*> getT "platform"
    <*> element "monitoring" (getT "state")
    <*> getT "subnetId"
    <*> getT "vpcId"
    <*> getT "privateIpAddress"
    <*> getT "ipAddress"
    <*> getT "sourceDestCheck"
    <*> groupSetSink
    <*> stateReasonSink
    <*> getT "architecture"
    <*> getT "rootDeviceType"
    <*> getT "rootDeviceName"
    <*> instanceBlockDeviceMappingsSink
    <*> getT "instanceLifecycle"
    <*> getT "spotInstanceRequestId"
    <*> getT "virtualizationType"
    <*> getT "clientToken"
    <*> resourceTagSink
    <*> getT "hypervisor"
    <*> networkInterfaceSink
    <*> elementM "iamInstanceProfile" (
        IamInstanceProfile
        <$> getT "arn"
        <*> getT "id"
        )
    <*> getT "ebsOptimized"

instanceBlockDeviceMappingsSink :: MonadThrow m
    => Consumer Event m [InstanceBlockDeviceMapping]
instanceBlockDeviceMappingsSink = itemsSet "blockDeviceMapping" (
    InstanceBlockDeviceMapping
    <$> getT "deviceName"
    <*> element "ebs" (
        EbsInstanceBlockDevice
        <$> getT "volumeId"
        <*> getT "status"
        <*> getT "attachTime"
        <*> getT "deleteOnTermination"
        )
    )

instanceStateCodes :: [(Int, InstanceState)]
instanceStateCodes =
    [ ( 0, InstanceStatePending)
    , (16, InstanceStateRunning)
    , (32, InstanceStateShuttingDown)
    , (48, InstanceStateTerminated)
    , (64, InstanceStateStopping)
    , (80, InstanceStateStopped)
    ]

codeToState :: Int -> Text -> InstanceState
codeToState code _name = fromMaybe
    (InstanceStateUnknown code)
    (lookup code instanceStateCodes)

instanceStateSink :: MonadThrow m
    => Text -> Consumer Event m InstanceState
instanceStateSink label = element label $ codeToState
    <$> getT "code"
    <*> getT "name"

networkInterfaceSink :: MonadThrow m
    => Consumer Event m [InstanceNetworkInterface]
networkInterfaceSink = itemsSet "networkInterfaceSet" $
    InstanceNetworkInterface
    <$> getT "networkInterfaceId"
    <*> getT "subnetId"
    <*> getT "vpcId"
    <*> getT "description"
    <*> getT "ownerId"
    <*> getT "status"
    <*> getT "macAddress"
    <*> getT "privateIpAddress"
    <*> getT "privateDnsName"
    <*> getT "sourceDestCheck"
    <*> groupSetSink
    <*> elementM "attachment" (
        InstanceNetworkInterfaceAttachment
        <$> getT "attachmentId"
        <*> getT "deviceIndex"
        <*> getT "status"
        <*> getT "attachTime"
        <*> getT "deleteOnTermination"
        )
    <*> instanceNetworkInterfaceAssociationSink
    <*> itemsSet "privateIpAddressesSet" (
        InstancePrivateIpAddress
        <$> getT "privateIpAddress"
        <*> getT "privateDnsName"
        <*> getT "primary"
        <*> instanceNetworkInterfaceAssociationSink
        )

instanceNetworkInterfaceAssociationSink :: MonadThrow m
    => Consumer Event m (Maybe InstanceNetworkInterfaceAssociation)
instanceNetworkInterfaceAssociationSink = elementM "association" $
    InstanceNetworkInterfaceAssociation
    <$> getT "publicIp"
    <*> getT "publicDnsName"
    <*> getT "ipOwnerId"

------------------------------------------------------------
-- DescribeInstanceStatus
------------------------------------------------------------
-- | raise 'ResponseParserException'('NextToken' token)
describeInstanceStatus
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> Bool  -- ^ is all instance? 'False': running instance only.
    -> [Filter] -- ^ Filters
    -> Maybe Text -- ^ next token
    -> EC2 m (ResumableSource m InstanceStatus)
describeInstanceStatus instanceIds isAll filters token =
    ec2QuerySource' "DescribeInstanceStatus" params token instanceStatusSet
  where
    params =
        [ "InstanceId" |.#= instanceIds
        , "IncludeAllInstances" |= isAll
        , filtersParam filters
        ]

instanceStatusSet :: MonadThrow m
    => Conduit Event m InstanceStatus
instanceStatusSet = do
    itemConduit "instanceStatusSet" $
        InstanceStatus
        <$> getT "instanceId"
        <*> getT "availabilityZone"
        <*> itemsSet "eventsSet" (
            InstanceStatusEvent
            <$> getT "code"
            <*> getT "description"
            <*> getT "notBefore"
            <*> getT "notAfter"
            )
        <*> instanceStateSink "instanceState"
        <*> instanceStatusTypeSink "systemStatus"
        <*> instanceStatusTypeSink "instanceStatus"

instanceStatusTypeSink :: MonadThrow m
    => Text -> Consumer Event m InstanceStatusType
instanceStatusTypeSink name = element name $
    InstanceStatusType
    <$> getT "status"
    <*> itemsSet "details" (
        InstanceStatusDetail
        <$> getT "name"
        <*> getT "status"
        <*> getT "impairedSince"
        )

------------------------------------------------------------
-- StartInstances
------------------------------------------------------------
startInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m (ResumableSource m InstanceStateChange)
startInstances instanceIds =
    ec2QuerySource "StartInstances" params instanceStateChangeSet
  where
    params = ["InstanceId" |.#= instanceIds]

instanceStateChangeSet
    :: (MonadResource m, MonadBaseControl IO m)
    => Conduit Event m InstanceStateChange
instanceStateChangeSet = itemConduit "instancesSet" $ do
    InstanceStateChange
    <$> getT "instanceId"
    <*> instanceStateSink "currentState"
    <*> instanceStateSink "previousState"

------------------------------------------------------------
-- StopInstances
------------------------------------------------------------
stopInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> Bool -- ^ Force
    -> EC2 m (ResumableSource m InstanceStateChange)
stopInstances instanceIds force =
    ec2QuerySource "StopInstances" params instanceStateChangeSet
  where
    params =
        [ "InstanceId" |.#= instanceIds
        , "Force" |= force]

------------------------------------------------------------
-- RebootInstances
------------------------------------------------------------
rebootInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m Bool
rebootInstances instanceIds =
    ec2Query "RebootInstances" params $ getT "return"
  where
    params = ["InstanceId" |.#= instanceIds]

------------------------------------------------------------
-- TerminateInstances
------------------------------------------------------------
terminateInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m (ResumableSource m InstanceStateChange)
terminateInstances instanceIds =
    ec2QuerySource "TerminateInstances" params
        instanceStateChangeSet
  where
    params = ["InstanceId" |.#= instanceIds]

------------------------------------------------------------
-- RunInstances
------------------------------------------------------------
-- | 'RunInstancesParam' is genereted with 'defaultRunInstancesParam'
runInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => RunInstancesRequest
    -> EC2 m Reservation
runInstances param =
    ec2Query "RunInstances" params reservationSink
  where
    params =
        [ "ImageId" |= runInstancesRequestImageId param
        , "MinCount" |= runInstancesRequestMinCount param
        , "MaxCount" |= runInstancesRequestMaxCount param
        , "KeyName" |=? runInstancesRequestKeyName param
        , "SecurityGroupId" |.#= runInstancesRequestSecurityGroupIds param
        , "SecurityGroup" |.#= runInstancesRequestSecurityGroups param
        , "UserData" |=? runInstancesRequestUserData param
        , "InstanceType" |=? runInstancesRequestInstanceType param
        , "Placement" |.
            [ "AvailabilityZone" |=?
                runInstancesRequestAvailabilityZone param
            , "GroupName" |=?
                runInstancesRequestPlacementGroup param
            , "Tenancy" |=?
                runInstancesRequestTenancy param
            ]
        , "KernelId" |=? runInstancesRequestKernelId param
        , "RamdiskId" |=? runInstancesRequestRamdiskId param
        , blockDeviceMappingsParam $
            runInstancesRequestBlockDeviceMappings param
        , "Monitoring" |.+ "Enabled" |=?
            runInstancesRequestMonitoringEnabled param
        , "SubnetId" |=? runInstancesRequestSubnetId param
        , "DisableApiTermination" |=?
            runInstancesRequestDisableApiTermination param
        , "InstanceInitiatedShutdownBehavior" |=?
            runInstancesRequestShutdownBehavior param
        , "PrivateIpAddress" |=?
            runInstancesRequestPrivateIpAddress param
        , "ClientToken" |=? runInstancesRequestClientToken param
        , "NetworkInterface" |.#. map networkInterfaceParams
            (runInstancesRequestNetworkInterfaces param)
        , "IamInstanceProfile" |.? iamInstanceProfileParams <$>
            runInstancesRequestIamInstanceProfile param
        , "EbsOptimized" |=?
            runInstancesRequestEbsOptimized param
        ]
    iamInstanceProfileParams iam =
        [ "Arn" |= iamInstanceProfileArn iam
        , "Name" |= iamInstanceProfileId iam
        ]

-- | RunInstances parameter utility
defaultRunInstancesRequest
    :: Text -- ^ ImageId
    -> Int -- ^ MinCount
    -> Int -- ^ MaxCount
    -> RunInstancesRequest
defaultRunInstancesRequest iid minCount maxCount
    = RunInstancesRequest
        iid
        minCount
        maxCount
        Nothing
        []
        []
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        []
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        []
        Nothing
        Nothing

networkInterfaceParams :: NetworkInterfaceParam -> [QueryParam]
networkInterfaceParams (NetworkInterfaceParamCreate di si d pia pias sgi dot) =
    [ "DeviceIndex" |= di
    , "SubnetId" |= si
    , "Description" |= d
    , "PrivateIpAddress" |=? pia
    , "SecurityGroupId" |.#= sgi
    , "DeleteOnTermination" |= dot
    ] ++ s pias
  where
    s SecondaryPrivateIpAddressParamNothing = []
    s (SecondaryPrivateIpAddressParamCount c) =
        ["SecondaryPrivateIpAddressCount" |= c]
    s (SecondaryPrivateIpAddressParamSpecified addrs pr) =
        [ privateIpAddressesParam "PrivateIpAddresses" addrs
        , maybeParam $ ipAddressPrimaryParam <$> pr
        ]
    ipAddressPrimaryParam i =
        "PrivateIpAddresses" |.+ toText i |.+ "Primary" |= True
networkInterfaceParams (NetworkInterfaceParamAttach nid idx dot) =
    [ "NetworkInterfaceId" |= nid
    , "DeviceIndex" |= idx
    , "DeleteOnTermination" |= dot
    ]

------------------------------------------------------------
-- GetConsoleOutput
------------------------------------------------------------
getConsoleOutput
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> EC2 m ConsoleOutput
getConsoleOutput iid =
    ec2Query "GetConsoleOutput" ["InstanceId" |= iid] $
        ConsoleOutput
        <$> getT "instanceId"
        <*> getT "timestamp"
        <*> getT "output"

------------------------------------------------------------
-- GetPasswordData
------------------------------------------------------------
getPasswordData
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> EC2 m PasswordData
getPasswordData iid =
    ec2Query "GetPasswordData" ["InstanceId" |= iid] $
        PasswordData
        <$> getT "instanceId"
        <*> getT "timestamp"
        <*> getT "passwordData"

describeInstanceAttribute
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> InstanceAttributeRequest -- ^ Attribute
    -> EC2 m InstanceAttribute
describeInstanceAttribute iid attr =
    ec2Query "DescribeInstanceAttribute" params
        $ getT_ "instanceId" *> f attr
  where
    str = iar attr
    params =
        [ "InstanceId" |= iid
        , "Attribute" |= str
        ]
    f InstanceAttributeRequestBlockDeviceMapping = instanceBlockDeviceMappingsSink
        >>= return . InstanceAttributeBlockDeviceMapping
    f InstanceAttributeRequestProductCodes =
        productCodeSink >>= return . InstanceAttributeProductCodes
    f InstanceAttributeRequestGroupSet =
        (itemsSet str $ getT "groupId")
        >>= return . InstanceAttributeGroupSet
    f req = valueSink str (fromJust $ Map.lookup req h)
    h = Map.fromList
        [ (InstanceAttributeRequestInstanceType,
           InstanceAttributeInstanceType . fromJust)
        , (InstanceAttributeRequestKernelId, InstanceAttributeKernelId)
        , (InstanceAttributeRequestRamdiskId, InstanceAttributeRamdiskId)
        , (InstanceAttributeRequestUserData, InstanceAttributeUserData)
        , (InstanceAttributeRequestDisableApiTermination,
           InstanceAttributeDisableApiTermination . just)
        , (InstanceAttributeRequestShutdownBehavior,
           InstanceAttributeShutdownBehavior
           . fromJust . fromText . fromJust)
        , (InstanceAttributeRequestRootDeviceName,
           InstanceAttributeRootDeviceName)
        , (InstanceAttributeRequestSourceDestCheck,
           InstanceAttributeSourceDestCheck
           . fromText . fromJust)
        , (InstanceAttributeRequestEbsOptimized,
           InstanceAttributeEbsOptimized . just)
        ]
    just = fromJust . join . (fromText <$>)
    valueSink name val =
        (element name $ getT "value") >>= return . val

iar :: InstanceAttributeRequest -> Text
iar InstanceAttributeRequestInstanceType          = "instanceType"
iar InstanceAttributeRequestKernelId              = "kernel"
iar InstanceAttributeRequestRamdiskId             = "ramdisk"
iar InstanceAttributeRequestUserData              = "userData"
iar InstanceAttributeRequestDisableApiTermination = "disableApiTermination"
iar InstanceAttributeRequestShutdownBehavior      = "instanceInitiatedShutdownBehavior"
iar InstanceAttributeRequestRootDeviceName        = "rootDeviceName"
iar InstanceAttributeRequestBlockDeviceMapping    = "blockDeviceMapping"
iar InstanceAttributeRequestSourceDestCheck       = "sourceDestCheck"
iar InstanceAttributeRequestGroupSet              = "groupSet"
iar InstanceAttributeRequestProductCodes          = "productCodes"
iar InstanceAttributeRequestEbsOptimized          = "ebsOptimized"

riap :: ResetInstanceAttributeRequest -> Text
riap ResetInstanceAttributeRequestKernel          = "kernel"
riap ResetInstanceAttributeRequestRamdisk         = "ramdisk"
riap ResetInstanceAttributeRequestSourceDestCheck = "sourceDestCheck"

resetInstanceAttribute
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> ResetInstanceAttributeRequest
    -> EC2 m Bool
resetInstanceAttribute iid attr =
    ec2Query "ResetInstanceAttribute" params $ getT "return"
  where
    params =
        [ "InstanceId" |= iid
        , "Attribute" |= riap attr
        ]

-- | not tested
modifyInstanceAttribute
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ InstanceId
    -> ModifyInstanceAttributeRequest
    -> EC2 m Bool
modifyInstanceAttribute iid attr =
    ec2Query "ModifyInstanceAttribute" params $ getT "return"
  where
    params = ["InstanceId" |= iid, miap attr]

miap :: ModifyInstanceAttributeRequest -> QueryParam
miap (ModifyInstanceAttributeRequestInstanceType a) =
    "InstanceType" |.+ "Value" |= a
miap (ModifyInstanceAttributeRequestKernelId a) =
    "Kernel" |.+ "Value" |= a
miap (ModifyInstanceAttributeRequestRamdiskId a) =
    "Ramdisk" |.+ "Value" |= a
miap (ModifyInstanceAttributeRequestUserData a) =
    "UserData" |.+ "Value" |= a
miap (ModifyInstanceAttributeRequestDisableApiTermination a) =
    "DisableApiTermination" |.+ "Value" |= a
miap (ModifyInstanceAttributeRequestShutdownBehavior a) =
    "InstanceInitiatedShutdownBehavior" |.+ "Value" |= a
miap (ModifyInstanceAttributeRequestRootDeviceName a) =
    "RootDeviceName" |= a
miap (ModifyInstanceAttributeRequestBlockDeviceMapping a) =
    blockDeviceMappingsParam a
miap (ModifyInstanceAttributeRequestSourceDestCheck a) =
    "SourceDestCheck" |.+ "Value" |= a
miap (ModifyInstanceAttributeRequestGroupSet a) =
    "GroupId" |.#= a
miap (ModifyInstanceAttributeRequestEbsOptimized a) =
    "EbsOptimized" |= a

------------------------------------------------------------
-- MonitorInstances
------------------------------------------------------------
monitorInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m (ResumableSource m MonitorInstancesResponse)
monitorInstances iids =
    ec2QuerySource "MonitorInstances" ["InstanceId" |.#= iids]
        monitorInstancesResponseSink

monitorInstancesResponseSink
    :: (MonadResource m, MonadBaseControl IO m)
    => Conduit Event m MonitorInstancesResponse
monitorInstancesResponseSink = itemConduit "instancesSet" $
    MonitorInstancesResponse
    <$> getT "instanceId"
    <*> element "monitoring" (getT "state")

------------------------------------------------------------
-- UnmonitorInstances
------------------------------------------------------------
unmonitorInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m (ResumableSource m MonitorInstancesResponse)
unmonitorInstances iids =
    ec2QuerySource "UnmonitorInstances" ["InstanceId" |.#= iids]
        monitorInstancesResponseSink

------------------------------------------------------------
-- DescribeSpotInstanceRequests
------------------------------------------------------------
describeSpotInstanceRequests
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ SpotInstanceRequestIds
    -> [Filter] -- ^ Filters
    -> EC2 m (ResumableSource m SpotInstanceRequest)
describeSpotInstanceRequests requests filters = do
--    ec2QueryDebug "DescribeInstances" params
    ec2QuerySource "DescribeSpotInstanceRequests" params $
        itemConduit "spotInstanceRequestSet" spotInstanceRequestSink
  where
    params =
        [ "SpotInstanceRequestId" |.#= requests
        , filtersParam filters
        ]

spotInstanceRequestSink :: MonadThrow m
    => Consumer Event m SpotInstanceRequest
spotInstanceRequestSink =
    SpotInstanceRequest
    <$> getT "spotInstanceRequestId"
    <*> getT "spotPrice"
    <*> getT "type"
    <*> getT "state"
    <*> elementM "fault" (
        SpotInstanceFault
        <$> getT "code"
        <*> getT "message"
        )
    <*> element "status" (
        SpotInstanceStatus
        <$> getT "code"
        <*> getT "updateTime"
        <*> getT "message"
        )
    <*> getT "validFrom"
    <*> getT "validUntil"
    <*> getT "launchGroup"
    <*> getT "availabilityZoneGroup"
    <*> spotInstanceLaunchSpecificationSink "launchSpecification"
    <*> getT "instanceId"
    <*> getT "createTime"
    <*> getT "productDescription"
    <*> resourceTagSink
    <*> getT "launchedAvailabilityZone"


spotInstanceLaunchSpecificationSink :: MonadThrow m
    => Text -> Consumer Event m SpotInstanceLaunchSpecification
spotInstanceLaunchSpecificationSink label = element label (
    SpotInstanceLaunchSpecification
    <$> getT "imageId"
    <*> getT "keyName"
    <*> groupSetSink
    <*> getT "instanceType"
    <*> element "placement" (
        Placement
        <$> getT "availabilityZone"
        <*> getT "groupName"
        <*> getT "tenancy"
        )
    <*> getT "kernelId"
    <*> getT "ramdiskId"
    <*> spotInstanceBlockDeviceMappingsSink
    <*> element "monitoring" (
        SpotInstanceMonitoringState
        <$> getT "enabled"
        )
    <*> getT "subnetId"
    <*> spotInstanceNetworkInterfaceSink
    <*> elementM "iamInstanceProfile" (
        IamInstanceProfile
        <$> getT "arn"
        <*> getT "id"
        )
    <*> getT "ebsOptimized" 
    )

spotInstanceBlockDeviceMappingsSink :: MonadThrow m
    => Consumer Event m [SpotInstanceBlockDeviceMapping]
spotInstanceBlockDeviceMappingsSink = itemsSet "blockDeviceMapping" (
    SpotInstanceBlockDeviceMapping
    <$> getT "deviceName"
    <*> element "ebs" (
        EbsSpotInstanceBlockDevice
        <$> getT "volumeSize"
        <*> getT "deleteOnTermination"
        <*> getT "volumeType"
        )
    )

spotInstanceNetworkInterfaceSink :: MonadThrow m
    => Consumer Event m [SpotInstanceNetworkInterface]
spotInstanceNetworkInterfaceSink = itemsSet "networkInterfaceSet" $
    SpotInstanceNetworkInterface
    <$> getT "deviceIndex"
    <*> getT "subnetId"
    <*> securityGroupSetSink

securityGroupSetSink :: MonadThrow m
    => Consumer Event m [SpotInstanceSecurityGroup]
securityGroupSetSink = itemsSet "groupSet" $
    SpotInstanceSecurityGroup
    <$> getT "groupId"

------------------------------------------------------------
-- RequestSpotInstances
------------------------------------------------------------
-- | 'RequestSpotInstancesParam' is genereted with 'defaultRequestSpotInstancesParam'
requestSpotInstances
    :: (MonadResource m, MonadBaseControl IO m)
    => RequestSpotInstancesParam
    -> EC2 m [SpotInstanceRequest]
requestSpotInstances param =
    ec2Query "RequestSpotInstances" params $
        itemsSet "spotInstanceRequestSet" spotInstanceRequestSink
  where
    params =
        [ "SpotPrice" |= requestSpotInstancesSpotPrice param
        , "InstanceCount" |=? requestSpotInstancesCount param
        , "Type" |=? requestSpotInstancesType param
        , "ValidFrom" |=? requestSpotInstancesValidFrom param
        , "ValidUntil" |=? requestSpotInstancesValidUntil param
        , "LaunchGroup" |=? requestSpotInstancesLaunchGroup param
        , "AvailabilityZoneGroup" |=? requestSpotInstancesLaunchGroup param
        , "LaunchSpecification" |.
          [ "ImageId" |= requestSpotInstancesImageId param
          , "KeyName" |=? requestSpotInstancesKeyName param
          , "SecurityGroupId" |.#= requestSpotInstancesSecurityGroupIds param
          , "SecurityGroup" |.#= requestSpotInstancesSecurityGroups param
          , "UserData" |=? requestSpotInstancesUserData param
          , "InstanceType" |= requestSpotInstancesInstanceType param
          , "Placement" |.
              [ "AvailabilityZone" |=?
                  requestSpotInstancesAvailabilityZone param
              , "GroupName" |=?
                  requestSpotInstancesPlacementGroup param
              ]
          , "KernelId" |=? requestSpotInstancesKernelId param
          , "RamdiskId" |=? requestSpotInstancesRamdiskId param
          , blockDeviceMappingsParam $
              requestSpotInstancesBlockDeviceMappings param
          , "Monitoring" |.+ "Enabled" |=?
              requestSpotInstancesMonitoringEnabled param
          , "SubnetId" |=? requestSpotInstancesSubnetId param
          , "NetworkInterface" |.#. map networkInterfaceParams
              (requestSpotInstancesNetworkInterfaces param)
          , "IamInstanceProfile" |.? iamInstanceProfileParams <$>
              requestSpotInstancesIamInstancesProfile param
          , "EbsOptimized" |=?
              requestSpotInstancesEbsOptimized param
          ]
        ]
    iamInstanceProfileParams iam =
        [ "Arn" |= iamInstanceProfileArn iam
        , "Name" |= iamInstanceProfileId iam
        ]

-- | RequestSpotInstances parameter utility
defaultRequestSpotInstancesParam
    :: Text -- ^ Price
    -> Text -- ^ ImageId
    -> Text -- ^ Instance type
    -> RequestSpotInstancesParam
defaultRequestSpotInstancesParam price iid iType
    = RequestSpotInstancesParam
        price
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        iid
        Nothing
        []
        []
        Nothing
        iType
        Nothing
        Nothing
        Nothing
        Nothing
        []
        Nothing
        Nothing
        []
        Nothing
        Nothing

------------------------------------------------------------
-- CancelSpotInstanceRequests
------------------------------------------------------------
cancelSpotInstanceRequests
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ InstanceIds
    -> EC2 m (ResumableSource m CancelSpotInstanceRequestsResponse)
cancelSpotInstanceRequests requestIds =
    ec2QuerySource "CancelSpotInstanceRequests" params $
        itemConduit "spotInstanceRequestSet" cancelSpotInstanceResponseSink
  where
    params = ["SpotInstanceRequestId" |.#= requestIds]

cancelSpotInstanceResponseSink :: MonadThrow m
    => Consumer Event m CancelSpotInstanceRequestsResponse
cancelSpotInstanceResponseSink = CancelSpotInstanceRequestsResponse
    <$> getT "spotInstanceRequestId"
    <*> getT "state"
