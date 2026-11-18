# Decisions

Short records of the choices that shape this deployment model. Each record
explains what was traded away, not only what was chosen.

> **Decision record.** ADRs explain why the target state is shaped this way. They
> are not procedures; the operational and reference pages carry the instructions.
> The build gap is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).

If a term is unfamiliar, [`GLOSSARY.md`](GLOSSARY.md) defines it.

All decisions below are accepted and describe the final target state.

## Decision index

| Area | Decisions |
|---|---|
| Access and identity | ADR-003, ADR-006, ADR-013, ADR-014, ADR-021 |
| Pipeline and release | ADR-001, ADR-002, ADR-004, ADR-005, ADR-007, ADR-008, ADR-011 |
| Hosts and environments | ADR-009, ADR-010, ADR-012, ADR-019 |
| Edge, WAF and alerts | ADR-015, ADR-016, ADR-017, ADR-018, ADR-020, ADR-025 |
| Repository hygiene | ADR-026 |
| Data services | ADR-022, ADR-023, ADR-024 |

The records are in number order below.

---

## ADR-001 — Infrastructure changes never run in CI

**Status:** accepted

**Context.** Running infrastructure playbooks from GitHub would require the vault password and a shared deploy-owner password in GitHub, because those playbooks write secrets and change host access. That puts the entire production credential set behind a workflow file that anyone with repository write access can edit.

**Decision.** Provisioning and configuration belong to Lane 1: an admin's control machine, the vault password typed for each run, and no CI involvement. CI may only deploy an application image.

Two mechanisms enforce this rule:

- The infrastructure playbooks are not available from the workflow.
- `playbooks/guard.yml` asserts that infrastructure playbooks do not run while `CI` is set in the environment.

**Consequences.** A configuration change always requires an admin. This cost is accepted because it is the difference between "a compromised pipeline ships a bad image" and "a compromised pipeline owns the server." Infrastructure changes are rare compared with image deploys, so the friction is small.

---

## ADR-002 — The pipeline holds zero passwords

**Status:** accepted

**Context.** GitHub Environment secrets are not readable by repository collaborators, so keeping the vault password in the production environment does keep passwords away from developers. It does not keep them away from a modified workflow. Approval then becomes the only control, and approval depends on a human reading a diff.

**Decision.** The production pipeline authenticates with one SSH key as `ci-deploy`. The `ci-deploy` account has a passwordless sudo rule for exactly two root-owned scripts:

```text
ci-deploy ALL=(root) NOPASSWD: /usr/local/bin/erp-deploy, /usr/local/bin/erp-smoke
```

In sudoers, a command listed without arguments may be run with any arguments, so both scripts validate their own input. Ansible installs the scripts. They are root-owned with mode `0755`, and `ci-deploy` cannot write to them.

**Consequences.**

- A tampered workflow can deploy an image. It cannot decrypt the vault, read application secrets, open a port, install a package, or change configuration.
- The deploy path does not need Ansible, a vault, or a become password in CI.
- Day-2 deploys use a shell script instead of a playbook. The script is smaller and easier to audit, but it repeats the compose operations that `roles/erp` performs. That repetition is contained to one file and covered by the smoke script.
- Once the pipeline is registered, `ci-deploy` must appear in `AllowUsers`. It must never join the `docker` group.

---

## ADR-003 — Production approval: one designated reviewer, no self-review

**Status:** accepted

**Context.** Approval is meaningful only when the approver is not the requester. The deployment has one designated release reviewer, who may also be the only host admin. A second reviewer is optional and improves availability.

**Decision.** The `production` GitHub Environment lists one designated reviewer and keeps **Prevent self-review** enabled. Deployment is restricted to `main`. Any authorised user may request a production deploy. The reviewer approves requests they did not trigger. If the reviewer is also the requester, the pipeline does not self-approve; that deploy uses the audited control-machine path. A second reviewer is optional, and the policy does not depend on one.

**Consequences.** Production pipeline deploys wait for the designated reviewer. The reviewer's own changes use the control-machine path when no second reviewer exists. Approval remains a release decision, separate from host access.

---

## ADR-004 — Pin by digest, not tag

**Status:** accepted

**Context.** A version tag is mutable. If the tag is rebuilt between the development test and the production pull, the two environments run different images.

**Decision.** The build produces a version tag for humans and a `sha256:` digest for machines. The pipeline promotes the digest. The deploy script accepts exactly one `sha256:` digest, validates its format, and rejects a tag. It does not resolve a version to a digest; the build job is the only place that knows which tag produced which digest.

**Consequences.**

- The image that passed in development is byte-identical in production.
- Rollback means deploying the previous digest through the same path and the same approval.
- The image prune policy must keep enough history for a rollback. `docker_prune_images_after` (168h) defines the window.
- A tag-only build cannot be deployed. The build job must publish the digest.

---

## ADR-005 — CI smoke is a health check; the full chain check stays on an admin's control machine

**Status:** accepted

**Context.** `playbooks/tasks/smoke.yml` verifies the whole CrowdSec path, including a test decision served to Traefik with the LAPI key from the vault. Running that check in CI would require the key, which ADR-002 removes from the pipeline.

**Decision.** The design uses two tools and two environments, and the assertions
are not identical:

