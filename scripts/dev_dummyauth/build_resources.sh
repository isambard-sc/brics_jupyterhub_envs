#!/bin/bash
set -euo pipefail

# shellcheck source=SCRIPTDIR/../common.sh
. scripts/common.sh

ENV_NAME="dev_dummyauth"
CONTAINER_BUILD_STAGE="stage-dev"

USAGE="
  ./build_resources.sh
"

# Validate number of arguments
if (( $# != 0 )); then
  echoerr "Error: incorrect number of arguments ($#)"
  echoerr
  echoerr "Usage: ${USAGE}"
  exit 1
fi 

# Get user and group for JupyterHub container volume from environment, or set defaults
: "${JUPYTERUSER:=root}"
: "${JUPYTERUSER_UID:=0}"
: "${JUPYTERGROUP:=root}"
: "${JUPYTERGROUP_GID:=0}"

# Get user and group for Slurm container volume from environment, or set defaults
: "${SLURMUSER:=slurm}"
: "${SLURMUSER_UID:=64030}"
: "${SLURMGROUP=slurm}"
: "${SLURMGROUP_GID:=64030}"

# Environment-specific directory containing initial volume contents
VOLUME_DIR="volumes/${ENV_NAME}"
if [[ ! -d ${VOLUME_DIR} ]]; then
  echoerr "Error: ${VOLUME_DIR} is not a directory"
  exit 1
fi

# If not already present, clone repositories to be mounted into dev images
clone_repo_skip_existing https://github.com/isambard-sc/bricsauthenticator.git brics_jupyterhub/_dev_build_data/bricsauthenticator
clone_repo_skip_existing https://github.com/isambard-sc/slurmspawner_wrappers.git brics_slurm/_dev_build_data/slurmspawner_wrappers

# Build local container images
podman build -t brics_jupyterhub:dev-latest --target=${CONTAINER_BUILD_STAGE} ./brics_jupyterhub
podman build -t brics_slurm:dev-latest --target=${CONTAINER_BUILD_STAGE} ./brics_slurm

# Create podman named volume containing JupyterHub data
create_podman_volume_from_dir jupyterhub_root_${ENV_NAME} "${JUPYTERUSER}:${JUPYTERUSER_UID}" "${JUPYTERGROUP}:${JUPYTERGROUP_GID}"  "${VOLUME_DIR}/jupyterhub_root/"

# Create podman named volume containing Slurm data
create_podman_volume_from_dir slurm_root_${ENV_NAME} "${SLURMUSER}:${SLURMUSER_UID}" "${SLURMGROUP}:${SLURMGROUP_GID}" "${VOLUME_DIR}/slurm_root/"
