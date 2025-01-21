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

# Environment-specific directory containing deployment scripts
SCRIPTS_DIR="scripts/${ENV_NAME}"
if [[ ! -d ${SCRIPTS_DIR} ]]; then
  echoerr "Error: ${SCRIPTS_DIR} is not a directory"
  exit 1
fi

# Execute environment-specific resource build script
exec bash "${SCRIPTS_DIR}/build_resources.sh"