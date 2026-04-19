#!/bin/bash

# Set variables
projectId="$1"
apiKey="$2"
artifactId="$3"
targetEnvironmentAlias="$4"
commitMessage="$5"
skipPreserveUmbracoCloudJson="${6:-false}"
noBuildAndRestore="${7:-false}"
skipVersionCheck="${8:-false}"
runSchemaExtraction="${9:-true}"
pipelineVendor="${10}"

# Not required, defaults to https://api.dev-cloud.umbraco.com
baseUrl="${11:-https://api.dev-cloud.umbraco.com}"

# Optional — identifies the container image used to execute the deployment on Cloud.
# Required when deploying a pre-built publish artifact (zip-deploy flow).
dockerImageTag="${12:-}"


### Endpoint docs
# https://docs.umbraco.com/umbraco-cloud/set-up/project-settings/umbraco-cicd/umbracocloudapi/todo-v2
#
url="$baseUrl/v2/projects/$projectId/deployments"

# Define function to call API to start thedeployment
function call_api {
  echo "Requesting start Deployment at $url with options:"
  echo " - targetEnvironmentAlias: $targetEnvironmentAlias"
  echo " - artifactId: $artifactId"
  echo " - commitMessage: $commitMessage"
  echo " - skipPreserveUmbracoCloudJson: $skipPreserveUmbracoCloudJson"
  echo " - noBuildAndRestore: $noBuildAndRestore"
  echo " - skipVersionCheck: $skipVersionCheck"
  echo " - runSchemaExtraction: $runSchemaExtraction"
  echo " - dockerImageTag: $dockerImageTag"

  body=$(jq -n \
    --arg targetEnvironmentAlias "$targetEnvironmentAlias" \
    --arg artifactId "$artifactId" \
    --arg commitMessage "$commitMessage" \
    --arg dockerImageTag "$dockerImageTag" \
    --argjson noBuildAndRestore "$noBuildAndRestore" \
    --argjson skipVersionCheck "$skipVersionCheck" \
    --argjson runSchemaExtraction "$runSchemaExtraction" \
    --argjson skipPreserveUmbracoCloudJson "$skipPreserveUmbracoCloudJson" \
    '{
      targetEnvironmentAlias: $targetEnvironmentAlias,
      artifactId: $artifactId,
      commitMessage: $commitMessage,
      noBuildAndRestore: $noBuildAndRestore,
      skipVersionCheck: $skipVersionCheck,
      runSchemaExtraction: $runSchemaExtraction,
      skipPreserveUmbracoCloudJson: $skipPreserveUmbracoCloudJson,
      dockerImageTag: $dockerImageTag
    }')

  response=$(curl -s -w "%{http_code}" -X POST $url \
    -H "Umbraco-Cloud-Api-Key: $apiKey" \
    -H "Content-Type: application/json" \
    -d "$body")

  responseCode=${response: -3}  
  content=${response%???}

  echo "--- --- ---"
  echo "Response:"
  echo $content

  if [[ 10#$responseCode -eq 201 ]]; then
    deployment_id=$(echo "$content" | jq -r '.deploymentId')

    if [[ "$pipelineVendor" == "GITHUB" ]]; then
      echo "deploymentId=$deployment_id" >> "$GITHUB_OUTPUT"
    elif [[ "$pipelineVendor" == "AZUREDEVOPS" ]]; then
      echo "##vso[task.setvariable variable=deploymentId;isOutput=true]$deployment_id"
    elif [[ "$pipelineVendor" == "TESTRUN" ]]; then
      echo $pipelineVendor
    else
      echo "Please use one of the supported Pipeline Vendors or enhance script to fit your needs"
      echo "Currently supported are: GITHUB and AZUREDEVOPS"
      exit 1
    fi

    echo "--- --- ---"
    echo "Deployment started successfully -> $deployment_id"
    exit 0
  fi

  ## Let errors bubble forward 
  errorResponse=$content
  echo "Unexpected API Response Code: $responseCode - More details below"
  # Check if the input is valid JSON
  cat "$errorResponse" | jq . > /dev/null 2>&1
  if [ $? -ne 0 ]; then
      echo "--- Response RAW ---\n"
      cat "$errorResponse"
  else 
      echo "--- Response JSON formatted ---\n"
      cat "$errorResponse" | jq .
  fi
  echo "\n---Response End---"
  exit 1
}

call_api

