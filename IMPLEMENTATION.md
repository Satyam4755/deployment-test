# Implementation status

> Internal tracker. This file is not part of the documentation in `docs/`. The documentation describes the target state; this file records how far the build has reached. Delete it once every row is done.

Last updated: 2026-10-24

## Status

| Piece | State | Where it belongs |
|---|---|---|
| Host hardening, Docker, firewall | done | `roles/base`, `roles/docker` |
| Per-person admin accounts with own key and own sudo password | done | `roles/base/tasks/users.yml`, `roles/base/tasks/ssh.yml`, `roles/base/defaults/main.yml` |
| `base_operators` group and sudoers rule | done | `roles/base/tasks/users.yml` |
| `vault_base_operators` (admin names and public keys) and `vault_operator_password_hashes` | done | `group_vars/*/vault.yml`, `roles/base` |
| Locked `deployowner` service identity | done | `roles/base/tasks/users.yml` |
| Remove `deploylogin`, `base_ssh_authorized_keys`, `vault_deploy_owner_password` | done | `roles/base`, `group_vars`, `playbooks/server.yml`, `.github/workflows/deploy.yml` |
| Role reference documentation | done | `docs/ROLES.md`, `docs/roles/` |
| Access model and developer workflow documentation | done | `docs/ARCHITECTURE.md`, `docs/SECRETS.md`, `docs/DEVELOPMENT.md`, `docs/DECISIONS.md` |
| Documentation restructure: landing page, glossary, one runbook, conventions | done | `README.md`, `docs/README.md`, `docs/GLOSSARY.md`, `docs/RUNBOOK.md`, `docs/CONVENTIONS.md` |
| Documentation link, anchor, terminology and banner checks | to build (deferred until code work resumes) | `scripts/`, `.github/workflows/` |
| Digest-only deploy contract in the script and workflow | done | `roles/erp`, `.github/workflows/deploy-app.yml` |
| Development and production TLS verification matrix | done (documented) | `docs/DECISIONS.md` ADR-005, `docs/RUNBOOK.md` |
| `ci-deploy` created only when the pipeline is registered | done | `roles/base`, `docs/RUNBOOK.md` |
| SSH port is configured before hardening; role does not edit `sshd` | done | `roles/base`, `docs/RUNBOOK.md` |
| Traefik edge stack | done | `roles/traefik` |
| CrowdSec engine, LAPI and basic Traefik bouncer | done | `roles/crowdsec`, `roles/traefik` |
| CrowdSec AppSec WAF, fail-closed bouncer settings and key file | done | `roles/crowdsec`, `roles/traefik/templates/dynamic.yaml.j2`, `group_vars/all/main.yml` |
| SSH authentication log acquisition | done | `roles/crowdsec/templates/`, `roles/base` |
| Host firewall bouncer (`crowdsec-firewall-bouncer-nftables`) | done | `roles/crowdsec`, `group_vars/all/main.yml` |
| Telegram notification profile | done | `roles/crowdsec`, `group_vars/*/vault.yml`, `docs/SECRETS.md` |
| CrowdSec collections target and hub update procedure | done | `group_vars/all/main.yml`, `roles/crowdsec`, `docs/RUNBOOK.md` |
| WAF acceptance suite and exception process | to build | `docs/WAF.md`, test tooling, `IMPLEMENTATION.md` |
| MariaDB | done | `roles/mariadb` |
| Redis follows the upstream two-instance layout | done | `roles/redis`, `playbooks/site.yml`, `playbooks/update.yml`, `roles/erp/templates/compose.yaml.j2` |
| Redis readiness checks both cache and queue | done | `playbooks/site.yml`, `playbooks/update.yml` |
| Redis `redis_socketio` points at the queue endpoint | done | `roles/erp/templates/compose.yaml.j2` |
| Frappe application image and deploy path | done | `roles/erp`, `playbooks/update.yml`, `group_vars/all/main.yml` |
| Backups and restore path | done | `roles/backup`, `playbooks/backup.yml` |
| Backup lifecycle is independent of deployment | done | `playbooks/backup.yml`, `playbooks/site.yml`, `playbooks/update.yml` |
| Per-environment vaults with `vault_id_match` | done | `group_vars/*/vault.yml`, `ansible.cfg` |
| Local-first developer stack and guide | to build (guide written) | application repository, `docs/DEVELOPMENT.md` |
| Centralized shared-development log access for developers | to design (deliberately deferred) | not yet assigned |
| `ci-deploy` account | done | `roles/base` |
| Restricted sudo for two scripts | done | `roles/base` |
| `erp-deploy` script | done | `roles/erp` |
| `erp-smoke` script | done | `roles/erp` |
| Deploy record `/var/log/erp-deploys.log` | done | `erp-deploy` |
| `AllowUsers` includes every admin, plus `ci-deploy` after pipeline registration | done | `roles/base/tasks/ssh.yml` (and the duplicate in `users.yml`) |
| `vault_ci_deploy_authorized_keys` variable | done | environment vaults; templated in `examples/vault.*.yml` |
| `.env` rendered at provisioning only | done | `roles/erp/tasks/main.yml` |
| Infrastructure playbooks removed from CI | done | `.github/workflows/deploy.yml` |
| CI guard: infra refuses to run when `CI` is set | done | `playbooks/guard.yml` |
| Application deploy pipeline with approval | done | `.github/workflows/deploy-app.yml` |
| Rollback dispatch | done | `.github/workflows/deploy-app.yml` |
| App repository dispatch token | to configure | application repository secret |
| `CODEOWNERS` for `.github/workflows/**` | done | `.github/CODEOWNERS` |
| HTTP-01 resolver for direct mode | done | `roles/traefik/templates/static.yaml.j2` |
| Cloudflare token optional in direct mode | done | `roles/traefik/tasks/main.yml`, `traefik.env.j2`, `roles/traefik/templates/compose.yaml.j2` |
| App router certificate resolver follows the edge mode | done | `roles/erp/templates/compose.yaml.j2` |
| Rename `vault_cloudflare_email` / `cloudflare_email` to a mode-neutral ACME name | done | `group_vars/all/main.yml`, `roles/traefik` |
| Trusted proxy list: localhost by default | done | `group_vars/all/main.yml` |
| CrowdSec bouncer trusted upstream list follows the edge mode | done | `roles/traefik/templates/dynamic.yaml.j2` |
| Dashboard uses a private allowlist | done | `roles/traefik/templates/compose.yaml.j2` |
| Per-admin dashboard basic auth from a Compose secret | done | `roles/traefik`, `group_vars/*/vault.yml` |
| Smoke warning only in Cloudflare proxy mode | done | `playbooks/tasks/smoke.yml` |
| SSH local forwarding for the dashboard tunnel | to change | `roles/base/defaults/main.yml` |
| `websocket` joins `erp-cache` so it can reach Redis | done | `roles/erp/templates/compose.yaml.j2` |
| Split `erp-internal` into `erp-db` and `erp-cache` | done | `playbooks/site.yml`, `roles/mariadb`, `roles/redis`, `roles/erp`, `roles/backup` |
| MariaDB root secret scoped to MariaDB and the one-shot configurator | done | `roles/mariadb`, `roles/erp`, `roles/backup` |
| MariaDB starts with `MARIADB_ROOT_PASSWORD_FILE`; root is not in the environment | done | `roles/mariadb/templates/compose.yaml.j2`, `roles/mariadb/templates/mariadb.env.j2` |
| Site creation follows Frappe's `bench new-site` flow, is idempotent, and lets Frappe choose the database name | to change | `roles/erp` |
| The site database name and user are read from `site_config.json`; no `frappe` default | done | `roles/mariadb`, `roles/backup`, `roles/erp` |
| Initial site config sets `enable_frappe_logger`, `host_name` and outgoing mail | to build | `roles/erp`, `group_vars/*/main.yml`, `group_vars/*/vault.yml` |
| Mail password is a Compose `file:` secret mounted only into the configurator and written to `site_config.json` | done | `roles/erp` |
| Application services depend on `configurator` with `service_completed_successfully` | done | `roles/erp/templates/compose.yaml.j2` |
| Cache-clear commands check that `site_config.json` exists and fail closed | done | `roles/erp/tasks/main.yml`, `roles/erp/templates/` |
| Frontend trusts `X-Forwarded-For` from Traefik on `traefik-public`, not `127.0.0.1` | done | `roles/erp/templates/compose.yaml.j2` |
| App image deployed by digest; asset marker keyed to the digest | done | `roles/erp`, `playbooks/update.yml`, `group_vars/all/main.yml` |
| Backup service can read its rclone configuration while still hardened | done | `roles/backup/templates/erp-backup.service.j2` |
| Telegram notification file restricted to the container account | done | `roles/crowdsec/tasks/main.yml` |
| Telegram bot token and chat ID are required secrets | done | `roles/crowdsec/tasks/main.yml`, `group_vars/*/vault.yml` |
| LAPI published only on `127.0.0.1:8080`; AppSec has no host port | done | `roles/crowdsec/templates/compose.yaml.j2` |
| `streamStartupBlock: true` and `updateMaxFailure: 0` | done | `roles/traefik/templates/dynamic.yaml.j2` |
| Startup handshake: Traefik waits for LAPI during `site.yml` | to verify | `playbooks/site.yml`, `roles/traefik`, `roles/crowdsec` |
| Backup reads `db_name` from `site_config.json` and has no hardcoded `frappe` fallback | done | `roles/backup` |
| Backup resolves the sites volume mountpoint from `docker volume inspect` | done | `roles/backup/templates/backup.sh.j2` |
| Backup manifest records the database name and application image digest | done | `roles/backup/templates/backup.sh.j2` |
| Swap file is initialised with `mkswap`, checked for size, and fails instead of silently resizing | done | `roles/base/tasks/system.yml` |
| CrowdSec runs as root, health-checks with `cscli lapi status`, and renders space-separated `COLLECTIONS` | done | `roles/crowdsec` |
| Host firewall bouncer installs from the CrowdSec packagecloud repository non-interactively | done | `roles/crowdsec/tasks/main.yml` |
| `server.yml` summary does not depend on a handler-only variable | done | `playbooks/server.yml` |
| `update.yml` waits for MariaDB and both Redis services before starting the application | done | `playbooks/update.yml` |

