#!/usr/local/bin/bash

CLUSTER=$1
REGION=$2
PROFILE=$3
SERVICE_PREFIX=$4

declare -A tasksSeen

#Algo

# Find the service from the pattern passed in
# list the tasks in the service and save off the task IDs
# for each task
#    Kill it
#    Wait for a new one

# Stops an ECS task and waits for a replacement to come online
stop_task()
{
  task_arn=$1
  retval=0

  echo "Stopping ${task_arn}" >&2

  aws ecs stop-task --cluster ${CLUSTER} --region ${REGION} --profile ${PROFILE} --task ${task_arn} --reason "killed by monitor"
  status=$?

  if [ ${status} -eq 0 ]; then
    retval=0
  else
    retval=1
  fi

  echo ${retval}
}

list_tasks()
{
  service=$1

  tasks=$(aws ecs list-tasks --cluster ${CLUSTER} --region ${REGION} --profile ${PROFILE} --service-name ${service} --query 'taskArns' --output text)

  echo "${tasks}"
}

get_task_status()
{
  task_arn=$1
  task_status=""

  task_status=$(aws ecs describe-tasks --cluster ${CLUSTER} --region ${REGION} --profile ${PROFILE} --tasks ${task_arn} --output text --query 'tasks[0].lastStatus')

  echo "${task_status}"
}


# Step 1 - get the ARN of the service we are intersted in
service_arn=$(aws ecs list-services --cluster ${CLUSTER} --region ${REGION} --profile ${PROFILE} --query 'serviceArns' |grep ${SERVICE_PREFIX} |xargs)

if [ ! -z "${service_arn}" ]; then
  service_arn=${service_arn/%,/}  # remove trailing comma if it exists
  echo "service arn found: ${service_arn}"

  # Step 2 - list the tasks assigned to this service
  tasks=$(list_tasks "${service_arn}")
  beginning_number_of_tasks=$(echo ${tasks} |wc -w |xargs)

  echo "There are currently ${beginning_number_of_tasks} tasks running for this service"
  echo "Initial tasks: ${tasks}"

  for task in ${tasks}
  do
    # We need to stop each task and then wait for a replacement before stopping the next one
    echo "calling STOP on task: ${task}"
    #status=0
    status=$(stop_task ${task})
    status=$?

    if [ "${status}" -eq 0 ]; then
      # task stopped ok...now wait until we get a new task in the RUNNING condition
      echo "Task stopped ok"

      current_number_of_tasks=0
      tasksSeen=()
      # Loop while we do not have the same number of RUNNING tasks as we originally had
      while (( ${current_number_of_tasks} < ${beginning_number_of_tasks} ))
      do
        current_tasks=$(list_tasks "${service_arn}")

        for current_task in ${current_tasks}
        do
          if [ "${tasksSeen[${current_task}]+exists}" == "exists" ]; then
            echo "task ${current_task} has already been seen"
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
fi

#aws cloudwatch get-metric-statistics --metric-name MemoryUtilization --namespace AWS/ECS --statistics Average --dimensions Name=ClusterName,Value=Signiant-ECS-DEV1-us-east1 Name=ServiceName,Value=storage-server-communicator-service-endeavour-SSCOMMSRVConfig-B9BS3ONDP0WX --start-time 2016-08-10T00:00:00 --end-time 2016-08-10T23:59:59 --period 3600

#aws ecs list-services --cluster Signiant-ECS-DEV1-us-east1 --profile dev1 --region us-east-1

#aws ecs list-tasks --cluster Signiant-ECS-DEV1-us-east1 --service-name arn:aws:ecs:us-east-1:367384020442:service/storage-server-communicator-service-endeavour-SSCOMMSRVConfig-B9BS3ONDP0WX --profile dev1 --region us-east-1

#aws ecs stop-task --cluster Signiant-ECS-DEV1-us-east1 --task arn:aws:ecs:us-east-1:367384020442:task/3daa818a-11fc-4da0-92b5-ec26f255fcc2 --reason memory --region us-east-1 --profile dev1

#aws ecs describe-tasks --cluster Signiant-ECS-DEV1-us-east1 --tasks arn:aws:ecs:us-east-1:367384020442:task/de525be5-822a-4ab1-bd9a-7cea4deefe70 --region us-east-1 --profile dev1
