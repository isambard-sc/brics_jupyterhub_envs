"""
JupyterHub configuration for deployment of containerised JupyterHub with BricsAuthenticator
"""

c = get_config()  #noqa

from pathlib import Path
import urllib

import batchspawner  # Even though not used, needed to register batchspawner interface

def get_env_var_value(var_name: str) -> str:
    from os import environ
    try:
        return environ[var_name]
    except KeyError as e:
        raise RuntimeError(f"Environment variable {var_name} must be set") from e

# The JupyterHub public proxy should listen on all interfaces, with a base URL
# of /jupyter
c.JupyterHub.bind_url = "http://:8000/jupyter"

# The Hub API should listen on an IP address that can be reached by spawned
# single-user servers
c.JupyterHub.hub_bind_url = "http://127.0.0.1:8081"

# BricsAuthenticator decodes claims from the JWT received in HTTP headers,
# uses the short_name claim from the received JWT as the username of the
# authenticated user, and passes the projects claim from the received JWT
# to BricsSpawner via auth_state. See
#
# * https://jupyterhub.readthedocs.io/en/latest/reference/authenticators.html#authentication-state
# * https://github.com/isambard-sc/bricsauthenticator/blob/main/src/bricsauthenticator/bricsauthenticator.py

# Use BriCS-customised Authenticator class (registered as entry point by
# bricsauthenticator package)
c.JupyterHub.authenticator_class = "brics"

# Don't shut down single-user servers when Hub is shut down. This allows the hub
# to restart and reconnect to running user servers
c.JupyterHub.cleanup_servers = False

# Use BriCS-customised SlurmSpawner class
c.JupyterHub.spawner_class = "brics"

# The default env_keep contains a number of variables which do not need to be
# passed from JupyterHub to the single-user server when starting the server as
# a batch job.
# 
# Set env_keep to empty list to avoid these environment variables from becoming
# part of SlurmSpawner's keepvars template variable and their values in the
# environment for JupyterHub being passed through to the spawned single-user
# server.
c.Spawner.env_keep = []

# Set environment variables to pass information through to the job submission
# script environment/spawned Jupyter user server. The variables are prefixed
# with JUPYTERHUB_* to ensure that they are passed through the `sudo` command
# used to invoke `sbatch` (according to the sudoers policy)
c.Spawner.environment = {
    "JUPYTERHUB_BRICS_CONDA_PREFIX_DIR": get_env_var_value("DEPLOY_CONFIG_CONDA_PREFIX_DIR"),
    "JUPYTERHUB_BRICS_JUPYTER_DATA_DIR": get_env_var_value("DEPLOY_CONFIG_JUPYTER_DATA_DIR")
}

# Default notebook directory is the user's home directory (`~` is expanded)
c.Spawner.notebook_dir = '~/'

# Allow up to 7 mins (420s) for user session to queue and start
c.Spawner.start_timeout = 420

def get_ssh_key_file() -> Path:
    """
    Return a path to an SSH key under JUPYTERHUB_SRV_DIR

    Gets JUPYTERHUB_SRV_DIR from environment or raises RuntimeError.
    Also raises RuntimeError if $JUPYTERHUB_SRV_DIR/ssh_key does not exist.
    """
    srv_dir = get_env_var_value("JUPYTERHUB_SRV_DIR")

    try:
        return (Path(srv_dir) / "ssh_key").resolve(strict=True)
    except FileNotFoundError as e:
        raise RuntimeError(f"SSH private key not found at expected location") from e

# srun command used to run single-user server inside batch script
# Modified to propagate all environment variables from batch script environment.
# This is necessary because by default `srun` will only use environment variables
# specified via the `sbatch` `--export` flag (via SLURM_EXPORT_ENV environment
# variable). We use `--export` to only specify environment variables in
# the keepvars template variable, which has been configured to exclude some
# host-specific variables which are usually included by default, such as PATH.
# This is because the values of these variables comes from the environment
# JupyterHub is running, where PATH etc. is likely to differ to the PATH in a
# batch script executing on a compute node. Using --export=ALL ensures that all
# variables passed through from JupyterHub's environment via keepvars and any
# other environment variables set by Slurm in the batch script environment are
# propagated through `srun`.
c.BricsSlurmSpawner.req_srun = "srun --export=ALL"

