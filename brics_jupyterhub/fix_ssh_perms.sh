#!/bin/bash
set -euo pipefail

# TODO Remove permission fixes for SSH client keys when podman >= v4.8.0 can be assumed
#   podman kube play for podman < v4.8.0 does not use defaultMode for volumes,
#   so permissions must be be set at runtime
# SSH client private keys from mounted volume
chmod u=rw,g=,o= ${JUPYTERHUB_SRV_DIR}/ssh_key

