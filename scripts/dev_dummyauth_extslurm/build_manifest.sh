#!/bin/bash
set -euo pipefail

# shellcheck source=SCRIPTDIR/../common.sh
. scripts/common.sh

ENV_NAME="dev_dummyauth_extslurm"

USAGE="
  ./build_manifest.sh <deploy_dir>
"

# Validate number of arguments
if (( $# != 1 )); then
  echoerr "Error: incorrect number of arguments ($#)"
  echoerr
  echoerr "Usage: ${USAGE}"
  exit 1
fi 

# Directory in which to place K8s manifest YAML and supporting data
DEPLOY_DIR=${1}
if [[ ! -d ${DEPLOY_DIR} ]]; then
  echoerr "Error: ${DEPLOY_DIR} is not a directory"
  exit 1
fi

# Environment-specific directory containing additional configuration data
CONFIG_DIR="config/${ENV_NAME}"
if [[ ! -d ${CONFIG_DIR} ]]; then
  echoerr "Error: ${CONFIG_DIR} is not a directory"
  exit 1
fi

cat > "${DEPLOY_DIR}/combined.yaml" <<EOF
$(make_ssh_key_secret_from_files "${DEPLOY_DIR}/ssh_client_key" "jupyterhub-slurm-ssh-client-key-${ENV_NAME}")
---
$(make_ssh_key_secret_from_files "${DEPLOY_DIR}/ssh_host_ed25519_key" "jupyterhub-slurm-ssh-host-key-${ENV_NAME}")
---
$(cat ${CONFIG_DIR}/pod.yaml)
EOF