# Prefix for commands used to interact with workload scheduler. Default is
# "sudo -E -u {username}" from BatchSpawnerBase, which runs the command as the
# user logged into JupyterHub. For single user testing we do not have `sudo`
# and want to submit the job as the user who started JupyterHub.
# When running JupyterHub in a context where we want to execute workload scheduler
# commands on a different machine (e.g. from within a container), we can run scheduler
# commands on the remote host over SSH by adding `ssh <hostname>` to the exec_prefix.
SSH_CMD=["ssh",
    "-i", str(get_ssh_key_file()),
    f"jupyterspawner@{get_env_var_value('DEPLOY_CONFIG_SSH_HOSTNAME')}", "sudo -u {username}",
]
c.BricsSlurmSpawner.exec_prefix = " ".join(SSH_CMD)

# Batch submission command which explicitly sets environment for sbatch, passing 
# as options to `sudo` from `exec_prefix`
#
# Explicitly setting the environment for the `batch_submit_cmd` is needed
# because `ssh` does not by default allow passing of arbitrary environment
# variables through to the remote process. OpenSSH client/server can be
# configured allow specific whitelisted variables to be passed from `ssh`'s
# environment into the environment of the remote process, but does not
# do this by default.
#
# The exec_prefix and batch_submit_cmd attributes undergo template expansion
# in BatchSpawner, so we can use Jinja2 templating features to insert
# all environment variables. After template rendering, the full command
# exec_prefix + batch_submit_cmd is run in a shell with environment specified
# by the result of the Spawner class's get_env() function.
#
# `batch_submit_cmd` needs to submit the job using `sbatch`, passing the
# environment variables in template variable keepvars through from the
# environment of the `batch_submit_cmd` to the single-user
# Jupyter server running in the Slurm job. As `sbatch` is being run via `ssh`,
# it does not share the same environment as the `ssh` process (specified by
# get_env()). In this case we expand the environment variables in `keepvars`
# in the environment of the `ssh` process and then explicitly set their values
# as arguments for an `env`/`sudo` command to setup the appropriate environment
# for `sbatch` to pass through to the Slurm job.
#
# NOTE: Care must be taken with quoting! The exec_prefix + batch_submit_cmd is
# run in a shell. Since the command run by the shell is `ssh ... <cmd>`, parameter
# expansion and quote removal occur in the context the `ssh` command is run, not
# in the context where the `<cmd>` is run. This is particularly important as
# some of the `JUPYTERHUB_*` environment variables in keepvars contain quotes
# themselves! In general, any portion of the command run by SSH that should be
# considered a single argument but might be split by the shell should be
# double-quoted, so that only the outer quotes are removed when the
# `ssh ... <cmd>` is processed by the shell.
SLURMSPAWNER_WRAPPERS_BIN = get_env_var_value("DEPLOY_CONFIG_SLURMSPAWNER_WRAPPERS_BIN")
c.BricsSlurmSpawner.batch_submit_cmd = " ".join(
    [
        "{% for var in keepvars.split(',') %}{{var}}=\"'${{'{'}}{{var}}{{'}'}}'\" {% endfor %}",
        f"{SLURMSPAWNER_WRAPPERS_BIN}/slurmspawner_sbatch",
]
)

# For `batch_query_cmd` and `batch_cancel_cmd`, passing through environment
# variables in `keepvars` is not necessary. However, we must still set the
# environment to pass the required SLURMSPAWNER_JOB_ID environment variable to
# the `slurmspawner_{scancel,squeue}` wrapper scripts, since these receive
# parameters via environment variables (not command line arguments).
c.BricsSlurmSpawner.batch_query_cmd = "SLURMSPAWNER_JOB_ID={{job_id}} " + f"{SLURMSPAWNER_WRAPPERS_BIN}/slurmspawner_squeue"
c.BricsSlurmSpawner.batch_cancel_cmd = "SLURMSPAWNER_JOB_ID={{job_id}} " + f"{SLURMSPAWNER_WRAPPERS_BIN}/slurmspawner_scancel"

