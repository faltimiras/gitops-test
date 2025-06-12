#!/bin/bash

# Usage: ./script.sh <commit 1> <commit2>
# ENDPOINT_URL="http://ptsv3.com/t/alti-git-ops-test/post/"
DEPLOYMENT_METADATA_FILE="./deployment_config.yml"
NERDGRAPH=https://staging-api.newrelic.com/graphql
BLOB_API=https://blob-api.staging-service.newrelic.com


get_config_by_name() {
  VALUE=$(yq -r '
    .configurations[]
    | select(.files[] == "'$2'")
    | .'$1'
  ' "$DEPLOYMENT_METADATA_FILE")
  echo "$VALUE"
}


if [ $# -ne 2 ]; then
  echo "Usage: $0 <commit 1> <commit2>"
  exit 1
fi

#Get files that changed between the 2 commits
#NOW IT ONLY SUPPORTS ONE PR WITH 1 FILE!!!!
TARGET_FILE=$(git diff --name-only $1 $2)
echo "Files changed: $TARGET_FILE"


#Extracting configuration metadata if exist
FLEET_ID=$(get_config_by_name "fleetId" "$TARGET_FILE")

if [[ -z "$FLEET_ID" ]]; then
  echo "No configurations detected. Nothing to do"
  exit 1
fi

ORG_ID=$(get_config_by_name "orgId" "$TARGET_FILE")
AGENT_TYPE=$(get_config_by_name "agentType" "$TARGET_FILE")
MANAGED_ENTITY_TYPE=$(get_config_by_name "managedEntityType" "$TARGET_FILE")
CONFIG_NAME=$(get_config_by_name "name" "$TARGET_FILE")
echo "Config: $CONFIG_NAME, Fleet: $FLEET_ID, Org id: $ORG_ID, Agent type: $AGENT_TYPE, Manatee type: $MANAGED_ENTITY_TYPE"

#find if config is new or already exit
CONFIG_RS=$(curl $NERDGRAPH \
  -s -X POST \
  -H "Api-Key: $API_KEY" \
  -H 'NewRelic-Requesting-Services: NR_CONTROL' \
  -H 'content-type: application/json' \
  --data-raw $'{"query": "{ actor { entitySearch ( query: \\" domain = '\''NGEP'\'' and type = '\''AGENT_CONFIGURATION'\'' and name = '\'''$CONFIG_NAME''\'' \") {results {entities { guid } } count }}}"}')

COUNT=$(jq '.data.actor.entitySearch.count' <<< "$CONFIG_RS")
if [ -z "$COUNT" ]; then
  echo "Error: $CONFIG_RS"
  exit 1
elif [ "$COUNT" -eq 0 ]; then
  echo "No entity created with this name. Creating..."
  #TODO create entity
elif [ "$COUNT" -eq 1 ]; then
    CONFIG_ID=$(jq -r '.data.actor.entitySearch.results.entities[0].guid' <<< "$CONFIG_RS")
    echo "Config id: $CONFIG_ID"
else
  echo "More than one entity with this name. Not supported"
  exit 1
fi


#Upload config version
CONFIG_VERSION_RS=$(curl "$BLOB_API/v1/e/organizations/$ORG_ID/AgentConfigurations" \
 -s -X POST \
 -H "Content-Type: plain/text" \
 -H "Api-Key:$API_KEY" \
 -H "newrelic-entity:{\"agentConfiguration\": \"$CONFIG_ID\"}" \
 --data-binary @"$TARGET_FILE" )

CONFIG_VERSION_ID=$(jq -r '.blobVersionEntity.entityGuid' <<< "$CONFIG_VERSION_RS")
if [ -z "$CONFIG_VERSION_ID" ] || [ "$CONFIG_VERSION_ID" = "null" ]; then
  echo "Error: Config version response: $CONFIG_VERSION_RS"
  exit 1
fi
echo "Config version id: $CONFIG_VERSION_ID"

sleep 10 #We need to wait some time, to give time EP to process the config version async

#Create deployment entity
DEPLOYMENT_RS=$(curl $NERDGRAPH \
  -s -X POST \
  -H "Api-Key: $API_KEY" \
  -H 'NewRelic-Requesting-Services: NR_CONTROL' \
  -H 'content-type: application/json' \
  --data-raw $'{"query":"mutation FleetV2CreateDeployment($name:String!$description:String$fleetGuid:ID!$configurationVersionList:[EntityManagementDeploymentAgentConfigurationVersionCreateInput]$scopeId:ID!$scopeType:EntityManagementEntityScope!){entityManagementCreateFleetDeployment(fleetDeploymentEntity:{name:$name description:$description fleetId:$fleetGuid configurationVersionList:$configurationVersionList scope:{id:$scopeId type:$scopeType}}){entity{id}}}","variables":{"scopeId":"'"$ORG_ID"'","scopeType":"ORGANIZATION","name":"git-ops '"$(date)"'","description":"","fleetGuid":"'"$FLEET_ID"'","configurationVersionList":[{"id":"'"$CONFIG_VERSION_ID"'"}]}}')

DEPLOYMENT_ID=$(jq -r '.data.entityManagementCreateFleetDeployment.entity.id' <<< "$DEPLOYMENT_RS")
if [ -z "$DEPLOYMENT_ID" ] || [ "$DEPLOYMENT_ID" = "null" ]; then
  echo "Error: Deployment response: $DEPLOYMENT_RS"
  exit 1
fi
echo "Deployment id: $DEPLOYMENT_ID"

#Trigger deployment 
DEPLOY_RS=$(curl $NERDGRAPH \
  -s -X POST \
  -H "Api-Key: $API_KEY" \
  -H 'NewRelic-Requesting-Services: NR_CONTROL' \
  -H 'content-type: application/json; charset=utf-8' \
  --data-raw $'{"query":"mutation deployFleet($deploymentId:ID!$fleetGuid:ID!$policy:[String!]){fleetControlDeployFleet(deploymentId:$deploymentId fleetId:$fleetGuid policy:{ringDeploymentPolicy:{ringsToDeploy:$policy}}){fleetGuid}}","variables":{"deploymentId":"'"$DEPLOYMENT_ID"'","fleetGuid":"'"$FLEET_ID"'","policy":["canary","default"]}}')
  
echo "Done \o/"
