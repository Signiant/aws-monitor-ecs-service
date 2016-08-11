#!/usr/local/bin/bash

# Checks the memory of an ECS service and if over a threshold, cycles the tasks

# Input parameters
#   1 - The name of the ECS cluster the service is running in
#   2 - the region the ECS cluster is running in (ie. us-east-1)
#   3 - The AWS CLI profile to use
#   4 - A prefix to match an ECS service (must map to ONLY ONE service)

CLUSTER=$1
REGION=$2
PROFILE=$3
SERVICE_PREFIX=$4

# get the ECS service name
get_service_name()
{
  arn=$(get_service_arn)
  name=${arn#*/}

  echo "$name"
}

get_service_arn()
{
  service_arn=$(aws ecs list-services --cluster ${CLUSTER} --region ${REGION} --profile ${PROFILE} --query 'serviceArns' |grep ${SERVICE_PREFIX} |xargs)
  service_arn=${service_arn/%,/}  # remove trailing comma if it exists

  echo "${service_arn}"
}

# Get the ECS service name
service_name=$(get_service_name)

if [ ! -z "${service_name}" ]; then
  echo "ECS service name found is ${service_name}"
fi
