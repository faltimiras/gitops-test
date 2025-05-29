#!/bin/bash

# Usage: ./script.sh <file_path>
ENDPOINT_URL="http://ptsv3.com/t/alti-git-ops-test/post/"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <file_path>"
  exit 1
fi

FILE_PATH="$1"

if [ ! -f "$FILE_PATH" ]; then
  echo "File not found: $FILE_PATH"
  exit 2
fi

curl -X POST "$ENDPOINT_URL" --data-binary @"$FILE_PATH" -H "Content-Type: text/plain"