## Inputs still needed

- SMTP host, port, login, sender address and TLS mode (SSL on 465, STARTTLS on 587).
- The application names for `frappe_site_apps`, unless the image's own init script installs them.
- The production vault password, so `vault_mail_password` can be added to the encrypted vault.

## Build order

Each code step depends on the one above it, except the edge and security-hardening
steps 9–13, which can be done after the base stack is healthy. Do not start the
pipeline before the account and the scripts exist. Step 8 is a documentation gate,
not a code step.

0. **Per-person admin accounts** (`roles/base`).
   - Replace `deploylogin`, `base_ssh_authorized_keys`, and `vault_deploy_owner_password` with `base_operators` and `vault_operator_password_hashes`.
   - Create the `base_operators` group and the sudoers rule: full sudo for the group, and the normal stack target is `deployowner`; do not use `targetpw`.
   - Use `update_password: on_create` for admin accounts, so a later `passwd` change is not overwritten.
   - Lock `deployowner` and remove its SSH access. Keep it as the only account in `docker`.
   - Generate `AllowUsers` from the admin names only. The pipeline account is
     created later, in step 1, and then added to the list.
   - Remove accounts that are no longer listed, so offboarding is real.
   - Acceptance: two admins log in with their own keys; `sudo -u deployowner` asks each admin's own password; `sudo -i` also asks their own password; `passwd -S deployowner` reports locked; no human account is in `docker`; removing an admin from the list removes the account on the next run.

