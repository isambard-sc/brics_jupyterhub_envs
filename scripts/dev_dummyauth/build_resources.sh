#!/bin/bash
set -euo pipefail

# shellcheck source=SCRIPTDIR/../common.sh
. scripts/common.sh

ENV_NAME="dev_dummyauth"
CONTAINER_BUILD_STAGE="stage-dev"
JUPYTERHUB_IMAGE_TAG="dev-latest"
SLURM_IMAGE_TAG="dev-latest"

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
# TODO Replace sourcing argfile.conf in a subshell and specifying individual
#   --build-arg values with use of --build-arg-file argfile.conf when >= buildah
#   1.30 can be assumed. Support for --build-arg-file was added in buildah 
#   1.30.0 which is included in podman v4.5.0, see:
#   https://buildah.io/releases/#buildah-version-1300-release-announcement
#   https://github.com/containers/podman/releases/tag/v4.5.0
#podman build -t brics_jupyterhub:${JUPYTERHUB_IMAGE_TAG} --build-arg-file ./brics_jupyterhub/argfile.conf --target=${CONTAINER_BUILD_STAGE} ./brics_jupyterhub
#podman build -t brics_slurm:${SLURM_IMAGE_TAG} --build-arg-file ./brics_slurm/argfile.conf --target=${CONTAINER_BUILD_STAGE} ./brics_slurm
(
source ./brics_jupyterhub/argfile.conf
podman build -t brics_jupyterhub:${JUPYTERHUB_IMAGE_TAG} \
  --target=${CONTAINER_BUILD_STAGE} \
  --build-arg=JUPYTERHUB_BASE_TAG=${JUPYTERHUB_BASE_TAG} \
  --build-arg=BRICSAUTHENTICATOR_TAG=${BRICSAUTHENTICATOR_TAG} \
  ./brics_jupyterhub
)
(
source ./brics_slurm/argfile.conf
podman build -t brics_slurm:${SLURM_IMAGE_TAG} \
  --build-arg-file ./brics_slurm/argfile.conf \
  --target=${CONTAINER_BUILD_STAGE} \
  --build-arg=SLURM_BASE_TAG=${SLURM_BASE_TAG} \
  --build-arg=SLURMSPAWNER_WRAPPERS_TAG=${SLURMSPAWNER_WRAPPERS_TAG} \
  ./brics_slurm
)

# Create podman named volume containing JupyterHub data
create_podman_volume_from_dir jupyterhub_root_${ENV_NAME} "${JUPYTERUSER}:${JUPYTERUSER_UID}" "${JUPYTERGROUP}:${JUPYTERGROUP_GID}"  "${VOLUME_DIR}/jupyterhub_root/"

# Create podman named volume containing Slurm data
create_podman_volume_from_dir slurm_root_${ENV_NAME} "${SLURMUSER}:${SLURMUSER_UID}" "${SLURMGROUP}:${SLURMGROUP_GID}" "${VOLUME_DIR}/slurm_root/"
