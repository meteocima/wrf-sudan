#!/bin/bash

set -e

aws ec2 run-instances --launch-template LaunchTemplateId=lt-039ae04625a271797 --region=eu-west-1 | cat

SERVER_IP=`aws ec2 describe-instances --region eu-west-1 --filters Name=tag:Name,Values=WRF_COMP Name=instance-state-name,Values=running --query "Reservations[].Instances[].PrivateIpAddress" --output text`
INSTANCE_ID=`aws ec2 describe-instances --region eu-west-1 --filters Name=tag:Name,Values=WRF_COMP Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text`

sleep 60

ssh wrf@$SERVER_IP cd /share/wrf; pwd; hostname

aws ec2 terminate-instances --region eu-west-1 --instance-ids $INSTANCE_ID