1. **`ci-deploy` account and sudo rule** (`roles/base`).
   - Create the user with no supplementary groups.
   - Add it to the generated `AllowUsers` list (admin names plus `ci-deploy`).
   - Add `vault_ci_deploy_authorized_keys` with `exclusive: true`.
   - Install `/etc/sudoers.d/ci-deploy` with the two script paths and `visudo` validation.
   - Acceptance: `ssh ci-deploy@host 'sudo -l'` lists only the two scripts; `id -nG ci-deploy` is empty.

2. **Deploy and smoke scripts** (`roles/erp`).
   - `/etc/erp/deploy.conf`, root-owned `0600`: app directory, site name, compose project.
   - `/usr/local/bin/erp-deploy`: validate the digest, pull, recreate, migrate, clear caches, restart workers, health check, append the deploy record.
   - `/usr/local/bin/erp-smoke`: containers, edge ping, certificate issued
     for the hostname, bouncer registration, AppSec through the bouncer path.
   - Acceptance: both run as root from a clean shell; a bad digest or a tag is
     rejected before anything is pulled; `erp-smoke` passes in development
     and production, with public trust asserted only in production; the full
     chain `smoke.yml` is accepted in development when the only failure is
     public trust, and production requires public trust.

3. **Stop re-rendering `.env` on deploys** (`roles/erp`).
   - Render only when the file is absent, or expose an explicit `erp_render_secrets` flag that the deploy path does not set.
   - Acceptance: two consecutive `update.yml` runs leave the file's mtime and checksum unchanged.

