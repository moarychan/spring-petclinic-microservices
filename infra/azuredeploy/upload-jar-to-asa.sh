#!/bin/bash

#      Copyright (c) Microsoft Corporation.
#      Copyright (c) IBM Corporation. 
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#           http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

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

base_url="https://github.com/Azure-Samples/spring-petclinic-microservices/releases/download"
auth_header="no-auth"
version="3.0.1"
declare -a artifact_arr=("admin-server" "customers-service" "vets-service" "visits-service" "api-gateway")
declare -A app_relative_path_map
declare -A app_upload_url_map
az extension add --name spring --upgrade

initMap() {
  get_resource_upload_url_result=$(az rest -m post -u "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.AppPlatform/Spring/$ASA_SERVICE_NAME/apps/$1/getResourceUploadUrl?api-version=2023-05-01-preview")
  upload_url=$(echo $get_resource_upload_url_result | jq -r '.uploadUrl')
  relative_path=$(echo $get_resource_upload_url_result | jq -r '.relativePath')
  app_upload_url_map[$1]=$upload_url
  app_relative_path_map[$1]=$relative_path
}

uploadJar() {
  jar_file_name="$1-$version.jar"
  source_url="$base_url/v$version/$jar_file_name"
  auth_header="no-auth"

  storage_account_name=$(echo ${app_upload_url_map[$1]} | awk -F'[/.]' '{print $3}')
  storage_endpoint=$(echo ${app_upload_url_map[$1]} | awk -F'/' '{print "https://" $3}')
  share_name=$(echo ${app_upload_url_map[$1]} | awk -F'/' '{print $4}')
  folder=$(echo ${app_upload_url_map[$1]} | awk -F'?' '{print $1}' | awk -F'/' '{for(i=5;i<NF-1;i++) printf "%s/",$i; print $(NF-1)}')
  path=$(echo ${app_upload_url_map[$1]} | awk -F'[/?]' '{print $(NF-1)}')
  sas_token=$(echo ${app_upload_url_map[$1]} | awk -F'?' '{print $2}')

  # Download binary
  echo "Downloading binary from $source_url to $path"
  if [ "$auth_header" == "no-auth" ]; then
      curl -L "$source_url" -o $path
  else
      curl -H "Authorization: $auth_header" "$source_url" -o $path
  fi

  # Upload to remote
  echo "Upload '$source_url' to '$storage_account_name' at '$storage_endpoint/$share_name/$folder/$path'"

  echo "az storage file upload -s $share_name --source $path --account-name  $storage_account_name --file-endpoint $storage_endpoint --sas-token $sas_token -p $folder"

  az storage file upload -s $share_name --source $path --account-name  $storage_account_name --file-endpoint "$storage_endpoint" --sas-token "$sas_token"  -p "$folder"
}

for item in "${artifact_arr[@]}"
do
  initMap $item
  uploadJar $item &
done

jobs_count=$(jobs -p | wc -l)

# Loop until all jobs are done
while [ $jobs_count -gt 0 ]; do
  wait -n
  exit_status=$?

  if [ $exit_status -ne 0 ]; then
    echo "One of the deployment failed with exit status $exit_status"
    exit $exit_status
  else
    jobs_count=$((jobs_count - 1))
  fi
done

# Write outputs to deployment script output path
result=$(jq -n -c --arg adminServer "${app_relative_path_map[${artifact_arr[0]}]}" --arg customersService "${app_relative_path_map[${artifact_arr[1]}]}" --arg vetsService "${app_relative_path_map[${artifact_arr[2]}]}" --arg visitsService "${app_relative_path_map[${artifact_arr[3]}]}" --arg apiGateway "${app_relative_path_map[${artifact_arr[4]}]}" '{admin_server: $adminServer, customers_service: $customersService, vets_service: $vetsService, visits_service: $visitsService, api_gateway: $apiGateway}')
echo $result > $AZ_SCRIPTS_OUTPUT_PATH

echo "Uploaded successfully."

# Delete uami generated before exiting the script
az identity delete --ids ${AZ_SCRIPTS_USER_ASSIGNED_IDENTITY}
