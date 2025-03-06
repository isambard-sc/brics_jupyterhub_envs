#!/bin/bash
set -euo pipefail

function echoerr { echo "$@" 1>&2; }

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
    echoerr "Error: expected 3 arguments, but got $#"
    exit 1
  fi
  # ssh-keygen prompts before overwriting, so duplicate stdout to stderr to show
  # the prompt without modifying the output of the function to stdout
  ssh-keygen -t ed25519 -f "${1}" -N "" -C "${2}" 1>&2
  cat <<EOF
apiVersion: core/v1
kind: Secret
metadata:
  name: ${3}
stringData:
  ssh_key: |
$(sed -E -e 's/^/    /' "${1}")
  ssh_key.pub: |
$(sed -E -e 's/^/    /' "${1}.pub")
  localhost_known_hosts: |
$(cat <(printf "%s" "localhost,127.0.0.1,::1 ") "${1}".pub | sed -E -e 's/^/    /')
  localhost_authorized_keys: |
$(cat <(printf "%s" 'from="localhost,127.0.0.1,::1" ') "${1}".pub | sed -E -e 's/^/    /')
immutable: true
EOF
}

# Writes a K8s manifest for a Secret containing the key data for an existing
# SSH key pair to stdout. The filename for the (private) key to be written, and
# name for the K8s Secret should be provided as arguments.
#
# The public part of the key is assumed to have the filename of the private part
# with .pub appended.
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
#    make_ssh_key_secret_from_files <filename> <secret name>
function make_ssh_key_secret_from_files {
  if (( $# != 2 )); then
    echoerr "Error: expected 2 arguments, but got $#"
    exit 1
  fi
  if [[ ! -a ${1} ]]; then
    echoerr "Error: ${1} not found"
    exit 1
  fi
  if [[ ! -a "${1}.pub" ]]; then
    echoerr "Error: ${1}.pub not found"
    exit 1
  fi
  cat <<EOF
apiVersion: core/v1
kind: Secret
metadata:
  name: ${2}
stringData:
  ssh_key: |
$(sed -E -e 's/^/    /' "${1}")
  ssh_key.pub: |
$(sed -E -e 's/^/    /' "${1}.pub")
  localhost_known_hosts: |
$(cat <(printf "%s" "localhost,127.0.0.1,::1 ") "${1}".pub | sed -E -e 's/^/    /')
  localhost_authorized_keys: |
$(cat <(printf "%s" 'from="localhost,127.0.0.1,::1" ') "${1}".pub | sed -E -e 's/^/    /')
immutable: true
EOF
}

# Create a K8s manifest for an immutable Secret containing data from a text file
#
# The Secret will have 1 key under stringData, containing the contents of the
# input file.
# 
# Usage:
#    make_secret_from_file <input_filename> <key_for_filename> <secret name>
function make_secret_from_file {
  if (( $# != 3 )); then
    echoerr "Error: expected 3 arguments, but got $#"
    exit 1
  fi
  if [[ ! -a ${1} ]]; then
    echoerr "Error: ${1} should already exist"
    exit 1
  fi
  cat <<EOF
apiVersion: core/v1
kind: Secret
metadata:
  name: ${3}
stringData:
  ${2}: |
$(sed -E -e 's/^/    /' "${1}")
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
# DEPLOY_CONFIG_DEV_USERS data key. It is expected that the key will be
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
  DEPLOY_CONFIG_DEV_USERS: "$(tr "\n" " " < "${1}" | sed -E -e 's/\s+$//')"
immutable: true
EOF
}

# Clone a Git repo, skipping if repo directory is already present
#
# Usage:
#   clone_repo_skip_existing <repository> <directory>
function clone_repo_skip_existing {
  if (( $# != 2 )); then
    echoerr "Error: expected 2 arguments, but got $#"
    exit 1
  fi

  if [[ ! -d "${2}" ]]; then
    mkdir -p -v "${2}"
    echo "Cloning fresh repository from ${1}"
    git clone "${1}" "${2}"
  else
    echo "Skipping clone from ${1}: existing directory ${2} found"
  fi
}

# Create a podman named volume and populate with the contents of a directory
#
# If an existing volume with name <volume_name> is found, the function exits
# without creating a new volume or modifying the existing volume. If no volume
# with name <volume_name> is found, then a new volume is created as follows:
#
# The username/UID and group/GID for files in the directory will be set based on
# the provided owner and group arguments.
#
# <owner> should be of the form USERNAME:UID
# <group> should be og the form GROUP:GID
#
# The initial volume contents are created as `tar` archive, which is imported
# into the podman named volume using `podman volume import`. `.gitkeep` files
# are excluded from the created volume. On macOS (Darwin) BSD tar is used and
# `podman volume import` is run in a podman machine. Otherwise GNU tar is used
# and `podman volume import` is run natively.
#
# Usage:
#   create_podman_volume_from_dir <volume_name> <owner> <group> <directory>
function create_podman_volume_from_dir {
  if (( $# != 4 )); then
    echoerr "Error: expected 4 arguments, but got $#"
    exit 1
  fi

  local VOL_NAME="${1}" OWNER="${2}" GROUP="${3}" VOL_DIR="${4}"

  if podman volume exists "${VOL_NAME}"; then
    echo "Skipping creating podman volume ${VOL_NAME}: ${VOL_NAME} already exists"
    return 0
  fi

  echo "Creating podman volume ${VOL_NAME} from ${VOL_DIR} with owner=${OWNER} group=${GROUP}"

  podman volume create "${VOL_NAME}"
  if [[ $(uname) == "Darwin" ]]; then
    # podman volume import not available using remote client, so run podman inside VM
    # BSD tar
    tar --cd "${VOL_DIR}" --create \
      --exclude .gitkeep \
      --uname "${OWNER%:*}" --uid "${OWNER#*:}" \
      --gname "${GROUP%:*}" --gid "${GROUP#*:}" \
      --file - . | podman machine ssh podman volume import "${VOL_NAME}" -
  else
    # GNU tar
    tar -C "${VOL_DIR}" --create \
      --exclude .gitkeep \
      --owner "${OWNER}" \
      --group "${GROUP}" \
      --file - . | podman volume import "${VOL_NAME}" -
  fi

}
