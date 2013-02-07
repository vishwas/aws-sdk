{-# LANGUAGE FlexibleContexts, RecordWildCards #-}
module AWSTests.CloudWatchTests.AlarmTests
    ( runAlarmTests
    )
    where

import Data.Text (Text)
import Test.Hspec

import AWS.CloudWatch
import AWS.CloudWatch.Types
import AWSTests.Util
import AWSTests.CloudWatchTests.Util

region :: Text
region = "ap-northeast-1"

runAlarmTests :: IO ()
runAlarmTests = do
    hspec describeAlarmsTest
    hspec putMetricAlarmTest
    hspec describeAlarmHistoryTest
    hspec alarmActionsTest

describeAlarmsTest :: Spec
describeAlarmsTest = do
    describe "Alarm operations doesn't fail" $ do
        it "describeAlarms doesn't throw any exception" $ do
            testCloudWatch region (describeAlarms Nothing AlarmSpecNothing Nothing Nothing Nothing) `miss` anyHttpException

            -- Expect NextToken is returned
            testCloudWatch region (describeAlarms Nothing AlarmSpecNothing (Just 1) Nothing Nothing) `miss` anyHttpException

        it "describeAlarmsForMetric doesn't throw any exception" $ do
            testCloudWatch region (do
                (MetricAlarm{..}:_, _) <- describeAlarms Nothing AlarmSpecNothing Nothing Nothing Nothing
                describeAlarmsForMetric metricAlarmDimensions metricAlarmMetricName metricAlarmNamespace metricAlarmPeriod metricAlarmStatistic Nothing
                ) `miss` anyHttpException

putMetricAlarmTest :: Spec
putMetricAlarmTest =
    describe "putMetricAlarm/deleteAlarms doesn't fail" $ do
        it "putMetricAlarm/deleteAlarms doesn't throw any exception" $ do
            testCloudWatch region (do
                (metric:_, _) <- listMetrics [] Nothing Nothing Nothing
                let req = PutMetricAlarmRequest
                            { putMetricAlarmActionsEnabled = Just False
                            , putMetricAlarmAlarmActions = []
                            , putMetricAlarmAlarmDescription = Just "putMetricAlarmTest Description"
                            , putMetricAlarmAlarmName = "putMetricAlarmTest"
                            , putMetricAlarmComparisonOperator = GreaterThanThreshold
                            , putMetricAlarmDimensions = []
                            , putMetricAlarmEvaluationPeriods = 5
                            , putMetricAlarmInsufficientDataActions = []
                            , putMetricAlarmMetricName = metricName metric
                            , putMetricAlarmNamespace = metricNameSpace metric
                            , putMetricAlarmOKActions = []
                            , putMetricAlarmPeriod = 5 * 60
                            , putMetricAlarmStatistic = StatisticSampleCount
                            , putMetricAlarmThreshold = 42.0
                            , putMetricAlarmUnit = Just "Count"
                            }
                putMetricAlarm req
                deleteAlarms [putMetricAlarmAlarmName req]
                ) `miss` anyHttpException

describeAlarmHistoryTest :: Spec
describeAlarmHistoryTest =
    describe "describeAlarmHistory doesn't fail" $ do
        it "describeAlarmHistory doesn't throw any exception" $ do
            testCloudWatch region (do
                describeAlarmHistory Nothing Nothing Nothing Nothing Nothing Nothing
                -- Expect NextToken is returned
                describeAlarmHistory Nothing Nothing Nothing (Just 1) Nothing Nothing
                ) `miss` anyHttpException

alarmActionsTest :: Spec
alarmActionsTest =
    describe "{disable,enable}AlarmActions doesn't fail" $ do
        it "{disable,enable}AlarmActions doesn't throw any exception" $ do
            testCloudWatch region (do
                (alarm:_, _) <- describeAlarms Nothing AlarmSpecNothing Nothing Nothing Nothing
                let name = metricAlarmAlarmName alarm
                disableAlarmActions [name]
                enableAlarmActions [name]
                ) `miss` anyHttpException
