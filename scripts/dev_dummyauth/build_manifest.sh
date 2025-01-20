#!/bin/bash
set -euo pipefail

. ../common.sh

ENV_NAME="dev_dummyauth"

USAGE="
  ./build_manifest.sh <output_dir>
"

# Validate number of arguments
if (( $# != 1 )); then
  echoerr "Error: incorrect number of arguments ($#)"
  echoerr
  echoerr "Usage: ${USAGE}"
  exit 1
fi 

# Directory in which to place K8s manifest YAML and supporting data
OUTPUT_DIR=${1}
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

cat > "${OUTPUT_DIR}/combined.yaml" <<EOF
$(make_dev_user_configmap ${CONFIG_DIR}/dev_users)
---
$(make_ssh_key_secret "${OUTPUT_DIR}/ssh_key" "JupyterHub-Slurm dev environment client key" "jupyterhub-slurm-ssh-client-key")
---
$(make_ssh_key_secret "${OUTPUT_DIR}/ssh_host_ed25519_key" "JupyterHub-Slurm dev environment host key" "jupyterhub-slurm-ssh-host-key")
---
$(cat ${CONFIG_DIR}/pod.yaml)
EOF