# `docker` — container engine

> **Target state.** This page describes the system as it is meant to be. The
> remaining code work is tracked in [`IMPLEMENTATION.md`](../../IMPLEMENTATION.md).
> When this page and the code disagree, this page is authoritative.

## What this role is for

`docker` installs Docker Engine and the Compose plugin from Docker's official repository, then sets daemon defaults that protect the host. The stack runs as containers, so this role is the foundation for every runtime role that follows.

It does not create containers. It creates the engine that the other roles use.

## At a glance

| Item | Value |
|---|---|
| Role path | `roles/docker` |
| Called by | `playbooks/server.yml` |
| Runs as | A named admin, becoming `deployowner` through `sudo` with the admin's own password |
| Depends on | `base` has created the named admin accounts, the locked `deployowner` identity, and the `DOCKER-USER` firewall hook |
| Used by | `traefik`, `crowdsec`, `mariadb`, `redis`, `erp`, `backup` |
| Main tags | `docker`, `docker-daemon`, `docker-socket`, `docker-prune` |

## Inputs

| Variable | Default or source | Required | What it controls |
|---|---|---|---|
| `docker_apt_keyring` | `/etc/apt/keyrings/docker.asc` | no | Docker's signing key |
| `docker_apt_repository` | `/etc/apt/sources.list.d/docker.list` | no | Docker's apt source |
| `docker_apt_packages` | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` | no | Installed Docker packages |
| `docker_apt_dependencies` | `ca-certificates`, `curl`, `gnupg` | no | Packages needed to add the repository |
| `docker_socket_groups` | `[base_deploy_owner_user]` | yes | The account allowed to use the Docker socket; resolves to the `deployowner` |
| `docker_prune_enabled` | `true` | no | Remove old images and stopped containers |
| `docker_prune_images_after` | `168h` | no | Retention window before pruning |
| `docker_daemon_options` | map | no | The complete `/etc/docker/daemon.json` content |
| `base_deploy_owner_user` | `DEPLOY_OWNER_USER` | yes | The service identity added to the `docker` group |

No human admin account is added to `docker` by this role. Admins normally become `deployowner` with `sudo -u deployowner` for stack work; a one-off Docker command still goes through `sudo`. Docker access is audited either way.

### Daemon options in detail

| Key | Value | Why |
|---|---|---|
| `log-driver` | `json-file` | Use Docker's standard local log driver |
| `log-opts.max-size` | `10m` | Cap each log file |
| `log-opts.max-file` | `3` | Keep three files per container |
| `live-restore` | `true` | Keep containers running across a Docker daemon restart |
| `no-new-privileges` | `true` | Prevent containers from gaining privileges through setuid or setgid binaries |
| `log-level` | `info` | Send normal Docker events to the journal |
| `data-root` | `/var/lib/docker` | Keep container state in the documented location |
| `default-address-pools` | `172.30.0.0/16`, subnet size `/24` | Avoid address collisions with common private networks |

The address pool is also why the role documentation must be read together with the Traefik allowlist: `172.30.0.0/16` is inside the private ranges that the application allowlist accepts. The edge network must remain limited to the proxy and the frontend.

## What the role creates and changes

| Path or object | Mode | Purpose |
|---|---|---|
| `/etc/apt/keyrings` | `0755` | Directory for Docker's signing key |
| `/etc/apt/keyrings/docker.asc` | `0644` | Docker repository signing key |
| `/etc/apt/sources.list.d/docker.list` | `0644` | Docker apt source |
| `/etc/docker/daemon.json` | `0644` | Docker daemon configuration |
| `docker` service | enabled and running | Container engine |
| `docker` group | system group | Socket access for the `deployowner` |
| `/var/lib/docker` | root-owned | Images, containers, volumes and networks |

The `docker` role does not create the `DOCKER-USER` rules. `base` owns that script and the systemd drop-in. The `docker` handler re-runs the script after a Docker restart, because Docker rebuilds its firewall chains on startup.

## What runs on the host

| Object | What it means |
|---|---|
| Docker Engine | Pulls images, creates containers, networks and volumes |
| Compose plugin | Reads each `compose.yaml` and starts the services in dependency order |
| containerd | The container runtime underneath Docker |
| buildx plugin | Build tooling; present even though the server does not build images |
| Docker socket | `/var/run/docker.sock`; powerful, so no human account is given ambient access to it |

## Security invariants

- No human admin account is ever added to the `docker` group. The role is not the place to make an exception.
- `deployowner` is in `docker` because the stack roles run as that service identity.
- The Docker socket is not mounted into Traefik. Traefik reaches a filtered proxy instead.
- Containers cannot gain new privileges through setuid or setgid binaries.
- Docker logs are capped at the daemon level as a backstop for any container that does not set its own limits.
- `live-restore` keeps the application alive during a daemon restart. It does not replace a proper deploy.
- The Docker data root stays at `/var/lib/docker`, which is the path the backup role reads.
- Images unused for seven days are pruned. This leaves a recent rollback target in place.

### Deliberately not set

These settings are not enabled because each one needs a migration or changes how the stack behaves:

| Setting | Why it is not enabled |
|---|---|
| `icc: false` | Breaks container-to-container traffic on Docker's default bridge |
| `userland-proxy: false` | Changes how published ports are handled and would need a traffic test |
| `userns-remap` | Orphans the ownership of every existing named volume and breaks the stack until each volume is rechowned |

## Idempotency and change behaviour

- The apt repository and key are rewritten only when their content changes.
- `daemon.json` is validated as JSON before it replaces the working file. A malformed file would stop Docker and take every container down.
- The handler validates the daemon configuration, restarts Docker and re-applies the `DOCKER-USER` rules in that order.
- `live-restore` keeps running containers alive through the restart.
- Pruning runs only when `docker_prune_enabled` is true and Ansible is not in check mode.
- The role prints the Docker and Compose versions at the end, so a run that did nothing is visible.

## Verification

```bash
docker --version
docker compose version --short
docker info --format '{{.Driver}} {{.LoggingDriver}}'
docker info --format '{{.LiveRestoreEnabled}}'
id -nG deployowner
id -nG <your-admin>
```

Expected results:

- Docker and Compose print versions.
- The storage driver and logging driver are reported.
- `live-restore` is `true`.
- `deployowner` is in `docker`.
- Your admin account is **not** in `docker`.

Inspect the effective daemon configuration:

```bash
sudo cat /etc/docker/daemon.json
sudo dockerd --validate --config-file /etc/docker/daemon.json
```

## Failure modes

| Symptom | Likely cause | First check |
|---|---|---|
| `docker: command not found` | The apt repository or package install failed | `apt-cache policy docker-ce`; inspect the Ansible output |
| Docker will not start | Invalid `daemon.json` | `sudo dockerd --validate --config-file /etc/docker/daemon.json` |
| `permission denied` talking to the socket | The account is not in the `docker` group, or the session predates the group change | `id -nG`; log out and back in |
| Containers lose networking after a reboot | Docker's bridge address pool conflicts with the host network | `docker network inspect bridge`; compare with the host routes |
| Disk fills after several deploys | Pruning is disabled or the retention window is too long | `docker system df`; `docker image ls` |
| A container port is open despite UFW | `DOCKER-USER` rules were not applied | `sudo iptables -L DOCKER-USER -n -v` |

## Changing the Docker version

Docker is installed from the distribution's official repository, not pinned in this role. To move to a new release:

1. Read the Docker release notes for daemon or Compose changes.
2. Run `playbooks/server.yml` in check mode first.
3. Apply in development.
4. Confirm `docker info` and the stack health.
5. Apply in production.

Do not change `data-root` without a migration plan. The backup role reads the sites volume directly from `/var/lib/docker/volumes`.

## Implementation checklist

- [ ] Docker Engine and the Compose plugin come from Docker's official
      repository.
- [ ] `deployowner` is the only account in the `docker` group.
- [ ] `/etc/docker/daemon.json` is validated before it replaces the working file.
- [ ] Containers cannot gain new privileges through setuid or setgid binaries.
- [ ] Log rotation is set at the daemon level.
- [ ] `live-restore` is enabled and the data root remains `/var/lib/docker`.
- [ ] Unused images are pruned after 168 hours, leaving a recent rollback target.
- [ ] The `DOCKER-USER` rules are re-applied after a Docker restart.

## Related pages

- [`ROLES.md`](../ROLES.md) for the container and network inventory.
- [`base`](base.md) for the firewall hook that Docker depends on.
- [`traefik`](traefik.md) for the socket proxy that keeps Docker's socket out of the edge container.
- [`RUNBOOK.md`](../RUNBOOK.md#8-first-provision--run-as-root) for the provisioning sequence.