4. **Remove infrastructure from CI and add the guard** (`deploy.yml`, `guard.yml`).
   - Keep `update.yml` and the new deploy path; remove `server.yml`, `traefik.yml`, `crowdsec.yml`, `site.yml`.
   - Assert that `lookup('env', 'CI')` is empty in every infrastructure playbook.
   - Acceptance: dispatching an infrastructure playbook from Actions fails before opening SSH.

5. **Application deploy pipeline** (`deploy-app.yml`).
   - `repository_dispatch` and `workflow_dispatch`.
   - Jobs: prepare, deploy development, smoke development, deploy production, smoke production.
   - `environment: production` with one designated reviewer, `prevent self-review`, `main` only.
   - No `VAULT_PASSWORD` and no `BECOME_PASSWORD` anywhere.
   - Acceptance: a dispatch with a bad digest fails in prepare; a development smoke failure leaves no production job.

6. **Rollback path**.
   - Same workflow, explicit digest, same approval.
   - Acceptance: re-dispatching the previous digest restores the previous version and passes smoke.

7. **Repository protections**.
   - `CODEOWNERS` for `.github/workflows/**`.
   - Branch protection on `main`.
   - Read-only `GITHUB_TOKEN`, no secrets to fork pull requests.
   - Acceptance: a pull request that edits a workflow requires an admin's review.

8. **Documentation gate (not a code step; done before coding resumed).**
   - Root landing page, document map, one reading path per audience, glossary and
     one end-to-end runbook.
   - One canonical owner per shared fact; role pages carry implementation
     checklists; every diagram has a caption and a plain-text summary.
   - Every Ansible command is written out in full, with development and
     production side by side. There are no shell helper aliases.
   - Acceptance: the `docs/CONVENTIONS.md` review checklist passes, and
     `docs/RUNBOOK.md` takes a newcomer from a fresh host to a serving
     development site.

