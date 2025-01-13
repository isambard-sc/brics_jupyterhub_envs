#!/bin/bash
set -euo pipefail

function echoerr { echo "$@" 1>&2; }

USAGE="
  ./build_env_resources.sh <env_name>
"

# Validate number of arguments
if (( $# != 1 )); then
  echoerr "Error: incorrect number of arguments ($#)"
  echoerr
  echoerr "Usage: ${USAGE}"
  exit 1
fi 

ENV_NAME=${1}

# Environment-specific directory containing additional configuration data
CONFIG_DIR="config/${ENV_NAME}"
if [[ ! -d ${CONFIG_DIR} ]]; then
  echoerr "Error: ${CONFIG_DIR} is not a directory"
  exit 1
fi

# Execute environment-specific resource build script
. ${CONFIG_DIR}/build_resources.sh