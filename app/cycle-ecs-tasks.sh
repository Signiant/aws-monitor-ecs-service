#!/bin/bash

# Input parameters
#   1 - The name of the ECS cluster the service is running in
#   2 - the region the ECS cluster is running in (ie. us-east-1)
#   3 - A prefix to match an ECS service (must map to ONLY ONE service)

CLUSTER=$1
REGION=$2
SERVICE_ARN=$3

# track where we've already seen a task ID
declare -A tasksSeen

# Main algorithm:
#    Find the ECS service from the pattern passed in
#    list the tasks running for this service
#    for each task
#      stop it
#      Wait for a new one to start

############################################################
############## FUNCTIONS ################
############################################################

# Stops an ECS task
stop_task()
{
  task_arn=$1
  retval=0

  echo "Stopping ${task_arn}" >&2

  aws ecs stop-task --cluster ${CLUSTER} --region ${REGION} --task ${task_arn} --reason "killed by monitor"
  status=$?

  if [ ${status} -eq 0 ]; then
    retval=0
  else
    retval=1
  fi

  echo ${retval}
}

# List the ECS tasks for a service
list_tasks()
{
  service=$1

  tasks=$(aws ecs list-tasks --cluster ${CLUSTER} --region ${REGION} --service-name ${service} --query 'taskArns' --output text)

  echo "${tasks}"
}

# Get the status of a task
get_task_status()
{
  task_arn=$1
  task_status=""

  task_status=$(aws ecs describe-tasks --cluster ${CLUSTER} --region ${REGION} --tasks ${task_arn} --output text --query 'tasks[0].lastStatus')

  echo "${task_status}"
}

############################################################
############## MAIN LINE ################
############################################################

if [ ! -z "${SERVICE_ARN}" ]; then
  service_arn=${SERVICE_ARN/%,/}  # remove trailing comma if it exists
  echo "service arn: ${SERVICE_ARN}"

  # Step 2 - list the tasks assigned to this service
  tasks=$(list_tasks "${SERVICE_ARN}")
  beginning_number_of_tasks=$(echo ${tasks} |wc -w |xargs)

  echo "There are currently ${beginning_number_of_tasks} tasks running for this service"
  echo "Initial tasks: ${tasks}"

  # This the main guts...basically, replace each running task one at a time
  # And do not kill the next task until a replacement has been launched
  for task in ${tasks}
  do
    echo "**** Stopping task: ${task}"
    status=$(stop_task ${task})
    status=$?

    if [ "${status}" -eq 0 ]; then
      # task stopped ok...now wait until we get a new task in the RUNNING state
      echo "Task ${task} stopped OK"

      # Track the current number of running tasks and an array to keep track
      # of which ones we've seen running
      current_number_of_tasks=0
      tasksSeen=()

      # Loop while we do not have the same number of RUNNING tasks as we originally had
      while (( ${current_number_of_tasks} < ${beginning_number_of_tasks} ))
      do
        current_tasks=$(list_tasks "${SERVICE_ARN}")

        for current_task in ${current_tasks}
        do
          if [ "${tasksSeen[${current_task}]+exists}" == "exists" ]; then
            echo "task ${current_task} has already been seen and is RUNNING. Waiting for new task to start..."
          else
            # is this task RUNNING?
            task_state=$(get_task_status ${current_task})
            echo "task: ${current_task} state: ${task_state}"

            if [ "${task_state}" == "RUNNING" ]; then
              tasksSeen[${current_task}]=1
              current_number_of_tasks=$((${current_number_of_tasks}+1))
            fi
          fi
        done
        sleep 1
      done
    else
      echo "error stopping task"
    fi
  done
else
  echo "Unable to find an ECS service in cluster ${CLUSTER} with ARN ${SERVICE_ARN}"
fi
