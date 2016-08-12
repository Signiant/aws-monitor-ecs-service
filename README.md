# monitor-ecs-service
Monitors an ECS service for memory use and cycles the tasks if the memory use is over a threshold

# Purpose
We've got a service/task running on AWS that has a small memory leak.  Over time, it causes the service to eventually reach the memory reservation and get killed.  We have an alarm set before this that pages us at ungodly hours so we can manually cycle the tasks and not take the service out of service.

However....manual work sucks. So we've developed this solution which will auto-cycle the tasks, one at a time, on an ECS service if a memory threshold is reached.  Auto-remediation!


# Prerequisites
* Docker must be installed
* A [config file](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) containing profiles needs to be configured for the AWS CLI

# Usage

The easiest way to run the tool is from docker (because docker rocks).  You will need to bind mount the AWS config file and pass in variables specific to the ECS service you want to affect

```bash
docker pull signiant/monitor-ecs-service
```

```bash
docker run \
  -v ~/.aws/credentials:/root/.aws/credentials:ro  \
   signiant/monitor-ecs-service \
        my_ecs_cluster \
        us-east-1 \
        development \
        my-ecs-service-prefix \
        70
```

In this example, we use a bindmount to mount in the aws cli configuration (containing profiles) config file from a local folder to the container.  The other arguments after the image name are

* ECS cluster name
* AWS region
* AWS CLI profile name
* Prefix of an ECS service
* Memory threshold to take action on

In the above example, we query the cluster for a service beginning with mys-ecs-service-prefix (done this way because cloudformation generated services have a random suffix appended).  Once we have found the service, we check the metrics for the last hour and if we are over 70% of the memory reservation, cycle each task currently running for the service, one at a time.
