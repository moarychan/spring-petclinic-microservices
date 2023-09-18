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

az spring config-server enable --subscription $SUBSCRIPTION_ID --resource-group $RESOURCE_GROUP --name $ASA_SERVICE_NAME
az spring eureka-server enable --subscription $SUBSCRIPTION_ID --resource-group $RESOURCE_GROUP --name $ASA_SERVICE_NAME
az spring config-server git set --subscription $SUBSCRIPTION_ID --resource-group $RESOURCE_GROUP --name $ASA_SERVICE_NAME --uri https://github.com/Azure-Samples/spring-petclinic-microservices-config.git --label master

echo "The managed components have been successfully enabled."
