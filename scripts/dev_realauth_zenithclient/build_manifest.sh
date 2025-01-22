#!/bin/bash
set -euo pipefail

# shellcheck source=SCRIPTDIR/../common.sh
. scripts/common.sh

ENV_NAME="dev_realauth_zenithclient"

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
$(make_ssh_key_secret "${OUTPUT_DIR}/ssh_client_key" "JupyterHub-Slurm dev environment client key" "jupyterhub-slurm-ssh-client-key-${ENV_NAME}")
---
$(make_ssh_key_secret "${OUTPUT_DIR}/ssh_host_ed25519_key" "JupyterHub-Slurm dev environment host key" "jupyterhub-slurm-ssh-host-key-${ENV_NAME}")
---
$(make_ssh_key_secret_from_files "${OUTPUT_DIR}/ssh_zenith_client_key" "jupyterhub-slurm-ssh-zenith-client-key-${ENV_NAME}")
---
$(make_secret_from_file "${OUTPUT_DIR}/zenith_client_config.yaml" "client.yaml" "jupyterhub-slurm-zenith-client-config-${ENV_NAME}")
---
$(cat ${CONFIG_DIR}/pod.yaml)
EOF