| Check | `erp-smoke` development | `erp-smoke` production | `smoke.yml` development | `smoke.yml` production |
|---|---|---|---|---|
| Containers running, none exited | yes | yes | yes | yes |
| Site answers `/api/method/ping` through the edge | yes | yes | yes | yes |
| Certificate is issued for the hostname | yes | yes | yes | yes |
| Certificate chains to a public CA | **no (staging CA by design)** | yes | **no (the expected single failure)** | yes |
| Bouncer registered (`cscli bouncers list`) | yes | yes | yes | yes |
| AppSec listener answers through the bouncer path | yes | yes | yes | yes |
| LAPI reachable from Traefik | no | no | yes | yes |
| Access log and acquisition file readable | no | no | yes | yes |
| Test decision served with the vault key | no | no | yes | yes |

A development run is accepted when the **only** failure is public trust in the
staging CA. A production run is accepted only when public trust also passes.

**Consequences.** A green pipeline means the site is serving, not that the
intrusion-prevention chain is intact. The runbook states this difference, so
nobody mistakes one for the other. The stronger check runs after every CrowdSec
change and during the periodic drift check.

---

## ADR-006 — Admin names and public keys live in the encrypted vault

**Status:** accepted; revised to keep the admin roster out of the public repository

**Context.** The server needs a list of keys that may log in, and the names of the people those keys belong to. Publishing that list in `group_vars/<env>/main.yml` makes it reviewable in a pull request, but it also publishes who administers the system and which keys are authorised. Even a public key is an identifier, and a roster of admins is useful to an attacker. Private keys must never be stored anywhere except a secret store.

**Decision.** Admin account names and public keys live in `vault_base_operators` in the encrypted environment vault. The shared `base_operators` alias in `group_vars/all/main.yml` resolves that value from the selected environment's vault. `vault_operator_password_hashes` holds the matching yescrypt hashes. Ansible writes each admin's `authorized_keys` with `exclusive: true`, so removing a key from the vault revokes it on the next run. Private keys live only in an admin's agent or a GitHub Environment secret.