9. **Edge modes** (`roles/traefik`, `group_vars/all`).
   - Add an HTTP-01 resolver for direct mode. Keep DNS-01 for Cloudflare DNS.
   - Make the Cloudflare token and the DNS-01 resolver conditional.
   - Default `traefik_trusted_ips` to localhost; add Cloudflare ranges only in proxy mode.
   - Give the dashboard a private allowlist. Do not attach `cloudflare-allow` to it.
   - Keep the app allowlist at Cloudflare plus the private network. Give the dashboard a separate private-only allowlist.
   - Replace `vault_traefik_basic_auth` with `vault_traefik_dashboard_users`. Render one `user:hash` line per admin into a Compose secret, move `dashboard-auth` into the dynamic file, and use `basicAuth.usersFile`. Use `no_log: true` on the render task.
   - Warn about direct origin access only in Cloudflare proxy mode.
   - Acceptance: direct mode obtains a certificate on port 80 with no Cloudflare token; a proxied deployment rejects direct-to-origin requests; the dashboard opens only through the tunnel; each admin has their own dashboard login and no shared `admin` credential exists.

10. **CrowdSec AppSec and fail-closed bouncer** (`roles/crowdsec`, `roles/traefik`).
    - Publish the LAPI only on `127.0.0.1:8080`. Do not publish 7422.
    - Add acquisition for `/var/log/auth.log` at `/logs/auth.log` and for the AppSec listener at `0.0.0.0:7422`.
    - Install `crowdsecurity/traefik`, `crowdsecurity/linux` and `crowdsecurity/appsec-virtual-patching`. Do not list `base-http-scenarios` or `http-cve` separately.
    - Load `crowdsecurity/appsec-default` on the listener. Do not install a bare config without its rules.
    - Move the Traefik LAPI key from `dynamic.yaml` into a Compose secret and use `crowdsecLapiKeyFile`.
    - Set `crowdsecAppsecEnabled: true`, `crowdsecAppsecFailureBlock: true`, `crowdsecAppsecUnreachableBlock: true`, `crowdsecAppsecUnreadableBodyBlock: true`, `streamStartupBlock: true`, `updateMaxFailure: 0` and a stream refresh interval of 10 seconds.
    - Acceptance: a normal `/api/method/ping` returns normally; a known virtual-patch probe returns `403`; stopping AppSec blocks HTTP; an invalid key returns `401` and blocks; `cscli metrics show appsec` increases; Traefik does not serve when LAPI is unavailable at startup; a clean `site.yml` run reaches a serving edge after CrowdSec starts.

11. **Host firewall bouncer** (`roles/crowdsec`).
    - Install `crowdsec-firewall-bouncer-nftables` and stop the service while writing its config.
    - Register `firewall-host` with `vault_crowdsec_firewall_key`. Remove any bouncer auto-registered by the package.
    - Point the bouncer at `http://127.0.0.1:8080/`, set nftables, `DROP`, IPv6 enabled and a 10 second refresh.
    - Do not edit UFW or Docker tables from this role.
    - Acceptance: the service is active; `ip crowdsec` and `ip6 crowdsec6` exist; a test decision reaches the nftables set; a banned test host is dropped; UFW and `DOCKER-USER` are unchanged.

12. **Telegram and CrowdSec updates** (`roles/crowdsec`, `docs/RUNBOOK.md`).
    - Add `vault_telegram_bot_token` and `vault_telegram_chat_id`; render `telegram.yaml` at mode `0600 root` and wire the profile.
    - Keep one human notification channel: Telegram.
    - Restart CrowdSec when `telegram.yaml` or `profiles.yaml` changes, and document the fail-closed outage window.
    - Batch notifications and keep the message template plain text.
    - Document `cscli hub update`, `cscli hub upgrade`, the supported reload and the maintenance-window restart.
    - Acceptance: `cscli notifications test telegram` delivers a message; a bad token fails the run or test visibly; a normal deploy does not change hub content.

13. **WAF acceptance suite** (`docs/WAF.md`).
    - Turn the Frappe workflow table into a repeatable test set that runs through Traefik.
    - Run it in development before AppSec is enabled in production, then after every rule, hub, plugin or Frappe change.
    - Define the narrow exception format and the rollback path before the first production exception is needed.
    - Acceptance: every legitimate workflow passes, every negative probe is blocked, and no exception excludes `/app`, `/api`, `/assets`, `/files` or a broad address range.

