#!/bin/bash
set -euo pipefail

. ../common.sh

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
podman build -t brics_jupyterhub:${ENV_NAME}-latest --target=${CONTAINER_BUILD_STAGE} ./brics_jupyterhub
podman build -t brics_slurm:${ENV_NAME}-latest --target=${CONTAINER_BUILD_STAGE} ./brics_slurm

# TODO Create and use common function to create podman named volume 
# Create podman named volume containing JupyterHub data
podman volume create jupyterhub_root_${ENV_NAME}
if [[ $(uname) == "Darwin" ]]; then
  # podman volume import not available using remote client, so run podman inside VM
  # BSD tar
  tar --cd "${VOLUME_DIR}/jupyterhub_root/" --create \
    --exclude .gitkeep \
    --uname "${JUPYTERUSER}" --uid "${JUPYTERUSER_UID}" \
    --gname "${JUPYTERGROUP}" --gid "${JUPYTERGROUP_GID}" \
    --file - . | podman machine ssh podman volume import jupyterhub_root_${ENV_NAME} -
else
  # GNU tar
  tar -C "${VOLUME_DIR}/jupyterhub_root/" --create \
    --exclude .gitkeep \
    --owner="${JUPYTERUSER}":"${JUPYTERUSER_UID}" \
    --group="${JUPYTERGROUP}":"${JUPYTERGROUP_GID}" \
    --file - . | podman volume import jupyterhub_root_${ENV_NAME} -
fi

# Create podman named volume containing Slurm data
podman volume create slurm_root_${ENV_NAME}
if [[ $(uname) == "Darwin" ]]; then
  # podman volume import not available using remote client, so run podman inside VM
  # BSD tar
  tar --cd "${VOLUME_DIR}/slurm_root/" --create \
    --exclude .gitkeep \
    --uname "${SLURMUSER}" --uid "${SLURMUSER_UID}" \
    --gname "${SLURMGROUP}" --gid "${SLURMGROUP_GID}" \
    --file - . | podman machine ssh podman volume import slurm_root_${ENV_NAME} -
else
  # GNU tar
  tar -C "${VOLUME_DIR}"/slurm_root/ --create \
    --exclude .gitkeep \
    --owner="${SLURMUSER}:${SLURMUSER_UID}" \
    --group="${SLURMGROUP}:${SLURMGROUP_GID}" \
    --file - . | podman volume import slurm_root_${ENV_NAME} -
fi