**Consequences.** Adding or removing an admin requires a vault edit (still a reviewable change, because the production vault is committed encrypted and the development vault is a local, gitignored file) and a run of `server.yml`. Reviewers can see that the production vault changed, but not its contents without the vault password. A key removed from the vault but not applied is still valid, which is why the runbook calls out the apply step. The CI public key now lives in `vault_ci_deploy_authorized_keys` for the same reason: a key comment or fingerprint is an identifier, even though the key grants no host access by itself. See [ADR-026](#adr-026--confidential-identifiers-live-in-the-vault-and-the-repository-is-non-identifying).

---

## ADR-007 — `ci-deploy` is not in the `docker` group

**Status:** accepted

**Context.** Membership in `docker` is equivalent to root. A member can mount the host filesystem, read any file, and become anyone. The same reasoning keeps every human admin account out of the group.

**Decision.** `ci-deploy` has no supplementary groups. Its only privileged capability is the two sudo commands.

**Consequences.** The deploy script runs as root through sudo, so it must stay small, fixed-purpose and reviewed. Any request to add "just one more docker command" widens this boundary and needs a new decision record.

---

## ADR-008 — `.env` is rendered at provisioning, not on every deploy

**Status:** accepted

**Context.** Templating `erp.env.j2` on every run forces the vault into every deployment path.

**Decision.** Provisioning writes the `.env` file, and Lane 1 rewrites it when a secret changes. Application deploys never render it. Compose reads the file, and the deploy script does not.

**Consequences.**

- The pipeline needs no application secrets.
- A secret rotation is a Lane 1 operation with a restart. Rotations are rare and deserve a human.
- Provisioning remains idempotent because the template still owns the file. Only the deploy path skips it.

---

## ADR-009 — One host per environment, one vault id per environment

**Status:** accepted

**Context.** The inventory keeps both environments in one file so the access model is defined once. Ansible selects an environment with `--limit`. That arrangement is safe only when each environment is unambiguous.

**Decision.** One host in `development` and one in `production`. Each environment has its own vault and matching vault-id, and `vault_id_match = True`.

**Consequences.** There is no staging environment. Adding one is a documented set of five steps in `ARCHITECTURE.md`. Two environments must never share a host or a vault-id, because either would make the guard's "exactly one environment in scope" assertion meaningless.

---

## ADR-010 — The host keeps a deploy record

**Status:** accepted

**Context.** GitHub Actions logs expire. During an incident, the server itself should answer the question "what is in production, and who put it there?"

**Decision.** `erp-deploy` appends one line per deploy to `/var/log/erp-deploys.log`, mode `0600`, owned by root. The line records the UTC timestamp, environment, previous digest, new digest, actor, workflow run URL and result.

**Consequences.** The host keeps a small, append-only audit trail that survives GitHub retention. It does not replace the GitHub approval record, which remains the authoritative record of who approved what.

---

## ADR-011 — Fine-grained PAT for repository dispatch

**Status:** accepted

**Context.** The application repository must trigger this repository's workflow. GitHub has no cross-repository trigger without a credential.

**Decision.** Use a fine-grained personal access token scoped to this repository with `Actions: write`. Store it as an application-repository secret and rotate it every 90 days. It must not belong to a person who is leaving the team. A GitHub App installation token is an equivalent alternative when both repositories share an organisation; the deployment depends on the dispatch capability, not on the mechanism.

**Consequences.** The token is a credential that must be rotated, and it must not belong to a departing employee. The design does not depend on which mechanism is used. It depends only on the rule that the application repository can dispatch, and nothing else can.

---

## ADR-012 — Cloudflare is an optional proxy, and its allowlist lives on the router

**Status:** accepted

**Context.** An environment may run without a proxy, with Cloudflare DNS only, or with Cloudflare in front. Treating Cloudflare as a required part of the entrypoint would make direct mode look unsupported and put an IP allowlist in the wrong layer.

**Decision.** Each environment chooses one edge mode:

| Mode | DNS | Proxy | Certificate | Router allowlist |
|---|---|---|---|---|
| Direct | Any provider | No | Let's Encrypt HTTP-01 | None |
| Cloudflare DNS, no proxy | Cloudflare, grey cloud | No | Let's Encrypt DNS-01 | None |
| Cloudflare proxy | Cloudflare, orange cloud | Yes | Let's Encrypt DNS-01 | `cloudflare-allow` on the public app router |

The entrypoint keeps a trusted-proxy list for `X-Forwarded-For`. That list decides whose client-IP header Traefik believes. It does not block. The `cloudflare-allow` middleware on the router is the gate, and it runs only in Cloudflare proxy mode. It permits Cloudflare and the private network.

The dashboard is private in every mode and is reached through an SSH tunnel.

**Consequences.** Direct mode needs port 80 for HTTP-01 and no Cloudflare token. Cloudflare DNS modes need a scoped DNS token. A direct deployment is not accidentally blocked by a Cloudflare allowlist. The trusted-proxy list and the router allowlist must stay separate in both the documentation and the Traefik configuration.

---

## ADR-013 — Per-person admin accounts, not a shared deploy login

**Status:** accepted

**Context.** A single shared human SSH account for every admin, plus one shared `deployowner` password for `sudo`, creates two problems that grow worse with a team:

- SSH and sudo logs could say that *someone* logged in, but not who.
- Removing one person would mean changing a password that everyone else knew, or leaving a valid shared credential behind.

A shared `deployowner` password would also do two jobs at once: it would be a service account's password and a human sudo secret. That would make the sudo target depend on a shared secret that could not be rotated per person.

**Decision.** Every admin has a named Linux account with their own SSH key and their own Unix password. Admin accounts are members of the `base_operators` group, and one sudoers rule gives that group full sudo. The normal target for stack work is `deployowner`, so the files and containers keep one service owner. Sudo authenticates the invoking admin, so `sudo -u deployowner` and ordinary `sudo` both ask for the admin's own password.

`deployowner` is a locked service identity with no SSH login and no usable password. It owns the stack directories and `.env`, and it is the only account in the `docker` group. Admins reach it only through `sudo`.

`vault_base_operators` is declared per environment, and both the account names and the public keys are in the encrypted vault. `vault_operator_password_hashes` holds one yescrypt hash per admin for account creation and rebuilds. There is no shared human host login and no shared owner password. `AllowUsers` names the admin accounts, plus `ci-deploy` once the pipeline is registered.

**Consequences.**

- Host changes are attributable to a person, and offboarding one admin does not require rotating a shared secret.
- Admins are still root-equivalent, because they have full sudo and can become `deployowner`. The model improves attribution and revocation; it does not reduce an admin's power.
- Every admin needs a key and a password hash, and access must be granted per environment.
- The only break-glass path is the provider console as `root`. That is deliberate: a shared human fallback would recreate the problem this model avoids.

---

## ADR-014 — Developers work locally and have no host account

**Status:** accepted

**Context.** Developers need a fast edit-run-debug loop and a place to integrate changes. The obvious shortcut is to give each developer SSH access to the shared development host. That shortcut is expensive: an account on a Docker host is effectively root, and a shared development host would accumulate credentials that are hard to review and revoke.

The shared development host is still useful, but as an integration target rather than a development machine.

**Decision.** Developers do not receive Linux accounts on development, production, or a control machine. They:

- run the application stack on their own machine;
- push code, where CI builds and deploys the development image;
- use Frappe Desk for application configuration and data in development;
- have no production System Manager role and no production host access.

A Frappe Desk user is not a Linux account. A developer can be a System Manager in the development app and still have no SSH access to the host. Production changes go through Lane 1 or an approved Lane 2 deployment.

**Consequences.**

- The local environment must be documented and kept close enough to shared development to be useful. [`DEVELOPMENT.md`](DEVELOPMENT.md) owns that workflow.
- A failure that only reproduces on shared development needs an admin to collect logs or run a host-side command. Centralized log access for developers is a separate decision and is not assumed here.
- A developer has no host audit identity because a developer has no host account. Audit records for developers are application-level Desk records and Git history.
- There is no standing exception process for temporary host access. If one is ever needed, it must be designed and recorded separately rather than added ad hoc.

---

## ADR-015 — AppSec is in-band and fail-closed

**Status:** accepted

**Context.** A WAF that fails open is a monitoring tool with a security label. If AppSec is unreachable or errors and Traefik lets the request through, an attacker can wait for the WAF to fail and then send the request uninspected. That defeats the purpose of running the WAF at all.

The trade-off is real: fail-closed makes CrowdSec a critical dependency. A CrowdSec outage becomes an HTTP outage.

**Decision.** AppSec runs in-band in the Traefik bouncer. `crowdsecAppsecFailureBlock` and `crowdsecAppsecUnreachableBlock` are both `true`. An AppSec error or an unreachable listener returns `403`; an invalid AppSec key returns `401` and is blocked regardless of the failure flags.

Virtual patching is the first in-band rule set. Generic rules are added only after the Frappe acceptance suite passes. CRS is run out-of-band first and moved in-band only after a separate review. There is no broad path exclusion and no broad client-IP bypass.

**Consequences.**

- CrowdSec is a critical dependency. Maintenance, upgrades and restarts need a plan.
- A false positive is a production outage. The acceptance suite and the narrow exception process in [`WAF.md`](WAF.md) are mandatory, not optional.
- Monitoring must distinguish an IP decision, an AppSec block and an application `403`.
- A permanent fix is a rule or application change, never "leave the WAF off".

---

## ADR-016 — Traefik waits for the initial decision stream

**Status:** accepted

**Context.** In stream mode the bouncer caches decisions and refreshes them on an interval. If Traefik starts while the cache is empty, there is a window in which a banned address is allowed. If the bouncer silently continues after the LAPI becomes unavailable, the cache becomes stale and the same problem returns later.

**Decision.** The target bouncer uses `crowdsecMode: stream`, `updateIntervalSeconds: 10`, `streamStartupBlock: true` and `updateMaxFailure: 0`.

`streamStartupBlock: true` makes plugin initialization wait for the first decision list before serving. `updateMaxFailure: 0` treats a failed refresh as a failure rather than as permission to serve with a stale list.

**Consequences.**

- A Traefik start with LAPI unavailable does not become an unprotected start. Traefik does not serve until the stream is ready.
- `site.yml` starts the Traefik play first so the log volume and `crowdsec-net` exist, then starts CrowdSec in the next play. The plugin waits during that gap. A standalone `traefik.yml` against a host with no CrowdSec starts a container that does not serve traffic.
- A LAPI outage can block HTTP traffic even if AppSec itself is healthy. That is the intended fail-closed behavior.
- The behavior must be tested in development before production, including the "LAPI down at startup" case.

---

## ADR-017 — The host firewall bouncer is mandatory and enforces all decisions

**Status:** accepted

**Context.** Traefik only sees HTTP. A CrowdSec decision on an address that attacks SSH, a published container port or a forwarded service is not enforced by the Traefik plugin. UFW is a static port policy; it does not learn from CrowdSec.

**Decision.** Every host runs `crowdsec-firewall-bouncer-nftables` as a systemd service. It reads the LAPI over `http://127.0.0.1:8080/`, uses a separate key (`firewall-host`), and enforces **all decision origins** in its own nftables tables. UFW remains the static port policy. The bouncer does not edit UFW or Docker's tables.

The LAPI is published only on host loopback. The host bouncer does not rely on the package's auto-registration; the role registers the named bouncer and writes its own config so the state is reproducible.

**Consequences.**

- SSH and forwarded traffic get the same decisions as HTTP.
- The host bouncer is fail-open for new decisions when LAPI is unavailable. UFW still enforces the static ports.
- In Cloudflare proxy mode the host bouncer cannot block the real client at layer 3 or layer 4. Traefik and AppSec remain the HTTP enforcement point. A decision that names a Cloudflare edge address can affect many visitors and needs a reviewed response.
- A false ban can lock an admin out of SSH. Recovery is the provider console, not a broad permanent allowlist.
- The key is separate from the Traefik key, so one leak does not force the other bouncer to rotate at the same time.

---

## ADR-018 — Telegram is the notification channel

**Status:** accepted

**Context.** The deployment needs one notification channel that the team actually monitors, with a credential that can be rotated and a destination that can be changed without editing a template by hand.

**Decision.** CrowdSec sends alerts to Telegram through its HTTP notification plugin. The bot token and chat ID live in the environment vault and are rendered into `<base_dir>/crowdsec/telegram.yaml`.

The message template is plain text. `group_wait` and `group_threshold` batch repeated alerts so a burst of bans does not hit Telegram's rate limit.

**Consequences.**

- A Telegram failure does not affect the site; it affects visibility.
- The bot token is part of the API URL and must be protected like any other secret. It is stored in a mode `0600 root` file, not in a command line.
- Rotating the bot or the chat is a documented operation and needs a test message.
- There is no dedicated Telegram plugin to maintain; the generic HTTP plugin is the supported path.

---

## ADR-019 — Hub content updates on a daily or weekly cadence

**Status:** accepted

**Context.** CrowdSec hub content — parsers, scenarios, collections and AppSec rules — receives security fixes independently of the engine image. Updating it every few hours adds churn and makes it harder to connect a change to a production symptom. Not updating it leaves known detection gaps.

**Decision.** Hub content is updated daily or weekly with `cscli hub update` and `cscli hub upgrade`, followed by the supported reload. CAPI blocklist updates are automatic and are not part of this cadence. A full container restart is a maintenance-window operation because AppSec is fail-closed.

The engine image and the Traefik plugin are updated separately, never in the same change. Tainted hub items are listed and reconciled; they do not silently keep receiving updates.

**Consequences.**

- A hub update can change detection behavior even when the engine image did not move. The WAF acceptance suite runs after the update.
- A reload must be verified to keep AppSec listening. If it does not, use a maintenance window and restart.
- A failed update is rolled back to the previous hub state or engine tag before the next attempt.
- The update is an admin operation, not a timer that runs unattended during business hours.

---

## ADR-020 — WAF exceptions are narrow, owned and reviewed

**Status:** accepted

**Context.** A WAF will eventually reject a legitimate request. The easy fixes are also the dangerous ones: exclude `/app`, exclude `/api`, disable AppSec, or trust a large address range. Each of those turns one false positive into a permanent blind spot.

**Decision.** A false positive is fixed at the narrowest layer that solves it:

1. fix the client or application;
2. narrow the rule;
3. disable one named rule in a reviewed overlay;
4. shadow one rule while evidence is collected;
5. a path-specific exception for one exact path and one exact rule.

Every exception has an owner, a reason, evidence, an expiry date, a rollback path and an acceptance-suite test. Broad exclusions for `/app`, `/api`, `/assets` or `/files`, and broad `clientTrustedIPs` bypasses, are prohibited.

**Consequences.**

- Some false positives take longer to fix. The result is auditable and reversible.
- The acceptance suite is the contract that proves the exception did not break another workflow.
- A `403` spike is an incident. The response is to identify the layer and roll back the narrow change, not to disable the WAF globally.
- Exceptions expire. A permanent exception needs a new decision record.

---

## ADR-021 — Dashboard access is per admin, not a shared login

**Status:** accepted

**Context.** The dashboard is private and reached through an SSH tunnel, but it is still a human login. A single shared `admin` basic-auth credential would recreate the attribution and offboarding problem that ADR-013 removes from the host.

**Decision.** Traefik basic auth uses one named entry per admin in `vault_traefik_dashboard_users`. The role renders a `user:hash` file into a Compose secret and mounts it at `/run/secrets/dashboard_users`; the `dashboard-auth` middleware reads it with `basicAuth.usersFile`. There is no shared dashboard password.

Removing an admin removes their host account and their dashboard entry. A dashboard password is separate from the admin's Linux and sudo password.

**Consequences.**

- Every dashboard login is attributable to a named admin.
- Adding or removing an admin is a `traefik.yml` change, not a password shared with the team.
- The dashboard credential cannot be used as a fallback for SSH or `sudo`.

---

## ADR-022 — Redis follows the upstream two-instance layout

**Status:** accepted

**Context.** Upstream `frappe_docker` defines two Redis services: `redis-cache` and `redis-queue`. Only the queue has a persistent volume. The application's `redis_socketio` setting points at the queue endpoint for backward compatibility, so a separate Socket.IO Redis service is not part of the upstream layout.

A third service adds operational surface without adding a distinct failure domain. It also creates a misleading expectation that Socket.IO needs its own durable store.

**Decision.** The target runs exactly two Redis services on `erp-cache`:

- `redis-cache` is ephemeral. It has no volume and no backup. Losing it is a cache miss, not a data restore.
- `redis-queue` uses the `redis-queue-data` volume for RQ jobs. It also carries Socket.IO pub/sub, which is ephemeral and not restored.
- `redis_socketio` points at `redis-queue`. There is no `redis-socketio` container.
- The `websocket` service joins `erp-cache` so it can reach the queue endpoint.
- Neither service has a password or a host port. The internal network is the boundary.
- The queue uses the image's RDB snapshot behavior. Append-only persistence is not enabled, so the queue is not a zero-loss job store.

`site.yml` and `update.yml` wait for both services before starting the application. Redis is not added to the MariaDB-and-sites backup pair.

**Consequences.**

- A normal container recreate keeps the queue volume, but a crash or unclean stop can lose jobs accepted since the last successful snapshot.
- A restore does not replay queued work. Operators must treat the backup pair and Redis as separate recovery scopes.
- The queue volume must never be removed with `docker compose down -v` unless discarding queued jobs is intentional.
- If job durability becomes a requirement, enabling append-only persistence or moving the queue to a durable broker is a new decision. It is not a silent configuration change.
- A Redis major-version upgrade needs a compatible RDB format and a tested rollback image.
- The role, the readiness gate and the application Compose file must all follow this decision. Implementation work is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).

