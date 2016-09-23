#!/bin/bash

# Checks the memory of an ECS service and if over a threshold, cycles the tasks

# Input parameters
#   1 - The name of the ECS cluster the service is running in
#   2 - the region the ECS cluster is running in (ie. us-east-1)
#   3 - A prefix to match an ECS service (must map to ONLY ONE service)
#   4 - percentage of memory use before the tasks should be cycled

CLUSTER=$1
REGION=$2
SERVICE_PREFIX=$3
MEMORY_THRESHOLD=$4

############################################################
############## FUNCTIONS ################
############################################################

# Print usage info
help()
{
  echo "Usage: check-ecs-service <ecs cluster name> <region> <ecs service name prefix> <service memory threshold>"
}

# Bit hacky but good enough
check_prereqs()
{
  if [ -z "${CLUSTER}" ] || \
     [ -z "${REGION}" ]  || \
     [ -z "${SERVICE_PREFIX}" ]  || \
     [ -z "${MEMORY_THRESHOLD}" ]; then
    help
    exit 1
  fi
}

# get the ECS service name from the ARN
get_service_name()
{
  arn=$(get_service_arn)
  name=${arn#*/}

  echo "$name"
}

get_service_arn()
{
  service_arn=$(aws ecs list-services --cluster "${CLUSTER}" --region "${REGION}" --query 'serviceArns' |grep "${SERVICE_PREFIX}" |xargs)
  service_arn=${service_arn/%,/}  # remove trailing comma if it exists

  echo "${service_arn}"
}

get_memory_metric_for_service()
{
  # Gets the newest metric for the service for the last hour
  service_name=$1

  current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  one_hour_ago=$(date -u -d '1 hour ago' "+%Y-%m-%dT%H:%M:%SZ")

  metric=$(aws cloudwatch get-metric-statistics \
              --metric-name MemoryUtilization \
              --namespace AWS/ECS \
              --statistics Average \
              --dimensions Name=ClusterName,Value="${CLUSTER}" \
                           Name=ServiceName,Value="${service_name}" \
              --start-time "${one_hour_ago}" \
              --end-time "${current_time}" \
              --period 3600 \
              --query 'Datapoints[*].Average' \
              --output text \
              --region "${REGION}")

  printf -v rounded_metric %.0f "$metric"
  echo "${rounded_metric}"
}

############################################################
############## MAIN LINE ################
############################################################

check_prereqs

# Get the ECS service name
service_name=$(get_service_name)

if [ ! -z "${service_name}" ]; then
  echo "ECS service name found is ${service_name} - checking memory threshold"

  percent_memory_used=$(get_memory_metric_for_service "${service_name}")

  if [ ! -z "${percent_memory_used}" ]; then
    echo "Current memory utilization for service is ${percent_memory_used}% of reservation"

    if [ "${percent_memory_used}" -gt "${MEMORY_THRESHOLD}" ]; then
      echo "service is over threshold of ${MEMORY_THRESHOLD}% - cycling tasks"

      service_arn=$(get_service_arn)
      ./cycle-ecs-tasks.sh "${CLUSTER}" "${REGION}" "${service_arn}"
    else
        echo "service is not over threshold of ${MEMORY_THRESHOLD}% - no action needed"
    fi
  else
    echo "ERROR: Unable to get metrics from cloudwatch for service"
  fi
fi
