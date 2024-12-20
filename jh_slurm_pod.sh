#!/bin/bash
set -euo pipefail

function echoerr { echo "$@" 1>&2; }

USAGE="
  ./jh_slurm_pod.sh up <env_name>
  ./jh_slurm_pod.sh down\
"

# Get user and group for JupyterHub container volume from environment, or set defaults
: ${JUPYTERUSER:=root}
: ${JUPYTERUSER_UID:=0}
: ${JUPYTERGROUP:=root}
: ${JUPYTERGROUP_GID:=0}

# Get user and group for Slurm container volume from environment, or set defaults
: ${SLURMUSER:=slurm}
: ${SLURMUSER_UID:=64030}
: ${SLURMGROUP=slurm}
: ${SLURMGROUP_GID:=64030}

# Creates a passwordless SSH key, then writes a K8s manifest for a Secret 
# containing the key data to stdout. The filename for the key to be written, the
# comment to add to the key, and name for the K8s Secret should be provided as
# arguments.
#
# The Secret will have 2 keys under stringData, containing the private and public
# parts of the SSH key named ssh_key and ssh_key.pub. 
#
# 2 additional entries are present included for convenience:
# 
# * A key named localhost_known_hosts contains an OpenSSH ssh_known_hosts-format
#   entry for localhost (hostname and IPv4/IPv6 addresses) with the public key. 
# * A key named localhost_authorized_keys contains and OpenSSH 
#   authorized_keys-format entry containing the public key restricted for access
#   from localhost (hostname and IPv4/IPv6 addresses) 
# 
# Usage:
#    make_ssh_key_secret <filename> <key comment> <secret name>
function make_ssh_key_secret {
  if (( $# != 3 )); then
    echoerr "Error: expected 3 arguments, but got $#" 1>&2
    exit 1
  fi
  if [[ -a ${1} ]]; then
    echoerr "Error: ${1} already exists"
    exit 1
  fi
  ssh-keygen -t ed25519 -f "${1}" -N "" -C "${2}" >/dev/null 2>&1
  cat <<EOF
apiVersion: core/v1
kind: Secret
metadata:
  name: ${3}
stringData:
  ssh_key: |
$(cat ${1} | sed -E -e 's/^/    /')
  ssh_key.pub: |
$(cat ${1}.pub | sed -E -e 's/^/    /')
  localhost_known_hosts: |
$(cat <(printf "%s" "localhost,127.0.0.1,::1 ") ${1}.pub | sed -E -e 's/^/    /')
  localhost_authorized_keys: |
$(cat <(printf "%s" 'from="localhost,127.0.0.1,::1" ') ${1}.pub | sed -E -e 's/^/    /')
immutable: true
EOF
}

# Creates an immutable ConfigMap named "dev-user-config" containing a list of
# test Unix user account names to be consumed by the containers in the 
# environment (e.g. to create user accounts in Slurm container or to define
# users allowed to authenticate in JupyterHub;s configuration). The ConfigMap is
# written to stdout.
#
# A newline-separated list of user account names is read in from the file
# provided as first argument and converted to a space-separated value for the
# DEV_USER_CONFIG_UNIX_USERNAMES data key. It is expected that the key will be
# used to populate an environment variable within containers.
#
# Usage:
#    make_dev_user_configmap <user list file>
function make_dev_user_configmap {
  if (( $# != 1 )); then
    echoerr "Error: expected 1 arguments, but got $#"
    exit 1
  fi
  if [[ ! -e ${1} ]]; then
    echoerr "Error: ${1} does not exist"
    exit 1
  fi
  cat <<EOF
apiVersion: core/v1
kind: ConfigMap
metadata:
  name: dev-user-config
data:
  DEV_USER_CONFIG_UNIX_USERNAMES: "$(tr "\n" " " < ${1} | sed -E -e 's/\s+$//')"
immutable: true
EOF
}

# Bring up the environment with name specified in first argument
#
# Prepare necessary resources (e.g. clone repositories, create volumes),
# construct K8s manifest YAML, bring up podman pod.
#
# The <env_name> is used to construct paths to environment specific volume
# and configuration data, e.g. volumes/<env_name> and config/<env_name>
#
# Usage:
#    bring_pod_up <env_name>
function bring_pod_up {
  if (( $# != 1 )); then
    echoerr "Error: expected 1 arguments, but got $#"
    exit 1
  fi

  # Environment-specific directory containing initial volume contents
  local VOLUME_DIR="volumes/${1}"
  if [[ ! -d ${VOLUME_DIR} ]]; then
    echoerr "Error: ${VOLUME_DIR} is not a directory"
    exit 1
  fi

  # Environment-specific directory containing additional configuration data
  local CONFIG_DIR="config/${1}"
  if [[ ! -d ${CONFIG_DIR} ]]; then
    echoerr "Error: ${CONFIG_DIR} is not a directory"
    exit 1
  fi

  # Make a temporary directory under ./_build_tmp to store ephemeral build data
  mkdir -p -v _build_tmp/
  local BUILD_TMPDIR=$(mktemp -d "_build_tmp/jh_slurm_pod_${1}.XXXXXXXXXX")
  echo "Temporary build data directory: ${BUILD_TMPDIR}"

  # If not already present, clone repositories to be mounted into dev images
  mkdir -p -v brics_jupyterhub/_dev_build_data
  if [[ ! -d brics_jupyterhub/_dev_build_data/bricsauthenticator ]]; then
    echo "Cloning fresh bricsauthenticator repository"
    git clone https://github.com/isambard-sc/bricsauthenticator.git brics_jupyterhub/_dev_build_data/bricsauthenticator
  else
    echo "Skipping clone of bricsauthenticator: existing directory found"
  fi

  mkdir -p -v brics_slurm/_dev_build_data
  if [[ ! -d brics_slurm/_dev_build_data/slurmspawner_wrappers ]]; then
    echo "Cloning fresh slurmspawner_wrappers repository"
    git clone https://github.com/isambard-sc/slurmspawner_wrappers.git brics_slurm/_dev_build_data/slurmspawner_wrappers
  else
    echo "Skipping clone of slurmspawner_wrappers: existing directory found"
  fi

  # Build local container images
  podman build -t brics_jupyterhub:dev-latest --target=stage-dev ./brics_jupyterhub
  podman build -t brics_slurm:dev-latest --target=stage-dev ./brics_slurm

  # Create podman named volume containing JupyterHub data
  podman volume create jupyterhub_root
  if [[ $(uname) == "Darwin" ]]; then
    # podman volume import not available using remote client, so run podman inside VM
    # BSD tar
    tar --cd "${VOLUME_DIR}/jupyterhub_root/" --create \
      --exclude .gitkeep \
      --uname ${JUPYTERUSER} --uid ${JUPYTERUSER_UID} \
      --gname ${JUPYTERGROUP} --gid ${JUPYTERGROUP_GID} \
      --file - . | podman machine ssh podman volume import jupyterhub_root -
  else
    # GNU tar
    tar -C "${VOLUME_DIR}/jupyterhub_root/" --create \
      --exclude .gitkeep \
      --owner=${JUPYTERUSER}:${JUPYTERUSER_UID} \
      --group=${JUPYTERGROUP}:${JUPYTERGROUP_GID} \
      --file - . | podman volume import jupyterhub_root -
  fi

  # Create podman named volume containing Slurm data
  podman volume create slurm_root
  if [[ $(uname) == "Darwin" ]]; then
    # podman volume import not available using remote client, so run podman inside VM
    # BSD tar
    tar --cd "${VOLUME_DIR}/slurm_root/" --create \
      --exclude .gitkeep \
      --uname ${SLURMUSER} --uid ${SLURMUSER_UID} \
      --gname ${SLURMGROUP} --gid ${SLURMGROUP_GID} \
      --file - . | podman machine ssh podman volume import slurm_root -
  else
    # GNU tar
    tar -C "${VOLUME_DIR}"/slurm_root/ --create \
      --exclude .gitkeep \
      --owner=${SLURMUSER}:${SLURMUSER_UID} \
      --group=${SLURMGROUP}:${SLURMGROUP_GID} \
      --file - . | podman volume import slurm_root -
  fi
  
  # Create combined manifest file with generated Secrets and Pod
  cat > "${BUILD_TMPDIR}/combined.yaml" <<EOF
$(make_dev_user_configmap ${CONFIG_DIR}/dev_users)
---
$(make_ssh_key_secret "${BUILD_TMPDIR}/ssh_key" "JupyterHub-Slurm dev environment client key" "jupyterhub-slurm-ssh-client-key")
---
$(make_ssh_key_secret "${BUILD_TMPDIR}/ssh_host_ed25519_key" "JupyterHub-Slurm dev environment host key" "jupyterhub-slurm-ssh-host-key")
---
$(cat jh_slurm_pod.yaml)
EOF

  # Bring up pod using combined file
  podman kube play "${BUILD_TMPDIR}/combined.yaml"
  
  # Preserve temporary build data directory for debugging (can be manually deleted)
  echo "To delete temporary build data directory:"
  echo "  rm -r -v ${BUILD_TMPDIR}"
}

# Destroy the pod and all associated resources created by bring_pod_up()
#
# Currently resources always have the same names, regardless of the <env_name>
# specified when bringing the environment up, so only one environment can be
# active at a time and tear_pod_down will tear down the active environment.
#
# Usage:
#  tear_pod_down
function tear_pod_down {
  # Tear down podman pod
  podman pod stop jupyterhub-slurm
  podman pod rm jupyterhub-slurm

  # Delete podman named volume containing JupyterHub data
  podman volume rm jupyterhub_root

  # Delete podman named volume containing Slurm data
  podman volume rm slurm_root

  # Delete podman secret and volume containing SSH client key
  podman secret rm jupyterhub-slurm-ssh-client-key
  podman volume rm jupyterhub-slurm-ssh-client-key

  # Delete podman secret and volume containing SSH host key
  podman secret rm jupyterhub-slurm-ssh-host-key
  podman volume rm jupyterhub-slurm-ssh-host-key
}

# Validate number of arguments
if (( $# < 1 || $# > 2 )); then
  echoerr "Error: incorrect number of arguments ($#)"
  echoerr
  echoerr "Usage: ${USAGE}"
  exit 1
fi 

ACTION=${1}

# Bring up or tear down podman pod using K8s manifest
if [[ ${ACTION} == "up" ]]; then

  if [[ -z ${2} ]]; then
    echoerr "Error: <env_name> not specified"
    echoerr
    echoerr "Usage: ${USAGE}"
    exit 1
  fi

  ENV_NAME=${2}

  echo "Bringing environment \"${ENV_NAME}\" up"
  bring_pod_up ${ENV_NAME}

elif [[ ${ACTION} == "down" ]]; then

  echo "Tearing environment down"
  tear_pod_down

else
  echoerr "Error: incorrect argument values"
  echoerr
  echoerr "Usage: ${USAGE}"
  exit 1
fi