---

## ADR-023 — Separate the database and cache networks

**Status:** accepted

**Context.** One internal network for MariaDB, Redis and the application services keeps the data services off the internet, but it also lets a compromised Redis container reach MariaDB. Upstream `frappe_docker` separates `mariadb-network` from `bench-network` in its multi-bench layout. Upstream still puts the public frontend on the same network as Redis, so copying it exactly would leave a public-facing container able to reach the cache.

**Decision.** The target uses three application-side networks:

- `erp_default` is the application network. It has a gateway for outbound traffic and carries `frappe-frontend`, `backend`, `websocket`, workers, scheduler and `asset-syncer`.
- `erp-db` is an internal network with no gateway. It carries MariaDB, the one-shot configurator, backend, workers and scheduler.
- `erp-cache` is an internal network with no gateway. It carries Redis, the one-shot configurator, backend, websocket, workers and scheduler.
- MariaDB is not on `erp-cache`. Redis is not on `erp-db`. The frontend and Traefik are on neither data network.

`traefik-public` is the edge network and carries only Traefik and `frappe-frontend`.

**Consequences.**

- A compromised Redis container cannot reach MariaDB.
- A compromised frontend cannot reach MariaDB or Redis. It can reach backend and websocket, which it needs to serve the site.
- A compromised websocket cannot reach MariaDB.
- Backend, workers and scheduler remain dual-homed because they genuinely need both data stores. The one-shot configurator joins both only while it provisions the site, then exits. Docker networks are not a firewall between containers on the same network; the reduction is in which services can reach which network.
- The MariaDB and Redis Compose projects join only their own data network. The one-shot configurator joins both and exits.
- `playbooks/site.yml`, the MariaDB and Redis Compose templates, the application Compose template and the network inventory must all agree. Implementation work is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).

