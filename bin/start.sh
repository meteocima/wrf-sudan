#!/bin/bash

set -e


function log() {
   echo -n `date -u '+%Y-%m-%d %H:%M:%S'`' '
   echo "$*"
}

log Starting server instance

aws ec2 run-instances --launch-template LaunchTemplateId=lt-0e3fcbfc04c4608f3 --region=eu-west-1 > /dev/null

sleep 5
SERVER_IP=`aws ec2 describe-instances --region eu-west-1 --filters Name=tag:Name,Values=WRF_COMP Name=instance-state-name,Values=running --query "Reservations[].Instances[].PrivateIpAddress" --output text`
INSTANCE_ID=`aws ec2 describe-instances --region eu-west-1 --filters Name=tag:Name,Values=WRF_COMP Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text`

log SERVER_IP $SERVER_IP
log INSTANCE_ID $INSTANCE_ID

err=1
n=0
set +e
while [ $err -ne 0 ]; do
    ssh -o StrictHostKeyChecking=no wrf@$SERVER_IP 'pwd' > /dev/null 2>&1
    err=$?
    sleep 10
    log Waiting server up. $(( n++ ))
done

ssh -o StrictHostKeyChecking=no wrf@$SERVER_IP '/share/wrf/bin/wrf-sudan.sh'

log Saving working directory to /share
ssh -o StrictHostKeyChecking=no wrf@$SERVER_IP '/share/wrf/bin/dump-workdir.sh'

set -e
log Stopping server instance
aws ec2 terminate-instances --region eu-west-1 --instance-ids $INSTANCE_ID > /dev/null
