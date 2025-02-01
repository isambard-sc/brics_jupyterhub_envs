#!/bin/bash
# Create a test user accounts with Isambard-style username and home directory 
# paths (<USER>.<PROJECT>, /home/<PROJECT>/<USER>.<PROJECT>) which are members
# of the jupyterusers group.
#
# Note that users are created without a password, but can be accessed through
# other means, e.g. via `sudo -u <USER>.<PROJECT>` for a sufficiently 
# privileged account.
#
# Usernames of the form <USER>.<PROJECT> are extracted from the environment
# variable DEPLOY_CONFIG_DEV_USERS.
set -euo pipefail

for UNIX_USERNAME in ${DEPLOY_CONFIG_DEV_USERS}; do
  SHORT_NAME=${UNIX_USERNAME%.*}
  PROJECT=${UNIX_USERNAME##*.}
  echo "Creating test user ${UNIX_USERNAME}, with home /home/${PROJECT}/${UNIX_USERNAME}"
  mkdir -p /home/${PROJECT}
  useradd --create-home \
    --comment "${SHORT_NAME} ${PROJECT}" \
    --home-dir /home/${PROJECT}/${UNIX_USERNAME} \
    --user-group \
    --shell /bin/bash \
    --groups jupyterusers \
    ${UNIX_USERNAME}
done