---

## ADR-024 — The MariaDB root credential is for provisioning only

**Status:** accepted

**Context.** Putting `DB_ROOT_PASSWORD` in the application `.env` and giving it to the configurator makes the root credential part of the runtime application environment, even though normal Frappe requests use a per-site database user. Upstream `frappe_docker` keeps the MariaDB root password in a file secret and creates the site with an explicit `bench new-site` step rather than passing root to the long-running services.

**Decision.** The root password is a Compose `file:` secret at
`<base_dir>/mariadb/secrets/db_root_password`, mode `0600`, owned by
`deployowner`. MariaDB starts with
`MARIADB_ROOT_PASSWORD_FILE=/run/secrets/db_root_password`; the one-shot
configurator mounts the same file. It is mounted only into those two services. It
is not in `erp/.env`, not in the Compose environment, and not in the
environment of backend, workers, scheduler or websocket. Compose `file:` secrets
are bind mounts, not Swarm secrets; they do not appear in `docker secret ls` and
are protected by the host file mode and ownership.

The one-shot configurator follows Frappe's documented `bench new-site` flow. It
reads the secret from `/run/secrets/db_root_password` and passes it as
`--db-root-password` for the duration of site creation. That is the one place the
value appears in a process argument, and the process is short-lived and isolated.
Frappe chooses the database name; it is not assumed to be `frappe`. In v15 the
database user defaults to `db_name`; from v16 it may be the explicit `db_user`.
Read `.db_name` and `.db_user // .db_name` from `sites/<site>/site_config.json`.
The host scope is restricted to the Docker address pool with
`--mariadb-user-host-login-scope='172.30.%.%'`.

