#!/bin/bash

# Usage: ./script.sh <commit 1> <commit2>
ENDPOINT_URL="http://ptsv3.com/t/alti-git-ops-test/post/"

if [ $# -ne 2 ]; then
  echo "Usage: $0 <commit 1> <commit2>"
  exit 1
fi


git diff --name-only $1 $2 > changed_files.txt


YAML_FILE="./deployment_config.yml"
TARGET_FILE=$(cat changed_files.txt)

echo $TARGET_FILE
export TARGET_FILE

FLEET_GUID=$(yq -r '
 .configurations[]
  | select(.files[] == env(TARGET_FILE))
  | .fleetGuid
' "$YAML_FILE")

echo $FLEET_GUID

curl -X POST "$ENDPOINT_URL" --data-binary @"$TARGET_FILE" -H "Content-Type: text/plain" -H "Api-Key:$API_KEY" -H "fleetGuid:$FLEET_GUID"

rm changed_files.txt