14. **Redis upstream layout** (`roles/redis`, `playbooks/site.yml`, `roles/erp`).
    - Keep `redis-cache` and `redis-queue`; remove `redis-socketio`.
    - Remove the cache volume and keep `redis-queue-data` on the queue.
    - Point `REDIS_SOCKETIO` at `redis-queue` and attach `websocket` to `erp-cache`.
    - Wait for both Redis `PING` checks in `site.yml` and `update.yml` before starting the application.
    - Acceptance: no third Redis container or volume exists, the websocket resolves `redis-queue`, a cache restart loses only cache, and a queue container recreate retains the volume.

15. **Secure site initialisation and initial site config** (`roles/erp`, `roles/mariadb`, `roles/backup`).
    - Mount the root secret through Compose `secrets`; set `MARIADB_ROOT_PASSWORD_FILE`; remove the root password from `.env` and the environment.
    - Add the role-owned idempotent wrapper. Use the image script when present; otherwise run Frappe's documented `bench new-site`. Let Frappe choose `db_name`; read `.db_name` and `.db_user // .db_name` from `site_config.json`.
    - Fail closed if the site is missing before either cache clear. Use `service_completed_successfully` for every application dependency on `configurator`.
    - Add the mail Compose secret and the initial `enable_frappe_logger`, `host_name` and mail keys. Fill only missing keys. Never pass the mail password as an argument.
    - Add the MariaDB and both Redis readiness gates to `update.yml`.
    - Acceptance: a clean first boot creates one site and applies logger/mail config; a second run changes nothing; a missing site fails before cache clear; root and mail secrets are absent from long-running environments; a backup reads the generated database name.

## Deferred documentation checks

These are deliberately **not** built in the documentation-only phase. Resume them
with the code work, after the restructure has been reviewed:

- [ ] A link and anchor checker for every relative Markdown link.
- [ ] A banned-terminology check for "deploy owner", "target system",
      "accepted stack", "finished system" and, where both are in scope, an
      unqualified "the bouncer".
- [ ] A banner check for every target-state page and the `DECISIONS.md`
      decision note.
- [ ] A duplicate-table check that fails if the network, volume, container or
      edge-mode matrix is copied outside its canonical page.
- [ ] A CI job that renders the Mermaid blocks, or a documented manual render
      step if GitHub is the only supported renderer.

Until those exist, the manual review checklist in `docs/CONVENTIONS.md` is the
gate.

## Definition of done

- `docs/ARCHITECTURE.md` is true without qualification.
- A direct deployment works without Cloudflare and without a Cloudflare token.
- The dashboard is private in every edge mode.
- The pipeline holds one SSH key and no passwords.
- Every admin has a named account, their own SSH key and their own sudo password. There is no shared human host login and no shared owner password.
- `deployowner` is locked, has no SSH login, and is the only account in `docker`.
- A developer has no Linux account on a shared host, works locally, and has no production System Manager role.
- Production cannot deploy without a reviewer.
- A developer can request a deploy and cannot read a production secret.
- A bad development build never creates a production job.
- A rollback is a digest and an approval.
- A clean first boot creates the site, enables the Frappe logger and applies the mail settings; a repeated deploy does not overwrite the site configuration.
- The root and mail secrets are absent from every long-running service environment; the site database name is read from `site_config.json`.
- Every admin has their own host account, sudo password, dashboard login and Frappe Desk user; the built-in `Administrator` is break-glass only.
- AppSec is in-band and fail-closed; the Frappe acceptance suite is green before production blocking.
- The host firewall bouncer is active, pulls from loopback LAPI, and enforces all decision origins in its own nftables tables.
- `firewall-host` and the Traefik bouncer use separate keys.
- Telegram receives a test alert, and no other human notification channel is configured.
- A CrowdSec hub update has been performed and rolled back once in development.
- WAF exceptions are narrow, owned, reviewed, tested and expired.