The same one-shot applies the initial site configuration: `enable_frappe_logger`,
`host_name`, and the outgoing-mail keys. The mail password is a separate Compose
secret at `<base_dir>/erp/secrets/mail_password`, mounted only into the
configurator and written into `site_config.json` after site creation. It is never
passed as a command-line argument. Only missing keys are filled, so a later
operator change is not overwritten.

**Consequences.**

- The runtime application cannot read the root secret.
- Site creation is the only normal use of root. Recovery may use it interactively, but not from a long-running service.
- The root password can appear briefly in the one-shot `bench new-site` arguments; it never enters the long-running environment.
- The site database name is not fixed. Backup, restore, grants and verification read it from `site_config.json`.
- `site_config.json` is a secret because it contains the database password, the mail password and the site encryption key.
- The backup script reads the root secret from inside the MariaDB container; it does not receive the password on a host command line.
- Root is a remote account for the one-shot configurator, because site creation runs in a container and connects over `erp-db`.
- The configurator must exit after site creation. A second site is a new environment, not a second tenant in the running stack.
- Implementation work is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).

---

## ADR-025 — The production Traefik bouncer is enabled only after the chain is proven

**Status:** accepted

**Context.** The Traefik bouncer is fail-closed (ADR-015) and waits for the
initial decision stream (ADR-016). Those are the right steady-state choices, but
they make the first production enablement all-or-nothing. A vault key that does
not match the registered bouncer, an AppSec listener that did not start, a
`crowdsec-net` that Traefik cannot reach, or a rule that rejects an ordinary
Frappe workflow all produce the same result: every HTTP request returns `403`.

The first production run is also the run with the least evidence. Development
proves the chain, but the production host has its own vault, its own networks and
its own certificate and DNS cutover. Discovering a broken dependency after the
bouncer is attached turns a security deployment into an outage.

`traefik_crowdsec_enabled` controls only the Traefik HTTP bouncer. It does not
control whether CrowdSec, the AppSec listener or the host firewall bouncer are
deployed. CrowdSec is installed and the host bouncer enforces decisions at layer
3 and layer 4 during the bootstrap phase.

**Decision.** Production starts with `traefik_crowdsec_enabled: false` as a
**bootstrap value**, not as the target state. The target state is `true`.

The bouncer is enabled only after all of the following are true in production:

1. `playbooks/crowdsec.yml` has run and the CrowdSec container, the LAPI and the
   AppSec listener are healthy.
2. `cscli bouncers list` shows the `traefik` and `firewall-host` bouncers
   registered, and the `traefik` key is the one in the production vault.
3. Traefik can reach the LAPI on `crowdsec-net`, and a test decision added with
   `cscli decisions add` is served to Traefik.
