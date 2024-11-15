# brics_jupyterhub_envs

BriCS JupyterHub service development and deployment environments

## JupyterHub-Slurm development environment

Create an environment where JupyterHub and Slurm run in separate containers and interact over the network, e.g. JupyterHub container connects to Slurm container via SSH to run job management tasks.

### Design

#### Base images

* JupyterHub: [jupyterhub](https://github.com/jupyterhub/jupyterhub), <https://quay.io/repository/jupyterhub/jupyterhub> 
* Slurm: [Docker-Slurm](https://github.com/owhere/docker-slurm), <https://hub.docker.com/r/nathanhess/slurm>

#### Configuration and logging data outside of containers

As above, bind mount directories/volumes outside of the container to configure and customise the behaviour of the images.

#### Minimal modify of base images

Modify the JupyterHub and Slurm base images as little as possible to enable them to interact, e.g. install SSH client/server packages.

#### JupyterHub connects to Slurm over SSH

To run Slurm job management commands required for [batchspawner](https://github.com/jupyterhub/batchspawner/) (`sbatch`, `squeue`, `scancel`), JupyterHub will connect to the Slurm container via SSH. This will allow the JupyterHub container to be easily reused with other (non-containerised) Slurm instances in production, simply by configuring an SSH connection.

#### Kubernetes-like deployment in `podman` pod

Use [`podman kube play`](https://docs.podman.io/en/stable/markdown/podman-kube-play.1.html) to enable multi-container deployment in a `podman pod` using a Kubernetes manifest.

This should enable the solution to be easily adapted for deployment in a Kubernetes environment in the future.

### Try it!

TODO

### Useful commands

To inspect contents of a podman named volume `jupyterhub_root` (extracts contents into current directory):

- On macOS (using a podman machine VM)

  ```shell
  podman machine ssh podman volume export jupyterhub_root | tar --extract --verbose
  ```

- On Linux (without a podman machine VM)

  ```shell
  podman volume export jupyterhub_root | tar --extract --verbose
  ```

To tear down the pod manually (without the launcher script):

- Based on the K8s YAML manifest `jh_slurm_pod.yaml`

  ```shell
  podman kube down jh_slurm_pod.yaml 
  ```

- Without the manifest (pod is named `jupyterhub-slurm`)

  ```shell
  podman pod stop jupyterhub-slurm
  podman pod rm jupyterhub-slurm
  ```

To manually remove a named volume `jupyterhub_root` (without the launcher script):

```shell
podman volume rm jupyterhub_root
```
