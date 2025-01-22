#!/bin/bash
set -euo pipefail

function echoerr { echo "$@" 1>&2; }

USAGE="
  ./build_env_manifest.sh <env_name> <deploy_dir>
"

# Validate number of arguments
if (( $# != 2 )); then
  echoerr "Error: incorrect number of arguments ($#)"
  echoerr
  echoerr "Usage: ${USAGE}"
  exit 1
fi 

ENV_NAME=${1}

# Directory in which to place K8s manifest YAML and supporting data
DEPLOY_DIR=${2}
if [[ ! -d ${DEPLOY_DIR} ]]; then
  echoerr "Error: ${DEPLOY_DIR} is not a directory"
  exit 1
fi

# Environment-specific directory containing deployment scripts
SCRIPTS_DIR="scripts/${ENV_NAME}"
if [[ ! -d ${SCRIPTS_DIR} ]]; then
  echoerr "Error: ${SCRIPTS_DIR} is not a directory"
  exit 1
fi

# Execute environment-specific manifest build script
exec bash "${SCRIPTS_DIR}/build_manifest.sh" "${DEPLOY_DIR}"