4. `playbooks/smoke.yml` passes with the bouncer still off.
5. The Frappe acceptance suite in [`WAF.md`](WAF.md#frappe-workflow-acceptance-suite)
   passes in development, and its result is recorded.

Then `traefik_crowdsec_enabled: true` is committed, `playbooks/site.yml` is run,
and smoke and the acceptance suite are repeated in production. The procedure is
in [`RUNBOOK.md`](RUNBOOK.md#153-enable-the-traefik-bouncer-in-production).

**Consequences.**

- The bootstrap phase is intentionally less protected at the HTTP layer: requests
  are not inspected by AppSec and Traefik does not enforce IP decisions. The host
  firewall bouncer still enforces decisions at layer 3 and layer 4, and UFW keeps
  the static port policy.
- The gap is visible, not silent. `playbooks/tasks/smoke.yml` warns when
  production still has the bouncer off, and the value is a reviewed line in
  `group_vars/production/main.yml`.
- Enabling the bouncer is a normal Lane 1 change with a diff, a review and a
  rollback, not a manual toggle on the host.
- A failure found during the gate is fixed with the site still serving. That is
  the whole point of the staged cutover.
- `false` is not a permanent exception. Leaving it off after the gate passes is a
  new decision, not an operational preference. The same rule applies to every
  later rebuild or region: the gate runs again before enforcement is attached.
- Turning the bouncer on makes CrowdSec a critical dependency for HTTP. From that
  point, CrowdSec maintenance, hub updates and image changes need the
  maintenance-window process in `RUNBOOK.md`.

**Alternatives rejected.**

- **Enable from the first production deploy.** Rejected: the first deploy is the
  least proven, and a single broken dependency produces a full HTTP outage with
  no staged way to diagnose it.
- **Enable fail-open until the chain is proven.** Rejected: ADR-015. A fail-open
  WAF passes uninspected traffic exactly when it matters, and the switch back to
  fail-closed would repeat the risky cutover later.
- **Leave the Traefik bouncer off permanently and rely on the host bouncer.**
  Rejected: the host bouncer cannot inspect HTTP requests and cannot virtual-patch
  a Frappe or dependency exploit. It is a layer-3 and layer-4 control, not a WAF.
- **Enable the bouncer but exclude `/app`, `/api` or `/files` during rollout.**
  Rejected: ADR-020. Those are the surfaces the WAF exists to protect, and a broad
  exclusion is a permanent blind spot created for a temporary reason.

---

## ADR-026 — Confidential identifiers live in the vault and the repository is non-identifying

**Status:** accepted

**Context.** The repository was published while it still described one real
deployment. The tracked configuration named the application domain, the
dashboard hostname, the registry namespace, the image repository, the backup
bucket, the SSH port, the mail identity and the people who operate the stack.
The git history also contained a real server address and login name, and the
commit metadata named the authors. Encryption protected passwords and tokens,
but a reader could still work out the site, the organisation and the host from
the identifiers around them.

Vaulting only the credentials was not enough. A domain, a registry path and a
bucket name are not secrets in the cryptographic sense, but together they
identify the deployment. The requirement is that a public reader cannot deduce
the real site, host, organisation, usernames or credentials from the repository.

**Decision.** Values are split into three tiers.

| Tier | Examples | Where it lives |
|---|---|---|
| Public constants | Upstream image names and versions, Cloudflare ranges, reserved and private IP ranges, generic role names, `deployowner`, `ci-deploy` | Tracked plaintext |
| Confidential identifiers | Domain, site name, dashboard host, registry namespace, image repository, mail server and login, sender name, backup remote and bucket, SSH port, repository URL, CI public keys | Encrypted environment vault, referenced as `vault_*` |
| Secrets | Passwords, tokens, private keys, password hashes | Encrypted environment vault, as before |

`group_vars/all/main.yml`, `group_vars/<env>/main.yml` and role defaults
contain only indirection for confidential values, for example
`domain: "{{ vault_domain | mandatory }}"` and
`erp_image_repository: "{{ vault_app_image_repository | mandatory }}"`.
Common aliases live in `group_vars/all/main.yml`; environment-specific source
values remain in their matching encrypted vault. `mandatory` is deliberate: a
missing key must fail the run rather than fall back to a value that could be
real.

The product name is replaced with the neutral name `erp` throughout the roles,
variables, volumes, networks, systemd units, scripts and documentation. External
resources such as the registry image path, the bucket and the DNS name are not
renamed; only their values move into the vault, so the repository stops
publishing them.

Two templates are tracked: `examples/vault.development.yml` and
`examples/vault.production.yml`. They contain only `CHANGE_ME` and
`example.com` values. They serve two purposes:

- a new clone copies the development template to
  `group_vars/development/vault.yml`, fills it in and encrypts it;
- CI copies both templates over the vault paths inside the ephemeral runner, so
  `ansible-lint` and `ansible-playbook --syntax-check` resolve every variable
  without a vault password.

The development vault is therefore not tracked at all. The production vault is
tracked because it is encrypted and every admin needs the same file. CI never
decrypts either real vault, which preserves ADR-002's rule that the pipeline
holds zero passwords.

`scripts/check-sensitive.sh` enforces the structure:

- every tracked environment vault starts with `$ANSIBLE_VAULT`;
- every referenced `vault_*` variable is defined in both example vaults;
- both example vaults define the same keys;
- no private key material or live provider token is tracked;
- `.DS_Store` is not tracked;
- if `SENSITIVE_PATTERNS` is supplied (locally or as a repository secret), no
  real identifier appears in a tracked file. The denylist is never committed,
  because publishing it would publish the values it protects.

Finally, the remedy for a repository that was already public is both a history
rewrite and a visibility change, not just a clean working tree:

1. rewrite the branch with `git filter-repo --refs <branch>` so old commits no
   longer contain the identifiers, author identities or removed files;
2. force-push only that branch;
3. make the repository private, because the other branches still carry the old
   history and a public repository exposes its owner and repository name
   regardless of file contents;
4. rotate every credential that was ever committed in plaintext and treat the
   old host and SSH account as exposed.

**Consequences.** Every Ansible run needs the environment vault, because even
`--syntax-check` resolves `vault_*`. That is the intended trade: the repository
is no longer a source of identifying information.

- A fresh clone cannot run a playbook until the development vault is created
  from the template. The runbook documents this.
- Adding a new identifier means adding a `vault_*` key to both examples and the
  real vault. The check script fails if the examples are forgotten.
- CI holds no vault password. The fixture files are placeholders; a real value
  accidentally committed to `examples/` would be a review failure, not a
  functional one.
- The production vault must be updated with the new keys before the next
  production run. Until then `mandatory` stops the run. This is a deliberate
  loud failure, not a fallback.
- Documentation uses `example.com`, `example-org`, `example-registry` and
  `alice`, so examples no longer hint at the real values.
- History rewrite invalidates every existing clone. Collaborators must re-clone
  or reset hard; old commits must not be merged back into the rewritten branch.
- The repository owner, repository name and commit metadata are still visible
  while the repository is public. Only making it private addresses that. Old
  forks, caches and search results may outlive a force-push.
- A live domain remains visible through DNS and certificate transparency.
  Vaulting it prevents the repository from confirming it; it does not hide the
  DNS record.

**Alternatives rejected.**

- **Keep domains and registry names public because they are not secrets.**
  Rejected: the requirement is that a reader cannot deduce the site, host or
  organisation. Those identifiers are exactly how a reader does it.
- **Vault only the credentials and leave identifiers in `group_vars/*/main.yml`.**
  Rejected: it achieves nothing against the stated threat, because the domain
  and registry path are the identifying values.
- **Store identifiers in GitHub Environment Variables instead of the vault.**
  Rejected: that splits the configuration across two stores, makes local runs
  depend on CI state, and still exposes the values in workflow configuration.
- **Commit the development vault in plaintext because it only holds development
  values.** Rejected: development values are still real identifiers, and a
  plaintext vault is one careless commit away from holding production-shaped
  values. The template plus local vault is safer and costs one copy command.
- **Give CI a development vault password.** Rejected: ADR-002. A password in
  the pipeline is authority a modified workflow can use.
- **Rewrite the current branch and keep the repository public.** Rejected: the
  owner and repository name remain public, and any other branch that was not
  rewritten still leaks the old values.
- **Delete the repository and start over.** Rejected as the primary option: it
  loses review history that still has operational value. It remains a fallback
  if old data cannot be purged from forks or caches.
- **Rename the external registry and bucket as well.** Rejected: that is an
  operational migration with downtime and data movement. Vaulting the values
  hides them from the repository without touching live infrastructure.

---

## ADR-027 — Separate SSH bans from general and alert-only profiles

**Status:** accepted

**Context.** SSH brute force is automated and has a lower false-positive risk
than a single HTTP or AppSec match. Applying the same long ban to every alert
would increase the impact of false positives, while treating every alert as a
remediation could ban a source for one in-band WAF match.

**Decision.** CrowdSec gives the four SSH brute-force and user-enumeration
scenarios a 24-hour IP ban. Other remediation alerts keep the existing
four-hour policy. Non-remediation alerts are notification-only. Telegram
notifications remain attached to all three profile paths when enabled.

**Consequences.**

- A false-positive SSH decision can still lock an administrator out for up to
  24 hours; use the provider console for recovery.
- WAF rule matches can be visible in Telegram without creating a decision.
- Repeat-offender escalation is not enabled until its behavior has been
  observed and validated.

---

## ADR-028 — Backups have an independent lifecycle

**Status:** accepted

**Context.** Backups used to be installed by `site.yml` and re-run by
`update.yml`. That coupled two unrelated concerns. A missing object-storage
credential could fail or partially install a deployment, and an image rollout
could rewrite the backup script and trigger a verification run without anyone
asking for it. It also made a failed first backup look like a deployment
problem, even though the site was already live.

**Decision.** A dedicated `playbooks/backup.yml` owns the backup install,
schedule, verification run and every later change. `site.yml` and `update.yml`
do not call the `backup` role. A fresh host has no backup timer until an admin
runs `backup.yml`, and that is an explicit provisioning gate. A failed
verification run fails `backup.yml`; it does not fail, stop or roll back the
application deployment.

**Consequences.**

- Deployments cannot fail because backup credentials are absent.
- An image rollout cannot silently reinstall or re-verify backups.
- A host can be live before backups exist. Run `backup.yml` immediately after
  `site.yml` and before declaring the host production-ready.
- Backup changes (schedule, destination, credentials) are made by running
  `backup.yml`, not `site.yml`.
- `backup_enabled: false` stops and removes the timer and service units, while
  leaving the script, configuration and existing data in place.

**Alternatives rejected.**

- **Keep backup in `site.yml` behind `backup_enabled`.** Rejected: the
  deployment still owns a lifecycle it does not need, and a missing credential
  still changes deployment behaviour.
- **Keep backup in `update.yml`.** Rejected: an image rollout must not rewrite
  the backup script or trigger a backup run.
- **Make the verification run non-fatal in `backup.yml`.** Rejected: once
  backups are a first-class operation, a failed verification must fail the
  operation that requested it. It still cannot affect the running site.
