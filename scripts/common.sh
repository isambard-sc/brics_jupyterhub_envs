#!/bin/bash
set -euo pipefail

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