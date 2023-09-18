#!/bin/bash

set -Eeuo pipefail

# Fail fast the deployment if envs are empty
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "The subscription Id is not successfully retrieved, please retry another deployment." >&2
  exit 1
fi

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "The resource group is not successfully retrieved, please retry another deployment." >&2
  exit 1
fi

if [[ -z "$ASA_SERVICE_NAME" ]]; then
  echo "The Azure Spring Apps service name is not successfully retrieved, please retry another deployment." >&2
  exit 1
fi

az extension add --name spring --upgrade

enableConfigServer() {
  az spring config-server enable --resource-group $RESOURCE_GROUP --name $ASA_SERVICE_NAME
  az spring config-server git set --resource-group $RESOURCE_GROUP --name $ASA_SERVICE_NAME --uri https://github.com/Azure-Samples/spring-petclinic-microservices-config.git --label master
}

enableEurekaServer() {
  az spring eureka-server enable --resource-group $RESOURCE_GROUP --name $ASA_SERVICE_NAME
}

enableConfigServer &
enableEurekaServer &

jobs_count=$(jobs -p | wc -l)

# Loop until all jobs are done
while [ $jobs_count -gt 0 ]; do
  wait -n
  exit_status=$?

  if [ $exit_status -ne 0 ]; then
    echo "One of the component activation failed with exit status $exit_status"
    exit $exit_status
  else
    jobs_count=$((jobs_count - 1))
  fi
done

echo "The managed components have been successfully enabled."
