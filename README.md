# brics_jupyterhub_envs

BriCS JupyterHub service development and deployment environments

## JupyterHub-Slurm development environment

### Aim

Create an environment where JupyterHub and Slurm run in separate containers and interact over the network. The JupyterHub container should connect to the Slurm container via SSH to run job management tasks. This environment should model the production environment for JupyterHub running on and interacting with Slurm on BriCS infrastructure (e.g. Isambard-AI).

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

When launching a dev environment using the deployment scripts local container images are built for JupyterHub and Slurm.

The container images use the [base images](#base-images) as a starting point and have three [build stages][multi-stage-builds-docker-docs]: `stage-base`, `stage-dev`, and `stage-prod`.

The `stage-base` stage contains build steps common to both the dev and prod builds. `stage-dev` and `stage-prod` each use `stage-base` as the starting point and customise the `stage-base` image for use in dev or prod environments, respectively. This allows the dev and prod container images to be built from a common base.

The dev environment deployment scripts build container images that target the `stage-dev` build stage.

[multi-stage-builds-docker-docs]: https://docs.docker.com/build/building/multi-stage/

### Development repositories

A key step in the `stage-dev` image build is to re-install key supporting packages (e.g. [`bricsauthenticator`][bricsauthenticator-github], [`slurmspawner_wrappers`][slurmspawner_wrappers-github]) in the container using local clones of the Git repositories.

The deployment scripts clone the repositories used in the JupyterHub and Slurm container image builds into `brics_jupyterhub/_dev_build_data` and `brics_slurm/_dev_build_data`. If the repositories are already present, they are not overwritten. This allows for testing of local modifications to the source code repositories.

To test a modified version of the source code in the dev environment, simply modify the cloned repository under `_dev_build_data` and [bring up](#bring-up-a-dev-environment) the dev environment. The modified code should be installed into the built container images when the environment is next deployed.

[bricsauthenticator-github]: https://github.com/isambard-sc/bricsauthenticator
[slurmspawner_wrappers-github]: https://github.com/isambard-sc/slurmspawner_wrappers

### Try it

#### Prerequisites

On machine where dev environment is launched:

* `podman`: the dev environment is launched as a [Podman pod][podman-pod-podman-docs] from a K8s manifest using [`podman kube play`][podman-kube-play-podman-docs]
* `bash`: the deployment scripts are a bash scripts
* OpenSSH: the deployment scripts use OpenSSH's `ssh-keygen` to generate SSH keys for use in the dev environment
* `git`: the deployment scripts clone development repositories with Git
* `sed`: the deployment scripts use `sed` to transform text when dynamically generating YAML documents
* `tar`: the deployment scripts create `tar` archives containing the initial contents of [podman named volumes][podman-volume-podman-docs]

The deployment scripts ([`build_env_resources.sh`](./build_env_resources.sh), [`build_env_manifest.sh`](./build_env_manifest.sh), and per-environment scripts in the [`scripts`](./scripts/) directory) use core utilities which may have different implementations on different operating systems (e.g. GNU vs BSD). Where possible the script use a common subset of utility options to avoid platform-specific conditionals. However, this is not always possible (e.g. GNU tar vs BSD tar).

[podman-pod-podman-docs]: https://docs.podman.io/en/stable/markdown/podman-pod.1.html
[podman-volume-podman-docs]: https://docs.podman.io/en/stable/markdown/podman-volume.1.html

#### Available dev environments

There are several dev environment variants, each with different characteristics. They differ in terms of the overall pod configuration and in the configuration of the applications running inside containers. Each dev environment is labelled by a descriptive string, e.g. `dev_dummyauth`, which is used to deploy the environment with the deployment scripts and to identify data associated with the environment (volumes, configuration data).

The deployment scripts use files in per-environment subdirectories under [`config`](./config) to obtain configuration data for the pod. The generic deployment scripts [`build_env_resources.sh`](./build_env_resources.sh) and [`build_env_manifest.sh`](./build_env_manifest.sh) use per-environment scripts under [`scripts`](./scripts) to perform the deployment.

When the dev environment is launched, named volumes are created for each container (JupyterHub, Slurm), to be mounted into the running container when launched. The initial contents of these volumes are in subdirectories under [`volumes`](./volumes), containing application configuration data and providing a directory/file structure for runtime and log information to be stored.

The per-environment data and scripts under [`config`](./config), [`volumes`](./volumes), [`scripts`](./scripts) allow the environments to be customised without changing the container images.

##### `dev_dummyauth`

JupyterHub and Slurm containers in a Podman pod interacting over SSH with mocked JWT authentication

* JupyterHub container initial volume data: [volumes/dev_dummyauth/jupyterhub_root](./volumes/dev_dummyauth/jupyterhub_root)
* Slurm container initial volume data: [volumes/dev_dummyauth/slurm_root](./volumes/dev_dummyauth/slurm_root)
* Pod configuration data: [config/dev_dummyauth](./config/dev_dummyauth)
* Deployment scripts: [scripts/dev_dummyauth](./scripts/dev_dummyauth)

In this environment, JupyterHub is configured to use `DummyBricsAuthenticator` (defined in [the JupyterHub configuration file](./volumes/dev_dummyauth/jupyterhub_root/etc/jupyterhub/jupyterhub_config.py)) which mocks the behaviour of `BricsAuthenticator` from [bricsauthenticator][bricsauthenticator-github], automatically authenticating the first user in the [`dev_users` config file](./config/dev_dummyauth/dev_users) (`<USER>` part of `<USER>.<PROJECT>`) and generating a projects claim containing the list of all projects associated with that user in the `dev_users` file (`<PROJECT>` for all usernames of form `<USER>.<PROJECT>` where `<USER>` is the authenticated user).

This is intended to be used for testing non-authentication components, where user HTTP requests to the JupyterHub server do not include a valid JWT to authenticate to JupyterHub.

##### `dev_realauth`

JupyterHub and Slurm containers in a Podman pod interacting over SSH with real JWT authentication

* JupyterHub container initial volume data: [volumes/dev_realauth/jupyterhub_root](./volumes/dev_realauth/jupyterhub_root)
* Slurm container initial volume data: [volumes/dev_realauth/slurm_root](./volumes/dev_realauth/slurm_root)
* Pod configuration data: [config/dev_realauth](./config/dev_realauth)
* Deployment scripts: [scripts/dev_realauth](./scripts/dev_realauth)

The `dev_realauth` environment does not have a predefined set of test users in `config/dev_realauth/dev_users`, unlike the `dev_dummyauth` environment, where the test users are listed in a tracked file.
The `dev_realauth` `config/dev_realauth/dev_users` file is ignored by Git and should be created/edited locally to match the users expected to authenticate to the dev environment.

The format of the `dev_users` file is 1 username of the form `<USER>.<PROJECT>` per line, where `<USER>` corresponds to the `short_name` authentication token claim and `<PROJECT>` is a key from the `projects` authentication token claim.

In this environment JupyterHub is configured to use `BricsAuthenticator` from [bricsauthenticator][bricsauthenticator-github], and therefore requires that user HTTP requests include a valid JWT to be processed by `BricsAuthenticator`'s request handler code. This is intended to be used for testing of authentication components, or for integration of authentication with other components.

One way to get valid JWTs sent to JupyterHub in HTTP request headers is to use the JupyterHub server as the endpoint of a [Zenith][zenith-github] tunnel, configured to authenticate users against an Open ID connect (OIDC) issuer which issues correctly formed identity tokens for processing by `BricsAuthenticator`. The [brics-zenith-client][brics-zenith-client-github] repository contains a Helm chart to deploy a suitably configured Zenith client.

> [!TIP]
> The URL for the OIDC issuer used by `BricsAuthenticator` to download OIDC configuration and perform signature verification can be configured by setting configuration attribute `c.BricsAuthenticator.oidc_server` in the [JupyterHub configuration file](./volumes/dev_realauth/jupyterhub_root/etc/jupyterhub/jupyterhub_config.py).

[zenith-github]: https://github.com/azimuth-cloud/zenith
[brics-zenith-client-github]: https://github.com/isambard-sc/brics-zenith-client/

#### Bring up a dev environment

Bring up a `podman` pod for dev environment name `<env_name>` (e.g. `dev_dummyauth`):

```shell
# Create a directory for output of K8s manifest YAML and supporting data
mkdir -p /path/to/deploy_dir

# Build podman resources (container images, volumes)
bash build_env_resources.sh <env_name>

# Build K8s YAML manifest
bash build_env_manifest.sh <env_name> /path/to/deploy_dir

# Bring up podman pod
podman kube play /path/to/deploy_dir/combined.yaml
```

As described in [Available dev environments](#available-dev-environments), [`build_env_resources.sh`](./build_env_resources.sh) uses data in [`volumes`](./volumes) and [`config`](./config) to build resources required to bring up the `podman` pod (container images, volumes). Once these resources are built, [`build_env_manifest.sh`](./build_env_manifest.sh) constructs an environment-specific K8s manifest YAML describing the `Pod` dev environment. This combines dynamically generated YAML documents with a fixed per-environment YAML document. The combined YAML document can then used to start a `podman` pod using [`podman kube play`][podman-kube-play-podman-docs].

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

### Tear down a dev environment

Tear down the active dev environment using the previously generated `combined.yaml`:

```shell
podman kube down --force /path/to/deploy_dir/combined.yaml
```

The `--force` option ensures that `podman` volumes associated with the pod are removed. If this option is omitted, then named volumes are retained (which may be useful for debugging, or to restart the environment while maintaining state).

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
> Running `podman kube play` with a manifest YAML with a `Secret` creates a volume with the same name as the secret. To completely remove a secret, the corresponding volume should also be removed using `podman volume rm`.
