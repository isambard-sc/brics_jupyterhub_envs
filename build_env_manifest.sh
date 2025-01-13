#!/bin/bash
set -euo pipefail

function echoerr { echo "$@" 1>&2; }

USAGE="
  ./build_env_manifest.sh <env_name> <output_dir>
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
OUTPUT_DIR=${2}
if [[ ! -d ${OUTPUT_DIR} ]]; then
  echoerr "Error: ${OUTPUT_DIR} is not a directory"
  exit 1
fi

# Environment-specific directory containing additional configuration data
CONFIG_DIR="config/${ENV_NAME}"
if [[ ! -d ${CONFIG_DIR} ]]; then
  echoerr "Error: ${CONFIG_DIR} is not a directory"
  exit 1
fi

# Execute environment-specific manifest build script
. ${CONFIG_DIR}/build_resources.sh "${OUTPUT_DIR}"