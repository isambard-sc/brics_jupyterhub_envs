#!/bin/bash
set -euo pipefail

# Authorized keys for jupyterspawner user from mounted volume
chown -R jupyterspawner:jupyterspawner /home/jupyterspawner/.ssh
chmod u=rwx,g=,o= /home/jupyterspawner/.ssh
chmod u=rw,g=,o= /home/jupyterspawner/.ssh/authorized_keys

# TODO Remove permission fixes for SSH host keys when podman >= v4.8.0 can be assumed
#   podman kube play for podman < v4.8.0 does not use defaultMode for volumes,
#   so permissions must be be set at runtime
# SSH host private keys from mounted volume
chmod u=rw,g=,o= /etc/ssh/ssh_host_*_key
