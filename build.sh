#!/bin/bash

IMAGE_EXT_IMPORT_DFLOW=`grep ^IMAGE_EXT_IMPORT_DFLOW ../.env | cut -d = -f 2`
AFFIRMATIVE="yes"
echo "Do you want to build the \"${IMAGE_EXT_IMPORT_DFLOW}\" image ("${AFFIRMATIVE}"/no)? " | tr -d '\n'
read answer
if [[ $answer = "${AFFIRMATIVE}" ]]; then
  echo "Building ${IMAGE_EXT_IMPORT_DFLOW} ..."
  docker build -t ${IMAGE_EXT_IMPORT_DFLOW} .
else
  echo "No build executed."
fi

