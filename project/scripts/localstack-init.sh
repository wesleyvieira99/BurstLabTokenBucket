#!/bin/sh
set -eu
awslocal sqs create-queue --queue-name burstlab-jobs --attributes VisibilityTimeout=45,ReceiveMessageWaitTimeSeconds=20,MessageRetentionPeriod=345600
awslocal sqs create-queue --queue-name burstlab-dlq --attributes MessageRetentionPeriod=1209600
# Deliberately no RedrivePolicy: waiting for capacity is NOT a failed B attempt.