# On Isambard-AI, no need to specify memory per node when --gpus is used to
# request a number of GH200s because memory is allocated based on the number of
# GPUs requested
# `--mem=0` requests all memory on each requested compute node in `sbatch`, `srun`
#c.BricsSlurmSpawner.req_memory = "0"
# No need to specify number of nodes required, as Slurm should request the correct number
# of nodes based on the number of GH200s requested
# Request a single node for Jupyter session
#c.BricsSlurmSpawner.req_options = "--nodes=1"
# Based on default for SlurmSpawner
# https://github.com/jupyterhub/batchspawner/blob/fe5a893eaf9eb5e121cbe36bad2e69af798e6140/batchspawner/batchspawner.py#L675
c.BricsSlurmSpawner.batch_script = """#!/bin/bash
#SBATCH --output={{homedir}}/jupyterhub_slurmspawner_%j.log
#SBATCH --job-name=spawner-jupyterhub
#SBATCH --chdir={{homedir}}
#SBATCH --export={{keepvars}}
#SBATCH --get-user-env=L
{% if partition  %}#SBATCH --partition={{partition}}
{% endif %}{% if runtime    %}#SBATCH --time={{runtime}}
{% endif %}{% if memory     %}#SBATCH --mem={{memory}}
{% endif %}{% if gres       %}#SBATCH --gres={{gres}}
{% endif %}{% if ngpus      %}##SBATCH --gpus={{ngpus}}  # NOTE: --gpus disabled in Slurm dev environment
{% endif %}{% if nprocs     %}#SBATCH --cpus-per-task={{nprocs}}
{% endif %}{% if reservation%}#SBATCH --reservation={{reservation}}
{% endif %}{% if options    %}#SBATCH {{options}}{% endif %}

set -euo pipefail

source ${JUPYTERHUB_BRICS_CONDA_PREFIX_DIR}/bin/activate jupyter-user-env

export JUPYTER_PATH=${JUPYTERHUB_BRICS_JUPYTER_DATA_DIR}${JUPYTER_PATH:+:}${JUPYTER_PATH:-}

trap 'echo SIGTERM received' TERM
{{prologue}}
{% if srun %}{{srun}} {% endif %}{{cmd}}
echo "jupyterhub-singleuser ended gracefully"
{{epilogue}}
"""

# Enable persisting of auth_state, which is used to persist authentication
# information in JupyterHub's database. This is encrypted and the 
# JUPYTERHUB_CRYPT_KEY environment variable must be set. `auth_state` is passed
# from  `Authenticator.authenticate()` to the `Spawner` via 
# `Spawner.auth_state_hook`. This is used to pass the value of the projects 
# claim from the JWT received by Authenticator to the Spawner.
c.Authenticator.enable_auth_state = True

# Use dev Keycloak as OpenID provider (used to get OIDC config, JWT signing key etc.)
c.BricsAuthenticator.oidc_server = "https://keycloak-dev.isambard.ac.uk/realms/isambard"

# Set name of platform being authenticated to. Only users with projects with this platform name in
# the token projects claim will be authenticated. Authenticated users can only spawn to projects
# associated with this platform name.
c.BricsAuthenticator.brics_platform = "brics.aip1.notebooks.shared"

# Set audience for JWT. Only users presenting tokens with this as value for the "aud" claim will be
# authenticated.
c.BricsAuthenticator.jwt_audience = "zenith-jupyter"

# Set leeway (in seconds) for validating time-based claims in the JWT.
c.BricsAuthenticator.jwt_leeway = 5

# Set (relative) logout redirect URL to the Zenith-server-managed OAuth2 Proxy sign_out
# endpoint with subsequent redirection to the service's base URL. This URL is redirected to after
# JupyterHub has handled its logout (clearing JupyterHub cookies) and causes OAuth2 Proxy's session
# storage cookies to be cleared.
c.BricsAuthenticator.logout_redirect_url = f"/jupyter/_oidc/sign_out?rd={urllib.parse.quote('/jupyter', safe='')}"

# Enable automatic redirection to the JupyterHub logout URL when an invalid JWT is encountered.
# If this is enabled it is important to ensure that the logout flow includes user prompt/interaction
# (e.g. by configuring OAuth2 Proxy to pass the prompt=login query parameter to the IdP OIDC
# authorization endpoint). If there is no prompt/interaction and the JWT is persistently invalid
# then a redirection loop could occur.
c.BricsAuthenticator.invalid_jwt_logout = True

# Set 12 h cookie_max_age_days value which expires the signed value of the cookie rather than the
# cookie itself, see:
# https://github.com/jupyterhub/jupyterhub/blob/01a43f41f8b1554f2de659104284f6345d76636d/jupyterhub/handlers/base.py#L471
# https://github.com/tornadoweb/tornado/blob/aace116c3f195e127c63b00fd5afadf1587c99d0/tornado/web.py#L862
# https://www.tornadoweb.org/en/stable/web.html#tornado.web.RequestHandler.get_signed_cookie
# This value controls the expiry of the signed value of the Hub login cookie (jupyterhub-hub-login)
# and internal OAuth token cookie for single-user server (jupyterhub-user-username), see:
# https://jupyterhub.readthedocs.io/en/latest/tutorial/getting-started/security-basics.html#cookies-used-by-jupyterhub-authentication
# https://jupyterhub.readthedocs.io/en/latest/explanation/oauth.html#token-caches-and-expiry
c.JupyterHub.cookie_max_age_days = 0.5
