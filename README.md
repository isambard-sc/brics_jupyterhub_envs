# brics_jupyterhub_envs

BriCS JupyterHub service development and deployment environments

## Environments

### Aim

Create an environment where JupyterHub and Slurm run in separate containers and interact over the network.
The JupyterHub container should connect to the Slurm container via SSH to run job management tasks. This environment should model the production environment for JupyterHub running on and interacting with Slurm on BriCS infrastructure (e.g. Isambard-AI).

### Design

#### Base images

* JupyterHub: [jupyterhub](https://github.com/jupyterhub/jupyterhub), <https://quay.io/repository/jupyterhub/jupyterhub>
* Slurm: [Docker-Slurm](https://github.com/owhere/docker-slurm), <https://hub.docker.com/r/nathanhess/slurm>

#### Configuration and logging data outside of containers

Configure and customise the behaviour of the images using data from outside of the container (e.g. volumes, `ConfigMap`s, `Secret`s)

#### Minimal modify of base images

Modify the JupyterHub and Slurm base images as little as possible to enable them to interact and model the production environment.

#### JupyterHub connects to Slurm over SSH

To run Slurm job management commands required for [batchspawner](https://github.com/jupyterhub/batchspawner/) (`sbatch`, `squeue`, `scancel`), JupyterHub will connect to the Slurm container via SSH. This will allow the JupyterHub container to be easily reused with other (non-containerised) Slurm instances in production, simply by setting up a service account to run the Slurm commands and configuring SSH login to this account.

#### Kubernetes-like deployment in `podman` pod

Use [`podman kube play`][podman-kube-play-podman-docs] to enable multi-container deployment in a `podman pod` using a Kubernetes manifest.

[podman-kube-play-podman-docs]: https://docs.podman.io/en/stable/markdown/podman-kube-play.1.html

This should enable the solution to be easily adapted for deployment in a Kubernetes environment in the future.

### Container images

When launching an environment using the deployment scripts local container images are built for JupyterHub and Slurm.

The container images use the [base images](#base-images) as a starting point and have three [build stages][multi-stage-builds-docker-docs]: `stage-base`, `stage-dev`, and `stage-prod`.

The `stage-base` stage contains build steps common to both the dev and prod builds. `stage-dev` and `stage-prod` each use `stage-base` as the starting point and customise the `stage-base` image for use in dev or prod environments, respectively. This allows the dev and prod container images to be built from a common base.

The dev environment deployment scripts build container images that target the `stage-dev` build stage.

The prod environment deployment scripts build container images that target the `stage-prod` build stage.

[multi-stage-builds-docker-docs]: https://docs.docker.com/build/building/multi-stage/

### Development repositories

A key step in the `stage-dev` image build is to re-install key supporting packages (e.g. [`bricsauthenticator`][bricsauthenticator-github], [`slurmspawner_wrappers`][slurmspawner_wrappers-github]) in the container using local clones of the Git repositories.

The dev environment deployment scripts clone the repositories used in the JupyterHub and Slurm container image builds into `brics_jupyterhub/_dev_build_data` and `brics_slurm/_dev_build_data`. If the repositories are already present, they are not overwritten. This allows for testing of local modifications to the source code repositories.

To test a modified version of the source code in the dev environment, simply modify the cloned repository under `_dev_build_data` and [bring up](#bring-up-an-environment) the dev environment. The modified code should be installed into the built container images when the environment is next deployed.

[bricsauthenticator-github]: https://github.com/isambard-sc/bricsauthenticator
[slurmspawner_wrappers-github]: https://github.com/isambard-sc/slurmspawner_wrappers

### Try it

#### Prerequisites

On the machine where the environment is launched:

* `podman`: the environment is launched as a [Podman pod][podman-pod-podman-docs] from a K8s manifest using [`podman kube play`][podman-kube-play-podman-docs]
* `bash`: the deployment scripts are a bash scripts
* OpenSSH: the deployment scripts use OpenSSH's `ssh-keygen` to generate SSH keys for use in the environment
* `git`: the deployment scripts clone development repositories with Git
* `sed`: the deployment scripts use `sed` to transform text when dynamically generating YAML documents
* `tar`: the deployment scripts create `tar` archives containing the initial contents of [podman named volumes][podman-volume-podman-docs]

The deployment scripts ([`build_env_resources.sh`](./build_env_resources.sh), [`build_env_manifest.sh`](./build_env_manifest.sh), and per-environment scripts in the [`scripts`](./scripts/) directory) use core utilities which may have different implementations on different operating systems (e.g. GNU vs BSD). Where possible the scripts use a common subset of utility options to avoid platform-specific conditionals. However, this is not always possible (e.g. GNU tar vs BSD tar).

[podman-pod-podman-docs]: https://docs.podman.io/en/stable/markdown/podman-pod.1.html
[podman-volume-podman-docs]: https://docs.podman.io/en/stable/markdown/podman-volume.1.html

#### Available environments

There are several environment variants, each with different characteristics. They differ in terms of the overall pod configuration and in the configuration of the applications running inside containers. Each environment is labelled by a descriptive string (e.g. `dev_dummyauth`, `prod`) which is used to deploy the environment with the deployment scripts and to identify data associated with the environment (volumes, configuration data).

The deployment scripts use files in per-environment subdirectories under [`config`](./config) to obtain static configuration data for the pod. The generic deployment scripts [`build_env_resources.sh`](./build_env_resources.sh) and [`build_env_manifest.sh`](./build_env_manifest.sh) use per-environment scripts under [`scripts`](./scripts) to perform the deployment.

When the environment is launched, named volumes are created for each container (JupyterHub, Slurm), to be mounted into the running container when launched. The initial contents of these volumes are in subdirectories under [`volumes`](./volumes), containing application configuration data and providing a directory/file structure for runtime and log information to be stored.

The per-environment data and scripts under [`config`](./config), [`volumes`](./volumes), [`scripts`](./scripts) allow the environments to be customised without changing the container images.

##### `dev_dummyauth`

JupyterHub and Slurm containers in a Podman pod interacting over SSH with mocked JWT authentication

* JupyterHub container initial volume data: [volumes/dev_dummyauth/jupyterhub_root](./volumes/dev_dummyauth/jupyterhub_root)
* Slurm container initial volume data: [volumes/dev_dummyauth/slurm_root](./volumes/dev_dummyauth/slurm_root)
* Pod configuration data: [config/dev_dummyauth](./config/dev_dummyauth)
* Deployment scripts: [scripts/dev_dummyauth](./scripts/dev_dummyauth)

Deploy `ConfigMap` example:

```yaml
apiVersion: core/v1
kind: ConfigMap
metadata:
  name: deploy-config
data:
  dummyAuthPassword: "MyVerySecurePassword"
  devUsers: "testuser.project1 testuser.project2 otheruser.project1"
immutable: true
```

In this environment, JupyterHub is configured to use `DummyBricsAuthenticator` (defined in [the JupyterHub configuration file](./volumes/dev_dummyauth/jupyterhub_root/etc/jupyterhub/jupyterhub_config.py)) which mocks the behaviour of `BricsAuthenticator` from [bricsauthenticator][bricsauthenticator-github], authenticating the first user in the from the value of `devUsers` in the deploy `ConfigMap` (`<USER>` part of `<USER>.<PROJECT>`).

The value of `devUsers` should be a space-separated list of usernames of the form `<USER>.<PROJECT>`, where `<USER>` corresponds to the `short_name` authentication token claim and `<PROJECT>` is a key from the `projects` authentication token claim.
The user is authenticated with a projects claim containing the list of all projects associated with that user in the value of `devUsers` (`<PROJECT>` for all usernames of form `<USER>.<PROJECT>` where `<USER>` is the authenticated user).

`DummyBricsAuthenticator` overrides JupyterHub's `DummyAuthenticator.authenticate()` method such that the username from the login form is discarded and the user authenticated is based on the value of `devUsers` in the deploy `ConfigMap`.
However, the password entered at the login form must match the value of `dummyAuthPassword` in the deploy `ConfigMap`.

In situations where other users may be able to connect to localhost (on which the dev environment's JupyterHub instance listens), it is recommended to set this as a long random password. For example to generate a 48 char base64 password using `openssl`:

```shell
openssl rand -base64 36
```

This environment is intended to be used for testing non-authentication components, where user HTTP requests to the JupyterHub server do not include a valid JWT to authenticate to JupyterHub.

##### `dev_dummyauth_extslurm`

JupyterHub in a Podman pod interacting with an external Slurm instance over SSH with mocked JWT authentication

* JupyterHub container initial volume data: [volumes/dev_dummyauth_extslurm/jupyterhub_root](./volumes/dev_dummyauth_extslurm/jupyterhub_root)
* Pod configuration data: [config/dev_dummyauth_extslurm](./config/dev_dummyauth_extslurm)
* Deployment scripts: [scripts/dev_dummyauth_extslurm](./scripts/dev_dummyauth_extslurm)

Deploy `ConfigMap` example:

```yaml
apiVersion: core/v1
kind: ConfigMap
metadata:
  name: deploy-config
data:
  dummyAuthPassword: "MyVerySecurePassword"
  sshHostname: "ssh.example"
  devUsers: "testuser.project1 testuser.project2 otheruser.project1"
  slurmSpawnerWrappersBin: "/path/to/slurmspawner_wrappers/bin"
  condaPrefixDir: "/path/to/conda"
  jupyterDataDir: "/path/to/jupyter/data"
  hubConnectUrl: "http://hub.example:8081"
immutable: true
```

In this environment, JupyterHub is configured to use `DummyBricsAuthenticator` (defined in [the JupyterHub configuration file](./volumes/dev_dummyauth/jupyterhub_root/etc/jupyterhub/jupyterhub_config.py)) which mocks the behaviour of `BricsAuthenticator` from [bricsauthenticator][bricsauthenticator-github], authenticating the first user in the from the value of `devUsers` in the deploy `ConfigMap` (`<USER>` part of `<USER>.<PROJECT>`).
See [`dev_dummyauth`](#dev_dummyauth) for details on the format of `devUsers`.

In order for spawning to work in the external Slurm instance, the `jupyterspawner` service user on the `sshHostname` should be able to switch users using `sudo -u <USER>.<PROJECT>` and run [`slurmspawner_wrappers`](slurmspawner_wrappers-github) scripts on behalf of the user to run jobs.
See [`jupyterhub_config.py`](./volumes/dev_dummyauth_extslurm/jupyterhub_root/etc/jupyterhub/jupyterhub_config.py) for details of the commands run on the SSH server, and [`jupyterspawner_sudoers`](./brics_slurm/jupyterspawner_sudoers) for an example `sudoers` configuration fragment that grants these permissions in the [`brics_slurm` container](./brics_slurm/Containerfile).

As in [`dev_dummyauth`](#dev_dummyauth), `DummyBricsAuthenticator` overrides JupyterHub's `DummyAuthenticator.authenticate()` and a password (`dummyAuthPassword`) must be provided to access JupyterHub as the user specified in `devUsers`
See [`dev_dummyauth`](#dev_dummyauth) for information and recommendations on setting `dummyAuthPassword`.

Other keys in the deploy `ConfigMap` configure how JupyterHub and spawned user instances interact with the external Slurm instance:

* `sshHostname`: host name or IP address that JupyterHub should connect to over SSH to run Slurm commands (via [slurmspawner_wrappers](slurmspawner_wrappers-github))
* `slurmSpawnerWrappersBin`: path to directory containing the `slurmspawner_{sbatch,scancel,squeue}` scripts on the SSH server (typically installed within a Python venv)
* `condaPrefixDir`: path to the Conda prefix directory for the Conda installation where the Jupyter user environment is installed (e.g. [`jupyter-user-env.yaml`](./brics_slurm/jupyter-user-env.yaml)), used by spawned user jobs to run `jupyterhub-singleuser`
  * This is the value of the `CONDA_PREFIX` environment variable when the base environment is activated
* `jupyterDataDir`: path to the Jupyter data directory to be used by spawned user servers, prepended to the [`JUPYTER_PATH` environment variable][jupyter-path-envvar-jupyter-docs] in spawned user jobs
  * This can be used to provide [kernelspecs][kernelspecs-jupyter-client-docs] to all notebook users
* `hubConnectUrl`: URL for user Jupyter servers to connect to the Hub API
  * User servers (e.g. running on compute nodes) must be able to communicate over HTTP to this URL
  * The host and port component of the URL should resolve to the IP and port on which port 8081 inside the JupyterHub container is published (see [Bring up an environment](#bring-up-an-environment))

This environment is intended to be used for testing non-authentication components and interaction with an external Slurm instance.

The `dev_dummyauth_extslurm` environment requires additional configuration data (in addition to the deploy `ConfigMap`) to be provided for the SSH connection to the external Slurm instance.
In [`dev_dummyauth`](#dev_dummyauth) the SSH client and host keys needed for communication between the JupyterHub container and Slurm container are generated when the environment is brought up and then injected into the JupyterHub and Slurm containers in the correct locations.
Since `dev_dummyauth_extslurm` connects to an external SSH server, the client and host key should be pre-generated and added to the deploy directory created when [bringing up the dev environment](#bring-up-an-environment). The following configuration information is required:

###### Client SSH key pair

A passwordless SSH key pair where the public key is authorized to access the SSH server at `sshHostname` for user `jupyterspawner` (e.g. added to `jupyterspawner`'s `~/.ssh/authorized_keys` file or presented by the `AuthorizedKeysCommand` specified in the `sshd`'s config file).

Filenames `ssh_client_key` (private key) and `ssh_client_key.pub` should be used

The following `ssh-keygen` command can be used to generate a suitable ed25519 keypair

```shell
ssh-keygen -t ed25519 -f "ssh_client_key" -N "" -C "JupyterHub-Slurm dev environment client key"
```

###### `ssh_known_hosts` file

An `ssh_known_hosts` file (named `ssh_known_hosts`) to be mounted into the JupyterHub container at `/etc/ssh/ssh_known_hosts` containing an entry with the value of `sshHostname` (from the deploy `ConfigMap`) followed by the public part of a host SSH key for the SSH server.

The file should follow the format of `ssh_known_hosts` specified in the [sshd man page][ssh-known-hosts-sshd-man-page].

This allows the JupyterHub to connect to the external SSH server and verify the host key before running any commands.

The following command can be used to construct a suitable `ssh_known_hosts` file from an ed25519 host public key (for an example hostname):

```shell
cat <(printf "%s" "ssh.example ") /etc/ssh/ssh_host_ed25519_key.pub > ssh_known_hosts
```

[jupyter-path-envvar-jupyter-docs]: https://docs.jupyter.org/en/stable/use/jupyter-directories.html#envvar-JUPYTER_PATH
[kernelspecs-jupyter-client-docs]: https://jupyter-client.readthedocs.io/en/latest/kernels.html#kernel-specs
[ssh-known-hosts-sshd-man-page]: https://manpages.ubuntu.com/manpages/jammy/en/man8/sshd.8.html#ssh_known_hosts%20file%20format

##### `dev_realauth`

JupyterHub and Slurm containers in a Podman pod interacting over SSH with real JWT authentication

* JupyterHub container initial volume data: [volumes/dev_realauth/jupyterhub_root](./volumes/dev_realauth/jupyterhub_root)
* Slurm container initial volume data: [volumes/dev_realauth/slurm_root](./volumes/dev_realauth/slurm_root)
* Pod configuration data: [config/dev_realauth](./config/dev_realauth)
* Deployment scripts: [scripts/dev_realauth](./scripts/dev_realauth)

Deploy `ConfigMap` example:

```yaml
apiVersion: core/v1
kind: ConfigMap
metadata:
  name: deploy-config
data:
  devUsers: "testuser.project1 testuser.project2 otheruser.project1"
immutable: true
```

In this environment JupyterHub is configured to use `BricsAuthenticator` from [bricsauthenticator][bricsauthenticator-github], and therefore requires that user HTTP requests include a valid JWT to be processed by `BricsAuthenticator`'s request handler code.
This is intended to be used for testing of authentication components, or for integration of authentication with other components.

Since `BricsAuthenticator` is used for authentication, no `dummyAuthPassword` is required in the deploy `ConfigMap`.
The usernames in `devUsers` should have the format described in [`dev_dummyauth`](#dev_dummyauth), i.e. `<USER>.<PROJECT>`, where `<USER>` and `<PROJECT>` corresponding to values in claims in the JWT used to authenticate.

One way to get valid JWTs sent to JupyterHub in HTTP request headers is to use the JupyterHub server as the endpoint of a [Zenith][zenith-github] tunnel, configured to authenticate users against an Open ID connect (OIDC) issuer which issues correctly formed identity tokens for processing by `BricsAuthenticator`. The [brics-zenith-client][brics-zenith-client-github] repository contains a Helm chart to deploy a suitably configured Zenith client.

> [!TIP]
> The URL for the OIDC issuer used by `BricsAuthenticator` to download OIDC configuration and perform signature verification can be configured by setting configuration attribute `c.BricsAuthenticator.oidc_server` in the [JupyterHub configuration file](./volumes/dev_realauth/jupyterhub_root/etc/jupyterhub/jupyterhub_config.py).

[zenith-github]: https://github.com/azimuth-cloud/zenith
[brics-zenith-client-github]: https://github.com/isambard-sc/brics-zenith-client/

##### `dev_realauth_zenithclient`

JupyterHub, Slurm, and [Zenith][zenith-github] client containers in a Podman pod, with JupyterHub and Slurm interacting over SSH, real JWT authentication, and traffic to JupyterHub proxied via the Zenith client

* JupyterHub container initial volume data: [volumes/dev_realauth_zenithclient/jupyterhub_root](./volumes/dev_realauth_zenithclient/jupyterhub_root)
* Slurm container initial volume data: [volumes/dev_realauth_zenithclient/slurm_root](./volumes/dev_realauth_zenithclient/slurm_root)
* Pod configuration data: [config/dev_realauth_zenithclient](./config/dev_realauth_zenithclient)
* Deployment scripts: [scripts/dev_realauth_zenithclient](./scripts/dev_realauth_zenithclient)

Deploy `ConfigMap` example:

```yaml
apiVersion: core/v1
kind: ConfigMap
metadata:
  name: deploy-config
data:
  devUsers: "testuser.project1 testuser.project2 otheruser.project1"
immutable: true
```

As with `dev_realauth`, JupyterHub is configured to use `BricsAuthenticator` from [bricsauthenticator][bricsauthenticator-github], and therefore requires that user HTTP requests include a valid JWT to be processed by `BricsAuthenticator`'s request handler code. This is intended to be used for testing of authentication components, or for integration of authentication with other components.

Since `BricsAuthenticator` is used for authentication, no `dummyAuthPassword` is required in the deploy `ConfigMap`.
The usernames in `devUsers` should have the format described in [`dev_dummyauth`](#dev_dummyauth), i.e. `<USER>.<PROJECT>`, where `<USER>` and `<PROJECT>` corresponding to values in claims in the JWT used to authenticate.

Unlike `dev_realauth`, the JupyterHub container in this environment does not publish the JupyterHub public proxy port on the host. Instead, it is expected that user traffic will arrive at the JupyterHub endpoint via a [Zenith][zenith-github] tunnel established between Zenith client running in the pod and an external Zenith server. The Zenith tunnel should be configured to authenticate users against an Open ID connect (OIDC) issuer which issues correctly formed identity tokens for processing by `BricsAuthenticator`.

The `dev_realauth_zenithclient` environment requires additional configuration data (in addition to the deploy `ConfigMap`) to be provided for the Zenith client when bringing up the pod in order to establish a tunnel with a Zenith server. This configuration information is read from the deploy directory created when [bringing up the dev environment](#bring-up-an-environment). The following configuration information is required:

###### Passwordless SSH key pair

* Private key: `ssh_zenith_client_key`
* Public key: `ssh_zenith_client_key.pub`

e.g. generated using

```shell
ssh-keygen -t ed25519 -f "ssh_zenith_client_key" -N "" -C "JupyterHub Zenith client key"
```

This should have been previously associated with a subdomain/URL path prefix in Zenith server, either by directly providing the SSH public key when reserving the name with Zenith server, or obtaining a token and then using `zenith-client init` to register a key at a later time (see [Zenith `README.md`][readme-zenith-github]).

###### Zenith client configuration file

Named `zenith_client_config.yaml`, based on the following template with deployment-specific configuration settings:

```yaml
# Zenith SSHD server address
serverAddress: ssh.example

# OpenID connect configuration
authOidcIssuer: https://keycloak.example/realms/name
authOidcClientId: example-client-name
authOidcClientSecret: exampleoidcsecret

# Whether to run Zenith client in debug mode
debug: true
```

[readme-zenith-github]: https://github.com/azimuth-cloud/zenith/blob/main/README.md

##### `prod`

JupyterHub and Zenith client containers in a Podman pod, with JupyterHub and Slurm interacting with an external Slurm instance over SSH. Real JWT authentication, and traffic to JupyterHub proxied via the Zenith client.

* JupyterHub container initial volume data: [volumes/prod/jupyterhub_root](./volumes/prod/jupyterhub_root)
* Pod configuration data: [config/prod](./config/prod)
* Deployment scripts: [scripts/prod](./scripts/prod)

Deploy `ConfigMap` example:

```yaml
apiVersion: core/v1
kind: ConfigMap
metadata:
  name: deploy-config
data:
  sshHostname: "ssh.example"
  slurmSpawnerWrappersBin: "/path/to/slurmspawner_wrappers/bin"
  condaPrefixDir: "/path/to/conda"
  jupyterDataDir: "/path/to/jupyter/data"
  hubConnectUrl: "http://hub.example:8081"
immutable: true
```

Unlike the `dev_` environments, this environment targets the `stage-prod` container build stage.
Local copies of development repositories are not built into the JupyterHub container image.

The keys in the deploy `ConfigMap` are as described for [`dev_dummyauth_extslurm`](#dev_dummyauth_extslurm).

Additional configuration data is as described for [`dev_dummyauth_extslurm`](#dev_dummyauth_extslurm) and [`dev_realauth_zenithclient`](#dev_realauth_zenithclient).
The following additional configuration data is required to be placed in the deploy directory created when [bringing up the environment](#bring-up-an-environment):

* [Client SSH key pair](#client-ssh-key-pair)
* [`ssh_known_hosts` file](#ssh_known_hosts-file)
* [SSH key pair for Zenith tunnel](#passwordless-ssh-key-pair)
* [Zenith client configuration file](#zenith-client-configuration-file)

#### Bring up an environment

Bring up a `podman` pod for environment name `<env_name>` (e.g. `dev_dummyauth`, `prod`):

```shell
# Create a directory for output of K8s manifest YAML and supporting data
mkdir -p /path/to/deploy_dir
```

In the deployment directory, create a "deploy `ConfigMap`" YAML file defining a K8s `ConfigMap` containing required configuration information.
See above for example YAML files for each environment.

At this point also add additional per-deployment configuration data to the deploy directory if required by the environment in use, e.g. Zenith client SSH key pair and configuration file for [`dev_realauth_zenithclient`](#dev_realauth_zenithclient).

```shell
# Build podman resources (container images, volumes)
bash build_env_resources.sh <env_name>

# Build K8s YAML manifest
bash build_env_manifest.sh <env_name> /path/to/deploy_dir

# Bring up podman pod with per-deployment configuration
podman kube play --configmap /path/to/deploy_dir/deploy-configmap.yaml [--publish ip:hostPort:containerPort] /path/to/deploy_dir/combined.yaml
```

> [!NOTE]
> The `--publish` option for `podman kube play` is only required for environments which spawn user sessions outside of the `podman` pod, e.g. [`dev_dummyauth_extslurm`](#dev_dummyauth_extslurm), [`prod`](#prod).
> This is used to publish the Hub API to a host IP so that spawned user servers can communicate with JupyterHub.
> The `ip` and `hostPort` should correspond to the host and port used in `hubConnectUrl` in the deploy `ConfigMap`.
> The `containerPort` should be port the Hub API is listening on in the JupyterHub container (default `8081`).

As described in [Available environments](#available-environments), [`build_env_resources.sh`](./build_env_resources.sh) uses container definitions (in [`brics_jupyterhub`](./brics_jupyterhub/) and [`brics_slurm`](./brics_slurm/)) and data under [`volumes`](./volumes) to build resources required to bring up the `podman` pod (container images, volumes). Once these resources are built, [`build_env_manifest.sh`](./build_env_manifest.sh) constructs an environment-specific K8s manifest YAML describing the `Pod` environment. This combines dynamically generated YAML documents with a fixed per-environment YAML document under [`config`](./config). The combined YAML document can then used to start a `podman` pod using [`podman kube play`][podman-kube-play-podman-docs], with deployment-specific configuration provided by the deploy `ConfigMap`.

If the pod has been successfully launched, the pod, containers, and volumes should be listed in the output of `podman` commands:

```shell
podman pod list --ctr-names --ctr-status
podman container list
podman volume list
podman secret list
```

To see the port mappings for containers in the pod, use `podman port`, e.g.

```shell
podman port jupyterhub-slurm-<env_name>-jupyterhub
```

### Tear down a environment

Tear down the active environment using the previously generated `combined.yaml`:

```shell
podman kube down [--force] /path/to/deploy_dir/combined.yaml
```

The `--force` option optionally ensures that `podman` volumes associated with the pod are removed. If this option is omitted, then named volumes are retained (which may be useful for debugging, or to restart the environment while maintaining state).

> [!NOTE]
> Older versions of `podman` may fail to remove volumes and secrets associated with the pod, even with the `--force` option. This has been observed in podman 4.4.4.
> Relevant GitHub issue and PR: [containers/podman#18797](https://github.com/containers/podman/issues/18797), [containers/podman#18814](https://github.com/containers/podman/pull/18814).
>
> The issue with removal of volumes (with `--force`) was fixed in [podman v4.6.0-RC2](https://github.com/containers/podman/releases/tag/v4.6.0-rc2).
> The issue with removal of secrets was fixed in [podman v4.5.0](https://github.com/containers/podman/releases/tag/v4.5.0).

If the pod has been successfully torn down, then the pod and associated components should be deleted, and will no longer be visible in the output of `podman` commands

```shell
podman pod list --ctr-names --ctr-status
podman container list
podman volume list
podman secret list
```

> [!TIP]
> If the pod was not brought up/torn down cleanly, then it may be necessary to manually delete the pod and associated components. See the below list of [useful commands](#useful-commands) for commands that delete individual environment components.

### Useful commands

To inspect contents of a podman named volume `jupyterhub_root` (extracts contents into current directory):

* On macOS (using a podman machine VM)

  ```shell
  podman machine ssh podman volume export jupyterhub_root | tar --extract --verbose
  ```

* On Linux (without a podman machine VM)

  ```shell
  podman volume export jupyterhub_root | tar --extract --verbose
  ```

To tear down the pod manually:

* Without the manifest (pod is named `jupyterhub-slurm-<env_name>`)

  ```shell
  podman pod stop jupyterhub-slurm-<env_name>
  podman pod rm jupyterhub-slurm-<env_name>
  ```

* To manually remove a named volume `jupyterhub_root_<env_name>`:

  ```shell
  podman volume rm jupyterhub_root_<env_name>
  ```

* To manually remove a secret `jupyterhub-slurm-ssh-client-key-<env_name>`

  ```shell
  podman secret rm jupyterhub-slurm-ssh-client-key-<env_name>
  ```

> [!NOTE]
> Running `podman kube play` with a manifest YAML containing a `Secret` creates a volume with the same name as the secret. To completely remove a secret, the corresponding volume should also be removed using `podman volume rm`.
