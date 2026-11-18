# Deployment runbook

Use this guide to set up a server, put the application online, check that it
works, and fix common problems. Follow the numbered steps in order for a new
server. If you already have a server, use the links below to jump to the task
you need.

Development and production are shown next to each other at every step. Run one
environment's commands, check the result, and only then continue. Development
and production differ in the server, domain, encrypted secrets, and a few
settings. Do not mix commands or credentials from the two environments.

> **Target state.** This page describes the system as it is meant to be. The
> remaining code work is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).
> When this page and the code disagree, this page is authoritative.

## How to use this runbook

- **First time setting up a server:** follow sections 1–12 in order, then
  install and verify backups in section 16. Register the optional automated
  deployment pipeline by following section 13.
- **Deploying an application update:** use section 15.1. For a manual rollback,
  use section 15.4.
- **Changing server or network settings:** use section 15.5.
- **Something failed:** start at section 19, then return to the step you were
  doing.
- **Restoring from a backup:** use the separate [restore guide](RESTORE.md).

Each step tells you what to do and how to check the result. If the result is
different, stop and use the troubleshooting link instead of moving on.

### Quick navigation

| I want to... | Go to |
|---|---|
| Prepare a new server | [Steps 1–8: prepare and provision](#1-the-identities-and-the-order-they-are-created) |
| Install and test the edge, security, and application | [Steps 9–12: deploy and verify](#9-start-the-edge) |
| Set up automated application deployments | [Section 13: register the pipeline](#13-register-the-pipeline) |
| Deploy an update, undo a deploy, or change settings | [Section 15: after setup](#15-day-2-operations) |
| Set up backups or check routine health | [Sections 16–17: backups and routine operations](#16-backups-and-restore) |
| Add or remove an administrator | [Section 18: manage administrators](#18-add-or-remove-an-admin) |
| Fix a failed step | [Section 19: troubleshooting](#19-troubleshooting) |
| Shut down a server | [Section 20: decommission](#20-decommission-a-server) |

Common checks and problems:

| I need to... | Go to |
|---|---|
| Log in to the private Traefik dashboard | [Verify the dashboard](#verify-the-private-dashboard) |
| Find Traefik startup or request logs | [Traefik logs and router checks](#traefik-is-running-but-the-dashboard-or-a-router-is-missing) |
| Fix certificate file permission errors | [ACME permission errors](#acme-reports-permission-denied-writing-acmejson) |
| Diagnose a failed Cloudflare certificate | [Cloudflare DNS certificate issues](#certificate-issuance-fails-in-cloudflare-dns-mode) |
| Check whether Traefik can reach CrowdSec | [Private LAPI connection](#cloudflare-appears-unable-to-reach-crowdsec-lapi) |
| Test Telegram notifications | [Telegram test and troubleshooting](#telegram-messages-do-not-arrive) |
| Diagnose a `403` response | [HTTP `403` troubleshooting](#every-http-request-returns-403) |

### All sections

- **Prepare:** [1. Accounts](#1-the-identities-and-the-order-they-are-created) ·
  [2. Requirements](#2-what-you-need-before-you-start) ·
  [3. Control computer](#3-prepare-the-control-machine) ·
  [4. Connection details](#4-set-the-connection-values-for-this-session) ·
  [5. Passwords and keys](#5-create-the-passwords-and-keys) ·
  [6. Encrypted settings](#6-fill-the-vault) ·
  [7. Environment settings](#7-set-the-per-environment-values) ·
  [8. First server setup](#8-first-provision--run-as-root)
- **Deploy and check:** [9. Traefik edge](#9-start-the-edge) ·
  [10. CrowdSec security](#10-start-crowdsec) ·
  [11. Application stack](#11-start-the-full-stack) ·
  [12. Smoke checks](#12-check-the-full-chain) ·
  [12.1. Application checks](#121-application-acceptance-is-separate-from-infrastructure-smoke)
- **Operate:** [13. Automated deployment](#13-register-the-pipeline) ·
  [14. Release policy](#14-development-and-production-rollout-policy) ·
  [15. Updates and configuration](#15-day-2-operations) ·
  [16. Backups and restore](#16-backups-and-restore) ·
  [17. Routine checks](#17-routine-operations) ·
  [18. Administrator accounts](#18-add-or-remove-an-admin)
- **Fix or finish:** [19. Troubleshooting](#19-troubleshooting) ·
  [20. Remove a server](#20-decommission-a-server) ·
  [Appendix A. Commands](#appendix-a--full-command-reference) ·
  [Appendix B. Where settings live](#appendix-b--where-each-value-lives)

### Plain-language terms

| Term | Meaning in this guide |
|---|---|
| Control machine | Your own computer, where you run Ansible commands. |
| Host or server | The remote computer where the website runs. |
| Environment | The separate development or production setup. |
| SSH | The secure connection used to log in to the server. |
| DNS | The internet's address book: it maps a website name to a server. |
| Vault | An encrypted file containing passwords and other private settings. |
| Container | One running service, such as Traefik, Redis, or the application. |
| Smoke check | A quick automated test that checks the services and website respond. |
| SSH tunnel | A private connection from your computer to the dashboard on the server. |
| Ansible playbook | A command that applies the saved server configuration. |
| ACME certificate | The HTTPS certificate Traefik requests and renews automatically. |
| LAPI | CrowdSec's private API, used by Traefik to check security decisions. |
| WAF | The web firewall that checks website requests for suspicious traffic. |
| Day-2 operation | A regular task done after the first setup, such as an update or backup. |

### Before running commands

- Run commands from the repository folder on your control machine, unless the
  step says **on the server** or **inside a container**.
- Replace every value in angle brackets, for example `<server-ip>`,
  `<your-admin-name>`, `<domain>`, `<dashboard-host>`.
- Choose either the `development` or `production` command block. Never combine
  them.
- A line ending in `\` continues on the next line; copy the whole command block.
- Type passwords only when prompted. Do not add them to commands or share them
  in logs.

### The values used below

| Value | Development example | Production example | Meaning |
|---|---|---|---|
| `<server-ip>` | `203.0.113.10` | `198.51.100.20` | Public IPv4 address of the host |
| `<your-admin-name>` | `alice` | `alice` or `bob` | The named admin account you will use |
| `<domain>` | `dev.example.com` | `erp.example.com` | Public application hostname |
| `<dashboard-host>` | `traefik.dev.example.com` | `traefik.erp.example.com` | Private Traefik dashboard hostname |
| `SSH_PORT` | `22222` | `22222` | Port `sshd` listens on. The default is `vault_ssh_port`; the `SSH_PORT` environment variable overrides it |
| vault id | `dev` | `prod` | Which vault password decrypts the environment |

The real application domain, site name and dashboard hostname live in the
environment vault (`vault_domain`, `vault_site_name`,
`vault_traefik_dashboard_host`). Shared aliases in `group_vars/all/main.yml`
resolve those values for the selected environment. Change the vault values if
your DNS names are different. Do not change `/etc/hosts` on the server for this
purpose.

---

## 1. The identities, and the order they are created

Five accounts are used to manage the server and website. The table shows who
uses each account and what it is allowed to do. Use only the account named in
the step you are following.

| Identity | How it gets in | What it is for | Created by |
|---|---|---|---|
| `root` | Provider console, or root SSH key during bootstrap | The first provisioning run only. It creates the other accounts. | The hosting provider |
| Named admin (`alice`, `bob`, ...) | Own SSH key, then own Unix password for `sudo` | Administer the host; run Ansible; become `deployowner` for stack work | The first, root run of `server.yml` |
| `deployowner` | Never logs in; reached with `sudo -u deployowner` | Owns the stack directories, `.env` files and Compose files; is the only account in the `docker` group | The first, root run of `server.yml` |
| `ci-deploy` | SSH key stored in GitHub | Runs exactly two root-owned scripts: `erp-deploy` and `erp-smoke` | `server.yml`, only after a real pipeline key is supplied |
| Frappe `Administrator` | Frappe Desk login | Break-glass application account, not a daily login | The one-shot configurator |

The order is deliberate and must not be skipped:

1. **Root provisions.** The first run connects as `root`. It creates the named
   admin accounts, the locked `deployowner`, the firewall, the SSH policy and
   Docker. It then disables root SSH and password authentication.
2. **The named admin takes over.** Every later Ansible run connects as the named
   admin and escalates to `root` with that admin's own `sudo` password. This is
   what allows apt, systemd and `/etc` changes: `deployowner` is a locked service
   identity and cannot perform them.
3. **`deployowner` owns the stack.** Once the host is hardened, stack files and
   containers are owned by `deployowner`. An admin works on the stack with
   `sudo -u deployowner`, so files keep one owner and the application never runs
   as an admin.
4. **The pipeline is registered last.** `ci-deploy` is only created once a real
   public key exists. Until then, `AllowUsers` contains the admins only.

> **Why Ansible becomes `root`, not `deployowner`.** The role installs packages,
> writes `/etc` and controls systemd. A locked service account cannot do that.
> `deployowner` is still the owner of the application stack; Ansible chowns those
> files to `deployowner` explicitly. The two roles are separate on purpose.

### The access rule in one sentence

SSH is key-only and per person; `sudo` asks for that person's own password;
`deployowner` has no password and no SSH login; `ci-deploy` has one key and two
commands. There is no shared human login anywhere.

---

## 2. What you need before you start

| You need | Why |
|---|---|
| A fresh Ubuntu host | The supported baseline is defined in `group_vars/all/main.yml` and kept in code rather than repeated in the docs. |
| 2 vCPU, 4 GB RAM, 40 GB disk minimum | MariaDB, Redis, Frappe workers, Traefik and CrowdSec run together. |
| A public IPv4 address and a provider console | The console is the fallback during the first SSH change. |
| Provider-level ingress rules | Allow inbound TCP on the chosen SSH port and ports 80 and 443. Host UFW rules cannot open a cloud security group or provider firewall. Port 80 must be reachable for HTTP-01 certificate issuance and renewal. |
| DNS control for the application and dashboard names | Certificates are issued by Let's Encrypt. |
| A container registry with the application image | The stack pulls `erp` from the registry. |
| A GitHub repository with Actions enabled | This repository runs Ansible; the application repository dispatches deploys. |
| A Linux, macOS or WSL control machine with a supported Python runtime | Ansible runs here, not on the server. |
| About 90 minutes | The certificate and the first image pull are the slow parts. |

Choose the SSH port **before** hardening. The examples use `22222`, which is a
placeholder; set the real value as `vault_ssh_port` in the environment vault.
Exporting `SSH_PORT` overrides it for a single run, which is useful during
bootstrap. If you leave the host on `22`, use `SSH_PORT=22` in every command
below. The `base` role opens the port in UFW but never edits the port in `sshd`;
changing the port is a manual step on the host, in section 7.

---

## 3. Prepare the control machine

```bash
git clone <repository-url> deployment
cd deployment

python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install ansible-core ansible-lint yamllint

ansible-galaxy collection install -r requirements.yml
ansible --version
```

Install the small helper tools used to generate credentials. On Ubuntu or WSL:

```bash
sudo apt-get update
sudo apt-get install -y openssh-client openssl whois apache2-utils
```

- `openssl` generates random secrets.
- `mkpasswd` from `whois` generates the yescrypt password hash.
- `htpasswd` from `apache2-utils` generates the bcrypt dashboard hash.

On macOS, install them with Homebrew:

```bash
brew install openssh openssl whois httpd
```

Confirm the repository is healthy before touching a server:

```bash
bash scripts/check-docs-versions.sh
ansible-lint --profile production
```

`ansible-lint` is expected to pass. It does not contact a server.

---

## 4. Set the connection values for this session

These four values are read from environment variables at runtime. They are never
committed. Set them in the terminal you will use for the whole procedure.

**Development**

```bash
export TARGET_SERVER_HOST=<dev-server-ip>
export SSH_LOGIN_USER=<your-admin-name>
export DEPLOY_OWNER_USER=deployowner
export SSH_PORT=22222
```

**Production**

```bash
export TARGET_SERVER_HOST=<prod-server-ip>
export SSH_LOGIN_USER=<your-admin-name>
export DEPLOY_OWNER_USER=deployowner
export SSH_PORT=22222
```

`SSH_LOGIN_USER` must be the same name that you put in `vault_base_operators`.
`DEPLOY_OWNER_USER` is normally `deployowner`; change it only if you have a
reason, and change it in both columns.

Confirm that Ansible sees exactly one host per environment:

```bash
ansible-inventory --graph
```

Expected:

```text
@all:
  |--@development:
  |  |--dev_server
  |--@production:
  |  |--prod_server
```

The guard in every playbook refuses to run unless exactly one environment is in
scope, so always pass `--limit development` or `--limit production`.

---

## 5. Create the passwords and keys

Create every credential **before** editing the vault. Keep the plaintext in your
password manager as you go. The vault stores hashes for human passwords, and
plaintext only for the application secrets that a service must read.

### 5.1 Vault password

The vault password encrypts the environment vault file. Development and
production must use different passwords.

Generate one:

```bash
openssl rand -base64 48
```

Store the output in your password manager under a clear name, for example
`erp development vault` or `erp production vault`. Then write it to a
temporary file for this session:

```bash
umask 077
read -r -s -p "Vault password: " VAULT_PASSWORD
printf '\n'
printf '%s' "$VAULT_PASSWORD" > /tmp/vault_pass
unset VAULT_PASSWORD
chmod 600 /tmp/vault_pass
```

Repeat with the production password when you work on production. Only one vault
password is in the file at a time, and every command below passes exactly one
`--vault-id`.

> Keep a sealed copy of the production vault password somewhere independent of
> the admins' laptops. There is no recovery from the encrypted file alone.

### 5.2 Admin SSH key pair

Each admin has their own key. Generate it on your own machine:

```bash
ssh-keygen -t ed25519 -a 100 -C "<your-admin-name>@admin-laptop" -f ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

Copy the whole `ssh-ed25519 ...` line. It goes into `vault_base_operators` in
section 6. The private key never leaves your machine and is never committed.

If you already have `~/.ssh/id_ed25519`, use it rather than replacing it, or name
the new key explicitly and pass `--private-key` on every command.

### 5.3 Admin Unix password and yescrypt hash

The Unix password is used only by `sudo`, not by SSH. Generate a strong initial
password and store it in your password manager:

```bash
openssl rand -base64 24
```

Now produce the yescrypt hash. `mkpasswd` prompts twice, so the password does not
enter shell history:

```bash
mkpasswd --method=yescrypt
```

Copy the printed line, which starts with `$y$`. It goes into
`vault_operator_password_hashes` under your account name.

Set the same plaintext password in `/tmp/become_pass` for Ansible. Enter it at
the hidden prompt; do not put it in shell history or print the file:

```bash
umask 077
read -r -s -p "Admin sudo password: " BECOME_PASSWORD
printf '\n'
printf '%s' "$BECOME_PASSWORD" > /tmp/become_pass
unset BECOME_PASSWORD
chmod 600 /tmp/become_pass
```

`--become-password-file /tmp/become_pass` is how Ansible answers `sudo`. The
plaintext stays on your control machine; the vault holds only the hash.

### 5.4 Traefik dashboard password and bcrypt hash

The dashboard has its own per-person basic-auth credential. It does not have to
match the Unix password.

```bash
htpasswd -B -C 12 -n <your-admin-name>
```

Type the dashboard password twice. The output looks like
`<your-admin-name>:$2y$12$...`. Store the plaintext in your password manager and
put only the hash in `vault_traefik_dashboard_users`.

### 5.5 Application and infrastructure secrets

Generate each value once and paste it straight into the vault editor in section
6. Do not paste secrets into a command that is recorded in shell history.

| Vault variable | How to create it | Notes |
|---|---|---|
| `vault_db_root_password` | `openssl rand -hex 32` | Hex avoids quoting problems in SQL and shell. |
| `vault_db_encryption_key` | `openssl rand -base64 32` | InnoDB key material. Losing it makes the data unreadable. |
| `vault_db_key_password` | `openssl rand -hex 32` | Protects the key above. |
| `vault_admin_password` | `openssl rand -base64 24` | Frappe `Administrator`, break-glass only. |
| `vault_mail_password` | From your SMTP provider | Required when `frappe_email_enabled` is true. |
| `vault_crowdsec_key` | `openssl rand -hex 32` | Shared by the Traefik bouncer and AppSec. A mismatch blocks all HTTP. |
| `vault_crowdsec_firewall_key` | `openssl rand -hex 32` | Separate key for the host firewall bouncer. |
| `vault_cloudflare_email` | Your team's operational email | Let's Encrypt account contact in every mode. |
| `vault_cf_token` | Cloudflare dashboard → API Tokens | Only for Cloudflare DNS modes. Scope `Zone:Zone:Read` and `Zone:DNS:Edit` to one zone. |
| `vault_telegram_bot_token` | Telegram `@BotFather` | Bot token. |
| `vault_telegram_chat_id` | Send the bot a message, then read the chat id | Destination for notifications. |
| `vault_backup_access_key_id` | Object-storage console | Scoped to one bucket. |
| `vault_backup_secret_access_key` | Object-storage console | Same key pair. |
| `vault_site_name` | Required | Exact Frappe site name. Both environment configurations require it; normally use the application domain. |

Generate the random values one at a time so you can paste each into the right
field:

```bash
openssl rand -hex 32       # database root password
openssl rand -base64 32    # InnoDB encryption key
openssl rand -hex 32       # InnoDB key password
openssl rand -base64 24    # Frappe Administrator password
openssl rand -hex 32       # CrowdSec Traefik/AppSec key
openssl rand -hex 32       # CrowdSec host firewall key
```

The Cloudflare token, SMTP password, Telegram values and backup keys come from
their providers, not from `openssl`.

> The two CrowdSec keys must be different. Using one key for both identities
> defeats the separation between the HTTP bouncer and the host firewall.

---

## 6. Fill the vault

The vault holds every secret, every confidential identifier and every admin's
account name and public key. None of those values is published in the
repository. The tracked configuration only references `vault_*` variables.

The tracked templates are `examples/vault.development.yml` and
`examples/vault.production.yml`. They list every required key. Use them as the
starting point so a key is never forgotten.

### 6.1 Development: copy, fill, then encrypt

The development vault is not tracked. Create it from the template, edit it with
your normal editor, fill every `CHANGE_ME` value, then encrypt it.

```bash
cp examples/vault.development.yml group_vars/development/vault.yml
$EDITOR group_vars/development/vault.yml
```

When the file is complete:

```bash
ansible-vault encrypt --vault-id dev@prompt group_vars/development/vault.yml
```

The command asks for the development vault password. Confirm the file starts
with `$ANSIBLE_VAULT`:

```bash
head -1 group_vars/development/vault.yml
```

### 6.2 Production: edit the encrypted file

The production vault is already encrypted. Edit it in place:

```bash
ansible-vault edit --vault-id prod@prompt group_vars/production/vault.yml
```

This opens a temporary decrypted copy in your editor. Save and close to re-encrypt
it. Never decrypt to a file inside the repository.

### 6.3 The contents of the vault

The two blocks below are complete examples. Replace every `<...>` value. The
development and production blocks differ in the site name, the domain, the ACME
contact, and whether a Cloudflare token is needed. The canonical list of keys is
`examples/vault.development.yml`; keep it in sync when the configuration grows.

**Development — `group_vars/development/vault.yml`**

```yaml
---
# --- confidential identifiers -------------------------------------------
# Real values, not examples. They are why this file is encrypted.
vault_domain: "<dev application domain>"
vault_site_name: "<dev site name, usually the domain>"
vault_traefik_dashboard_host: "<dev dashboard hostname>"
vault_ssh_port: "<ssh port>"
vault_app_image_repository: "<registry namespace>/erp"
vault_backup_remote_name: "<rclone remote name>"
vault_backup_bucket: "<bucket name>"
vault_backup_endpoint: "<S3 endpoint, or empty for AWS>"
vault_mail_server: "<SMTP host>"
vault_mail_login: "<SMTP login>"
vault_mail_sender_name: "<sender name shown to recipients>"

# Admin accounts. Names and public keys are kept here, not in the repository.
vault_base_operators:
  - name: "<your-admin-name>"
    keys:
      - "ssh-ed25519 AAAAC3... <your-admin-name>@admin-laptop"

# One yescrypt hash per admin, keyed by the same name.
vault_operator_password_hashes:
  "<your-admin-name>": "$y$j9T$..."

# Per-person Traefik dashboard basic-auth. One bcrypt hash per admin.
vault_traefik_dashboard_users:
  "<your-admin-name>": "$2y$12$..."

# Application and infrastructure secrets.
vault_db_root_password: "<openssl rand -hex 32>"
vault_db_encryption_key: "<openssl rand -base64 32>"
vault_db_key_password: "<openssl rand -hex 32>"
vault_admin_password: "<openssl rand -base64 24>"
vault_mail_password: "<SMTP password>"

# Let's Encrypt account contact. Required in every mode.
vault_cloudflare_email: "ops@example.com"

# Cloudflare DNS token. Direct mode does not use it; leave the placeholder.
vault_cf_token: "CHANGE_ME_DEV_CF_TOKEN"

# CrowdSec. The two keys must be different.
vault_crowdsec_key: "<openssl rand -hex 32>"
vault_crowdsec_firewall_key: "<openssl rand -hex 32>"

# Telegram notifications. Optional if crowdsec_telegram_enabled is false.
vault_telegram_bot_token: "<bot token>"
vault_telegram_chat_id: "<chat id>"

# Offsite backup credentials.
vault_backup_access_key_id: "<access key>"
vault_backup_secret_access_key: "<secret key>"

# CI deploy public keys. Keep empty until section 13 registers a real key.
vault_ci_deploy_authorized_keys: []
```

**Production — `group_vars/production/vault.yml`**

```yaml
---
# --- confidential identifiers -------------------------------------------
# Real values, not examples. They are why this file is encrypted.
vault_domain: "<production application domain>"
vault_site_name: "<production site name, usually the domain>"
vault_traefik_dashboard_host: "<production dashboard hostname>"
vault_ssh_port: "<ssh port>"
vault_app_image_repository: "<registry namespace>/erp"
vault_backup_remote_name: "<rclone remote name>"
vault_backup_bucket: "<bucket name>"
vault_backup_endpoint: "<S3 endpoint, or empty for AWS>"
vault_mail_server: "<SMTP host>"
vault_mail_login: "<SMTP login>"
vault_mail_sender_name: "<sender name shown to recipients>"

# Admin accounts. Names and public keys are kept here, not in the repository.
vault_base_operators:
  - name: "<your-admin-name>"
    keys:
      - "ssh-ed25519 AAAAC3... <your-admin-name>@admin-laptop"

# One yescrypt hash per admin, keyed by the same name.
vault_operator_password_hashes:
  "<your-admin-name>": "$y$j9T$..."

# Per-person Traefik dashboard basic-auth. One bcrypt hash per admin.
vault_traefik_dashboard_users:
  "<your-admin-name>": "$2y$12$..."

# Application and infrastructure secrets.
vault_db_root_password: "<openssl rand -hex 32>"
vault_db_encryption_key: "<openssl rand -base64 32>"
vault_db_key_password: "<openssl rand -hex 32>"
vault_admin_password: "<openssl rand -base64 24>"
vault_mail_password: "<SMTP password>"

# Let's Encrypt account contact. Required in every mode.
vault_cloudflare_email: "ops@example.com"

# Cloudflare DNS token: required because production uses DNS-01.
vault_cf_token: "<Cloudflare API token with Zone:Zone:Read and Zone:DNS:Edit>"

# CrowdSec. The two keys must be different.
vault_crowdsec_key: "<openssl rand -hex 32>"
vault_crowdsec_firewall_key: "<openssl rand -hex 32>"

# Telegram notifications. Optional if crowdsec_telegram_enabled is false.
vault_telegram_bot_token: "<bot token>"
vault_telegram_chat_id: "<chat id>"

# Offsite backup credentials.
vault_backup_access_key_id: "<access key>"
vault_backup_secret_access_key: "<secret key>"

# CI deploy public keys. Keep empty until section 13 registers a real key.
vault_ci_deploy_authorized_keys: []
```

Two rules keep the vault usable:

- Every `name` in `vault_base_operators` must have a matching key in
  `vault_operator_password_hashes`. `roles/base` refuses to run otherwise.
- Every admin who uses the dashboard needs a matching entry in
  `vault_traefik_dashboard_users`, or they cannot sign in to it.

### 6.4 Verify the vault

View it without writing a decrypted copy:

```bash
ansible-vault view --vault-id dev@prompt group_vars/development/vault.yml
```

```bash
ansible-vault view --vault-id prod@prompt group_vars/production/vault.yml
```

Check that the file contains no `CHANGE_ME` left by accident:

```bash
ansible-vault view --vault-id dev@prompt group_vars/development/vault.yml | grep CHANGE_ME
```

```bash
ansible-vault view --vault-id prod@prompt group_vars/production/vault.yml | grep CHANGE_ME
```

The only value that may legitimately remain a placeholder is `vault_cf_token` in
direct mode. Every other placeholder must be replaced before provisioning.

### 6.5 Commit the encrypted vault

The development vault is untracked by design, so there is nothing to add for it.
Only the encrypted production vault is committed.

```bash
git status --short
# group_vars/development/vault.yml must not appear here
git add group_vars/production/vault.yml
git commit -m "Add the production vault"
git push
```

Before you commit, confirm that `git diff --cached` shows only the production
vault and that it starts with `$ANSIBLE_VAULT`. Never commit the development
vault: `.gitignore` excludes it on purpose, because it is the file most likely
to be filled in on a laptop and left in plaintext.

---

## 7. Set the per-environment values

Environment-specific operational choices live in `group_vars/<env>/main.yml`.
Common variable aliases live in `group_vars/all/main.yml`; the values that name
the site, host, organisation or people remain in the matching environment
vault. Review both the operational values and the vault values before the first
run.

**Development — `group_vars/development/main.yml`**

```yaml
env_name: "development"
base_dir: "{{ deploy_owner_home }}/app_server_dev"

# Direct edge mode: HTTP-01, no Cloudflare proxy.
traefik_cert_resolver: "http"

# Development uses the Let's Encrypt staging CA.
cloudflare_acme_server: "{{ acme_staging_url }}"

# The bouncer is on so the whole chain is exercised.
traefik_crowdsec_enabled: true
```

**Production — `group_vars/production/main.yml`**

```yaml
env_name: "production"
base_dir: "{{ deploy_owner_home }}/app_server"

# Cloudflare proxy mode: DNS-01, orange-cloud proxy enabled.
traefik_cert_resolver: "cloudflare"
traefik_trusted_ips: "{{ cloudflare_ips + ['127.0.0.1/32'] }}"
traefik_origin_cloudflare_only: true

# Production uses the real Let's Encrypt CA.
cloudflare_acme_server: "{{ acme_prod_url }}"

# Keep the Traefik bouncer off until the host layer is proven.
traefik_crowdsec_enabled: false
```

The admin list is **not** in either environment's `main.yml`.
`base_operators` and `ci_deploy_authorized_keys` are shared aliases in
`group_vars/all/main.yml` that read their values from the selected environment
vault, so account names and public keys never appear in tracked plaintext.

If `frappe_email_enabled` is `false`, the mail settings are not required. If it is
`true` (the default), set a real SMTP host and login and put the password in
`vault_mail_password`. The configurator fails before creating the site if mail is
enabled and incomplete.

### Choose the edge mode

| Mode | DNS | Proxy | Certificate | Cloudflare token | App-router allowlist |
|---|---|---|---|---|---|
| Direct | A record at any provider | No | HTTP-01 | No | None |
| Cloudflare DNS, no proxy | Cloudflare, grey cloud | No | DNS-01 | Yes | None |
| Cloudflare proxy | Cloudflare, orange cloud | Yes | DNS-01 | Yes | `cloudflare-allow` |

The mode is three values that must change together: `traefik_cert_resolver`,
`traefik_trusted_ips` and `traefik_origin_cloudflare_only`. Do not set one without
the others. The exact values are in [`ROLES.md`](ROLES.md#edge-mode-values).

The dashboard allowlist is private in every mode. It is not the public app
router.

---

## 8. First provision — run as `root`

This is the only run that logs in as `root`. It creates the accounts every later
run depends on. Keep the provider console open until step 8.6 succeeds.

### 8.1 Create the DNS records

| Record | Development | Production | Points at |
|---|---|---|---|
| Application A record | `dev.example.com` | `erp.example.com` | `<server-ip>` |
| Dashboard A record | `traefik.dev.example.com` | `traefik.erp.example.com` | `<server-ip>` in direct mode only |

- **Direct mode:** both records are plain A records pointing at the server.
  HTTP-01 needs the application name to resolve before the certificate request.
- **Cloudflare DNS modes:** create the application record in Cloudflare. The
  dashboard does not need a public record; the SSH tunnel supplies the hostname.
  For production, enable the orange-cloud proxy on the application record before
  provisioning. DNS-01 uses a token scoped to the zone with both Zone Read and
  DNS Edit permissions.

Confirm propagation from your control machine:

```bash
dig +short dev.example.com
dig +short erp.example.com
```

In direct mode, wait until the answer is the server address. With Cloudflare
proxy enabled, the public lookup returns Cloudflare addresses instead. In either
case, ensure the record is active and points to the server in the Cloudflare
dashboard before requesting a certificate.

For the production orange-cloud record, the public DNS answer should be a
Cloudflare address, while the Cloudflare DNS record's origin is the server's
public address. Confirm both sides in the Cloudflare dashboard; a public DNS
lookup cannot reveal which origin is configured behind the proxy.

### 8.2 Set the SSH port on the host

Run this on the host, as `root`, from the provider console. Skip it if you are
keeping port `22`.

```bash
tee /etc/ssh/sshd_config.d/10-port.conf >/dev/null <<'EOF'
Port 22222
PubkeyAuthentication yes
EOF
sshd -t
systemctl reload ssh
```

From your control machine, confirm the new port answers before continuing:

```bash
ssh -p 22222 root@<server-ip> true
```

If this fails, fix the port or the firewall before running Ansible. Never harden
a host you cannot reach.

### 8.3 Install a root bootstrap key

Generate a dedicated key for the bootstrap, or reuse an existing root key:

```bash
ssh-keygen -t ed25519 -C "root-bootstrap@<your-admin-name>" -f ~/.ssh/id_root
ssh-copy-id -i ~/.ssh/id_root.pub -p 22222 root@<server-ip>
ssh -i ~/.ssh/id_root -p 22222 root@<server-ip> true
```

If the host only accepts a root password, `ssh-copy-id` will ask for it. If
password login is already disabled and you have no key, use the provider console
to append the public key to `/root/.ssh/authorized_keys`.

### 8.4 Run the bootstrap

The bootstrap run needs the vault because the admin accounts are in it. It does
not need a `sudo` password: it is already `root`.

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  -e ansible_user=root -e ansible_become_user=root \
  -e ansible_port="${SSH_PORT}" \
  --vault-id dev@/tmp/vault_pass \
  --private-key ~/.ssh/id_root \
  playbooks/server.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  -e ansible_user=root -e ansible_become_user=root \
  -e ansible_port="${SSH_PORT}" \
  --vault-id prod@/tmp/vault_pass \
  --private-key ~/.ssh/id_root \
  playbooks/server.yml
```

If root authenticates with a password instead of a key, replace
`--private-key ~/.ssh/id_root` with `--ask-pass`.

What this run does:

1. Creates one named admin account per entry in `vault_base_operators`, with the
   keys and the yescrypt hash from the vault.
2. Creates `deployowner` as a locked service identity with no SSH login.
3. Installs the sudoers rule for the `base_operators` group.
4. Hardens `sshd`, writes `AllowUsers` with the admin names (and `ci-deploy` only
   when a real pipeline key exists), and disables root and password login.
5. Configures UFW, the Docker `DOCKER-USER` rules, kernel settings, swap and
   unattended security updates.
6. Installs Docker and adds `deployowner` to the `docker` group.

The run ends with a security report. Read it. Every line that says `YES - FIX
THIS` is a failure even if the play recap is green.

> **Keep the console open.** SSH is changed during this run. Every change is
> validated with `sshd -t`, but the console is the fallback if your key is wrong.

### 8.5 Move to the named admin

From now on, do not log in as `root`. Test the admin account with a key, then
with `sudo`:

```bash
ssh -p "${SSH_PORT}" -i ~/.ssh/id_ed25519 "${SSH_LOGIN_USER}"@"${TARGET_SERVER_HOST}" 'id -nG'
```

Expected: the admin's own group list, and **no** `docker` group.

Test `sudo` interactively. It prompts for the admin's Unix password, which is the
one whose hash is in the vault:

```bash
ssh -t -p "${SSH_PORT}" -i ~/.ssh/id_ed25519 "${SSH_LOGIN_USER}"@"${TARGET_SERVER_HOST}" 'sudo -v && sudo id -un'
```

Expected: `root`.

Confirm the SSH policy:

```bash
ssh -t -p "${SSH_PORT}" -i ~/.ssh/id_ed25519 "${SSH_LOGIN_USER}"@"${TARGET_SERVER_HOST}" \
  'sudo sshd -T | grep -E "^(permitrootlogin|passwordauthentication|allowusers)"'
```

Expected:

```text
permitrootlogin no
passwordauthentication no
allowusers <your-admin-name>
```

`ci-deploy` is absent at this point. It is added in section 13, after the pipeline
key exists. That ordering is intentional.

### 8.6 Confirm `deployowner` is a locked service identity

On the host, as the admin:

```bash
getent passwd deployowner
sudo passwd -S deployowner
sudo -u deployowner id
sudo -u deployowner test -w /home/deployowner && echo "stack home writable"
```

Expected:

- the account exists;
- `passwd -S` reports `L` (locked) or `NP` (no password), never `P` with a usable
  password;
- `sudo -u deployowner id` succeeds and names `deployowner`;
- the stack home is writable by that account.

If `deployowner` can log in over SSH, stop. Check `AllowUsers` and the account's
shell. It must not be a login identity.

### 8.7 Re-run the playbook through the normal path

Run the same playbook again, this time as the admin with that admin's `sudo`
password. This proves the two-layer model works before you build on it.

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/server.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/server.yml
```

The recap should show `changed=0` or only the expected service reloads. Ansible
connects as the named admin and becomes `root` through `sudo`; `deployowner` stays
the owner of the application stack.

Before continuing, verify the host services and firewall from the host:

```bash
sudo systemctl is-active ssh docker
sudo ufw status verbose
sudo docker info --format '{{.ServerVersion}}'
```

Both services must report `active`, Docker must print a server version, and UFW
must allow the selected SSH port plus ports 80 and 443. If any check fails, stop
here and use [Troubleshooting](#19-troubleshooting); do not continue to the edge
on a host that is not reachable or cannot run containers.

---

## 9. Start the edge

The edge is Traefik and its `socket-proxy` sidecar. The sidecar is the only
container that talks to the Docker socket, and it exposes only the read-only calls
Traefik needs.

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/traefik.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/traefik.yml
```

Check the containers on the host:

```bash
sudo docker ps --filter 'name=traefik' --filter 'name=socket-proxy' \
  --format 'table {{.Names}}\t{{.Status}}'
```

The Traefik health check must report `healthy`; both containers must be running:

```bash
sudo docker inspect --format '{{.State.Health.Status}}' traefik
sudo docker ps --filter 'name=traefik' --filter 'name=socket-proxy' \
  --format 'table {{.Names}}\t{{.Status}}'
```

Read both the container startup output and Traefik's file log if it is not
healthy or certificate issuance is still pending:

```bash
sudo docker logs --tail 100 traefik
sudo docker exec traefik tail -n 100 /var/log/traefik/traefik.log
```

The daemon log is at `/var/log/traefik/traefik.log`; requests are recorded in
`/var/log/traefik/access.log`. Do not print the Traefik `.env` file or inspect
container environment values while debugging: Cloudflare's DNS token is secret.

Development uses the Let's Encrypt **staging** CA, so the certificate is not
publicly trusted. That is expected. Production uses the real CA and needs the
Cloudflare token and a ready DNS zone.

The Traefik bouncer is on in development from the start. In production it stays
off until section 15.3 proves the host layer. When the bouncer is on and
`streamStartupBlock` is enabled, Traefik waits for CrowdSec before it serves; a
`docker ps` that shows `traefik` as `starting` before CrowdSec exists is normal
for a few seconds, not a failure.

### Verify the private dashboard

The dashboard is private in every mode. Never expose it through Cloudflare or
publish it on the internet. Verify that Traefik installed successfully by
logging in through an SSH tunnel:

Run this check only once Traefik reports `healthy`. If `streamStartupBlock` is
waiting for CrowdSec, finish section 10 first, then return here; that wait is
not a dashboard failure.

```bash
ssh -N -p "${SSH_PORT}" -i ~/.ssh/id_ed25519 \
  -L 8443:127.0.0.1:443 \
  "${SSH_LOGIN_USER}"@"${TARGET_SERVER_HOST}"
```

Add the dashboard hostname to your local hosts file as `127.0.0.1`:

```text
127.0.0.1 traefik.dev.example.com
```

Open `https://<dashboard-host>:8443`, sign in with your own dashboard username
and password, and confirm the dashboard overview and `/api/rawdata` load. The
password is the one whose bcrypt hash is in `vault_traefik_dashboard_users`;
there is no shared `admin` login. In development the dashboard certificate
comes from the staging CA, so the browser warns. Close the tunnel when you
finish.

If login or the dashboard fails, check the tunnel, the exact dashboard hostname,
the `dashboard-users` secret, the private allowlist, and the Traefik logs above.
Do not make the dashboard public to work around an allowlist or tunnel problem.

---

## 10. Start CrowdSec

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/crowdsec.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/crowdsec.yml
```

This does six things:

1. Writes the acquisition files for the Traefik access log and the host SSH log.
2. Installs the target collections.
3. Registers the Traefik/AppSec bouncer with the LAPI key from the vault and
   verifies the key afterwards.
4. Registers the separate `firewall-host` bouncer, installs the nftables bouncer
   package and starts its systemd service.
5. Writes the Telegram notification profile when it is enabled.
6. Checks that the LAPI and AppSec are reachable from inside the Traefik
   container.

Verify on the host:

```bash
sudo systemctl is-active crowdsec-firewall-bouncer
sudo nft list tables | grep crowdsec
sudo docker exec crowdsec cscli bouncers list
sudo docker exec crowdsec cscli metrics show appsec
```

`firewall-host` must show a recent `Last API pull`. If it does not, the host
service is not enforcing new decisions.

Verify LAPI reachability from the same network namespace Traefik uses. This
check is deliberately run inside the Traefik container:

```bash
sudo docker exec traefik \
  wget --no-verbose --tries=1 --spider http://crowdsec:8080/health
sudo docker exec crowdsec cscli bouncers list
sudo docker exec crowdsec cscli metrics show appsec
sudo docker exec crowdsec test -r /var/log/traefik/access.log
```

The health request must succeed, the `traefik` bouncer must be registered, and
CrowdSec must be able to read the access log. An empty AppSec metric immediately
after deployment is not proof of failure; make a normal request through
Traefik and check again.

If Telegram notifications are enabled, send an explicit test after setup:

```bash
sudo docker exec crowdsec cscli notifications list
sudo docker exec crowdsec cscli notifications test telegram
```

Confirm the test message arrives in the configured Telegram chat. This command
sends a real message; it is manual and is not run automatically during each
deployment. If it does not arrive, follow [Troubleshooting](#19-troubleshooting).

---

## 11. Start the full stack

`site.yml` runs the whole stack in dependency order and is safe to re-run. It
creates the networks and volumes, then Traefik, CrowdSec, MariaDB, Redis and the
application. It does **not** install backups.

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml
```

Then install and verify backups with the dedicated playbook. A host is not
production-ready until this succeeds:

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/backup.yml
```

The first run creates the Frappe site through the one-shot `configurator`:

1. It creates the site with `bench new-site`, using the MariaDB root secret and
   the Frappe `Administrator` password.
2. It writes the initial site configuration: `enable_frappe_logger`, `host_name`,
   and the outgoing-mail settings.
3. It fails closed if the site has no database identity, or if mail is enabled
   and incomplete.

The configurator is the only application-side service that receives the MariaDB
root and mail secrets. The runtime services use the per-site database user and
read the mail password from `site_config.json`.

Before testing the public application, verify the data stores:

```bash
sudo docker exec mariadb-database \
  healthcheck.sh --connect --innodb_initialized
sudo docker exec redis-cache redis-cli ping
sudo docker exec redis-queue redis-cli ping
```

MariaDB's health check must exit successfully and both Redis commands must print
`PONG`. The one-shot `configurator` and `asset-syncer` containers should exit
with status `0`; inspect `sudo docker logs configurator` if the site was not
created. Do not treat a running backend container alone as proof that the site
is ready.

Verify the public path from the control machine.

**Development** (staging certificate, so `--insecure` is expected):

```bash
curl --insecure --silent --show-error --fail \
  --resolve dev.example.com:443:<dev-server-ip> \
  https://dev.example.com/api/method/ping
```

**Production**:

```bash
curl --silent --show-error --fail \
  https://erp.example.com/api/method/ping
```

The response must be the normal Frappe ping, not `403`. The production request
uses the public hostname so it traverses Cloudflare. A direct request to the
production origin is expected to be rejected by the Cloudflare-only allowlist;
the smoke playbook separately checks the origin locally from the host. If the
public request fails, see [Troubleshooting](#19-troubleshooting).

---

## 12. Check the full chain

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/smoke.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/smoke.yml
```

The report should say:

- no long-running container has exited, and both one-shot services exited `0`;
- the site answers `/api/method/ping` through the edge;
- the certificate is valid for the application hostname;
- CrowdSec can read the Traefik access log, and the Traefik acquisition file
  exists;
- the LAPI is reachable from Traefik;
- the Traefik bouncer is registered;
- a temporary `198.51.100.42` decision is served to Traefik with the vault key,
  then removed.

`playbooks/smoke.yml` does not check the AppSec listener or the SSH acquisition
file. The CI health check (`erp-smoke`) checks AppSec; verify the SSH
acquisition directly only when SSH events are not appearing.

In development, the certificate does **not** chain to a public CA. The staging CA
is reported as untrusted. That single result is expected. Every other check must
pass.

The current smoke playbook's certificate assertion requires a publicly trusted
certificate, so it can exit non-zero in development when the staging
certificate is served. Treat only that known staging trust assertion as
expected; every other failed task is a deployment failure. Production must pass
the certificate assertion.

> **Rollout vs steady state.** The **host firewall bouncer** is installed in every
> environment by `crowdsec.yml`. The **Traefik bouncer** is controlled by
> `traefik_crowdsec_enabled`. Development has it on. Production turns it on only
> after the host layer and the development acceptance suite pass.

### 12.1 Application acceptance is separate from infrastructure smoke

The smoke playbook proves that the containers, edge, certificate and selected
CrowdSec checks respond. It does **not** prove that ordinary ERPNext/Frappe
workflows succeed. The WAF acceptance cases in [`WAF.md`](WAF.md#frappe-workflow-acceptance-suite)
are currently a manual checklist, not an automated test script. Record the
application image digest, test date, tester and result for each environment.

Before enabling the fail-closed Traefik bouncer in production, exercise these
flows on development through the public hostname and Traefik:

| Workflow | Acceptance |
|---|---|
| Login and Desk | Login page and Desk load; a test user can sign in and navigate normally. |
| Document work | Create, read, update and delete a non-destructive test record using ordinary content. |
| API | Authenticated API read and write succeed; expected permission failures remain application responses. |
| Files | Upload, download and preview representative small files; test the supported large-upload path separately. |
| Background work | A queued task completes; scheduler-driven work runs as expected. |
| Realtime | WebSocket connection succeeds and a representative Desk notification/update arrives. |
| Email | Send a test message and confirm delivery; avoid real customer recipients. |
| WAF negatives | The approved negative probes in `WAF.md` are blocked, and normal requests are not blocked. |

Any ordinary workflow returning an unexplained `403`, failed job, failed
upload, missing realtime update or undelivered test email is a failed
acceptance. Identify the failing layer and fix it in development before
enabling the production bouncer. A green infrastructure smoke alone is not
approval to enable it.

---

## 13. Register the pipeline

The pipeline is a second, much narrower lane: one SSH key and two root-owned
scripts. It cannot read the vault, change infrastructure or open a shell.

### 13.1 Generate the CI key pair

Generate it on an admin's control machine, never on a server:

```bash
ssh-keygen -t ed25519 -C "ci-deploy@github" -f /tmp/ci_deploy -N ''
ls -l /tmp/ci_deploy /tmp/ci_deploy.pub
```

### 13.2 Add the public key

Add the contents of `/tmp/ci_deploy.pub` to `vault_ci_deploy_authorized_keys` in
**both** environment vaults. It is an identifier, not a credential, but a key
comment or fingerprint names the operator, so it is not committed.

**Development**

```bash
ansible-vault edit --vault-id dev@prompt group_vars/development/vault.yml
```

```yaml
vault_ci_deploy_authorized_keys:
  - "ssh-ed25519 AAAAC3... ci-deploy@github"
```

**Production**

```bash
ansible-vault edit --vault-id prod@prompt group_vars/production/vault.yml
```

```yaml
vault_ci_deploy_authorized_keys:
  - "ssh-ed25519 AAAAC3... ci-deploy@github"
```

The private half never touches the repository or a server. Commit the encrypted
production vault if it changed; the development vault is not tracked:

```bash
git add group_vars/production/vault.yml
git commit -m "Register the CI deploy key in the production vault"
git push
```

### 13.3 Create the account and the two scripts

`server.yml` adds `ci-deploy` to `AllowUsers` and installs the restricted sudo
rule. `site.yml` installs the two scripts that rule names.

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/server.yml

ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/server.yml

ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml
```

### 13.4 Configure GitHub

In the repository, open **Settings → Environments** and create two environments.

**`development`**

| Setting | Value |
|---|---|
| Required reviewers | none |
| Deployment branches | `main` |
| Secret `CI_DEPLOY_SSH_KEY` | The contents of the private file `/tmp/ci_deploy` |
| Variable `TARGET_SERVER_HOST` | The development server address |
| Variable `CI_DEPLOY_USER` | `ci-deploy` |
| Variable `SSH_PORT` | `22222` |

**`production`**

| Setting | Value |
|---|---|
| Required reviewers | one designated reviewer |
| Prevent self-review | **on** |
| Deployment branches | `main` only |
| Secret `CI_DEPLOY_SSH_KEY` | The contents of the private file `/tmp/ci_deploy` |
| Variable `TARGET_SERVER_HOST` | The production server address |
| Variable `CI_DEPLOY_USER` | `ci-deploy` |
| Variable `SSH_PORT` | `22222` |

No environment holds a vault password, a sudo password or an application secret.
The pipeline deploys one image digest; it never runs Ansible.

### 13.5 Configure the application-repository dispatch

The deployment workflow listens for a GitHub `repository_dispatch` event whose
type is exactly `deploy`. The application repository must send the digest after
the image is pushed. Its workflow needs a token that can dispatch an event to
`knapsfs/deployment`; the deployment workflow does not create or configure this
credential.

Create a fine-grained token (or a GitHub App installation token) limited to the
`knapsfs/deployment` repository, with **Contents: read and write** permission
for the repository-dispatch endpoint. Store it in the application repository's
Actions secrets as `DEPLOYMENT_REPO_DISPATCH_TOKEN`. Do not use the deploy SSH
key or a deployment environment secret for this token. Set an expiry and rotate
it before expiry.

The application workflow must use that secret as `GH_TOKEN` and dispatch the
payload below after a successful image push. Replace `<digest-from-push>` with
the pushed image's full `sha256:` digest. The actor is an audit label, not an
authorization mechanism.

```yaml
- name: Dispatch the built image to deployment
  env:
    GH_TOKEN: ${{ secrets.DEPLOYMENT_REPO_DISPATCH_TOKEN }}
    IMAGE_DIGEST: ${{ steps.push.outputs.digest }}
  run: |
    gh api --method POST repos/knapsfs/deployment/dispatches \
      -f event_type=deploy \
      -F "client_payload[digest]=$IMAGE_DIGEST" \
      -F "client_payload[environment]=development" \
      -F "client_payload[actor]=$GITHUB_ACTOR"
```

The deployment workflow requires `digest` to match `sha256:` followed by 64
lowercase hexadecimal characters. `environment` must be `development` or
`production`; normal application builds must dispatch `development`. A
successful development deployment and smoke check lead to the gated production
job. Do not dispatch a production event to bypass development validation.

**Test the integration** with a real, already-pushed development image digest:

1. Run the application workflow that performs the dispatch.
2. Confirm the dispatch step succeeds in the application repository's Actions
   run.
3. Open **Actions → Deploy Application** in `knapsfs/deployment` and confirm
   **Prepare & Validate** shows the expected digest, `development`, and actor.
4. Confirm the development job deploys that digest and `erp-smoke` passes.
5. Confirm a production approval is offered only after the development job
   succeeds.

If the event does not arrive, check the token's repository scope/permission,
secret name, event type, and payload field names. A manual
`workflow_dispatch` of a known digest is an operational fallback, not a
substitute for proving the normal app-repository trigger.

### 13.6 Test the account, then delete the private key

On each host, confirm that `ci-deploy` can run the smoke script and nothing else:

```bash
ssh -p "${SSH_PORT}" -i /tmp/ci_deploy ci-deploy@"${TARGET_SERVER_HOST}" \
  'sudo -n /usr/local/bin/erp-smoke'
```

A command other than the two allowed scripts must fail:

```bash
ssh -p "${SSH_PORT}" -i /tmp/ci_deploy ci-deploy@"${TARGET_SERVER_HOST}" \
  'sudo -n id'
```

Expected: `sudo: a password is required` and a non-zero exit status. If the
command succeeds, stop and correct the sudoers rule before enabling the
pipeline. The positive `erp-smoke` command must exit successfully; a failed
smoke is a failed CI registration, not a reason to bypass the check.

When both hosts pass, destroy the local private key:

```bash
shred -u /tmp/ci_deploy
```

---

## 14. Development and production rollout policy

Development is the place where a change is proved. Production receives the same
artefact only after development passes.

| Change | Development | Production |
|---|---|---|
| Application image | Deploys automatically on merge to `main` | Waits for reviewer approval |
| Stack or edge configuration | Apply, then smoke | Apply only after development passes |
| New admin | Add to the development vault | Add to the production vault separately |
| Traefik bouncer | On from the first run | Off until the host layer is proven |
| Certificate | Let's Encrypt staging | Let's Encrypt production |

Admin access is granted per environment. Being an admin in development does not
give you production access.

---

## 15. Day-2 operations

### 15.1 Deploy an application image

The normal path is the pipeline. A merge to `main` in the application repository
builds and pushes the image, reads its `sha256:` digest, and dispatches this
repository with the version, digest, commit and actor.

1. Development deploys automatically.
2. Development runs `erp-smoke`.
3. Production waits for approval.
4. The same digest deploys to production.
5. Production runs `erp-smoke`.

You do not run an Ansible command for this.

Do not treat a green build or successful SSH connection as deployment
acceptance: `erp-smoke` must pass on the target host after both the development
deploy and the approved production deploy. If development fails, do not approve
production. If production fails, stop further rollout and use the failed job's
output and [Troubleshooting](#19-troubleshooting) to diagnose the service or
edge. After a manual rollback or control-machine deployment, run
`playbooks/smoke.yml` as described in section 12.

### 15.2 Approve a production deploy

Open the waiting run under **Actions**. Before approving, check:

| Field | What it should tell you |
|---|---|
| Version and digest | The same digest that ran in development |
| Commit | The change you expect |
| Actor | A person, not an unrecognised bot |
| Development run | Green, with an `erp-smoke` check that passed |
| Workflow change | The commit should not also change `.github/workflows/**` without review |

The production environment has one designated reviewer and self-review is
disabled. If you triggered the run, ask the other reviewer; if there is no other
reviewer, use the audited control-machine path in section 15.4.

### 15.3 Enable the Traefik bouncer in production

**This is a two-stage rollout.** The first production bootstrap intentionally
leaves CrowdSec HTTP/AppSec inspection off; production is not protected by this
WAF until you complete the steps below. The target state is
`traefik_crowdsec_enabled: true`, applied only after the host layer and
development acceptance checks pass. Do not enable it as part of the initial
bootstrap.

`traefik_crowdsec_enabled: false` in production is a bootstrap value, not the
target state. The bouncer is fail-closed, so enabling it before the chain is
proven turns one broken key, listener or network into an HTTP outage for every
user. See
[ADR-025](DECISIONS.md#adr-025--the-production-traefik-bouncer-is-enabled-only-after-the-chain-is-proven)
for the decision and [`WAF.md`](WAF.md#why-production-starts-with-the-bouncer-off)
for the beginner-level explanation.

Do this only after the host layer is proven and the Frappe acceptance suite in
[`WAF.md`](WAF.md#frappe-workflow-acceptance-suite) passes in development.

1. Prove CrowdSec and the host bouncer without the Traefik bouncer:

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/crowdsec.yml
```

2. On the host, confirm the LAPI and the host bouncer:

```bash
systemctl is-active crowdsec-firewall-bouncer
docker exec crowdsec cscli bouncers list
docker run --rm --network container:traefik alpine \
  wget -qO- http://crowdsec:8080/health
```

3. Set `traefik_crowdsec_enabled: true` in
   `group_vars/production/main.yml`, commit, and run the full stack:

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml
```

4. Run smoke:

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/smoke.yml
```

The bouncer **fails closed**. If AppSec is unreachable or errors, requests return
`403`. If the decision stream cannot be refreshed, Traefik does not continue with
a stale list. A CrowdSec restart is an HTTP outage until CrowdSec, the LAPI and
AppSec are healthy again.

### 15.4 Re-deploy a build or roll back

A rollback is a deploy of an older digest. There is no separate mechanism.

1. Find the previous digest in the last successful run summary, or on the host:

```bash
sudo cat /var/log/erp-deploys.log
```

2. Dispatch it:

```bash
gh workflow run deploy-app.yml \
  -f environment=production \
  -f digest=sha256:0123... \
  -R <org>/<deployment-repo>
```

3. Approve production as usual.
4. Watch the smoke check. A rollback that does not pass smoke is an incident, not
   a rollback.

Images unused for 168 hours are pruned. A rollback older than that needs the
image rebuilt from the same commit, so plan a rollback within the window.

If GitHub is unavailable, use the audited control-machine path. This path needs
the vault, which is exactly why the pipeline does not have it.

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  -e erp_image=sha256:<digest> \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/update.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  -e erp_image=sha256:<digest> \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/update.yml
```

`erp_image` must be a `sha256:` digest. `erp_image_version` is only a
human-readable label; it is not a deploy target. See ADR-004 in
[`DECISIONS.md`](DECISIONS.md#adr-004--pin-by-digest-not-tag).

### 15.5 Change configuration

Anything that is not an image goes through an admin's control machine. That
includes the edge mode, the certificate resolver, the router allowlist, a rate
limit, a Redis setting or a new domain.

Run a dry run first, then apply. Always development first, production second.

**Development**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml --check --diff

ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml
```

**Production**

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml --check --diff

ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml
```

The production vault password cannot decrypt the development vault, and the
reverse is also true. That is why exactly one `--vault-id` is passed.

After applying a configuration change, verify the changed surface and then run
`playbooks/smoke.yml`. A successful Ansible recap only proves that tasks
completed; it does not prove that the public route, certificate, or WAF works.
For a certificate-resolver or edge-mode change, also repeat the dashboard and
public-path checks in sections 9 and 11. If any gate fails, stop before applying
the same change to production.

### 15.6 What the pipeline cannot do

The pipeline cannot:

- edit a compose file, role or template;
- read or write `.env`, the rclone config or a vault file;
- change firewall, SSH, users or sudo;
- change the edge mode, certificate resolver or router allowlist;
- expose the dashboard publicly;
- create a site, restore a backup or rotate a secret;
- deploy to production without a reviewer.

If a change needs one of those, it is a Lane 1 change and needs an admin.

---

## 16. Backups and restore

`roles/backup` installs a systemd timer that runs at **03:17** every day. It dumps
MariaDB and tars the sites volume to object storage, and keeps 30 days.

Backups are **independent of the application deployment**. `site.yml` and
`update.yml` do not install or verify them. A fresh host has no backup timer until
an admin runs the dedicated playbook:

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit <development|production> -e target_env=<development|production> \
  --vault-id <dev|prod>@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_deploy playbooks/backup.yml
```

That run installs rclone, the script and the units, and then runs one verification
backup. A failed verification fails `backup.yml`; it does not stop or roll back the
site. Run it immediately after `site.yml`, before declaring the host
production-ready.

```bash
systemctl list-timers erp-backup.timer
sudo systemctl start erp-backup
sudo journalctl -u erp-backup -n 50
sudo rclone lsf '<rclone-remote>:<bucket>/<environment>/'
```

The playbook must finish successfully, `erp-backup.timer` must be listed, and the
remote must contain a new timestamped directory with `mariadb.sql.gz`,
`sites.tar.gz`, and `manifest.json`. If the service fails, inspect its journal
and check that the configured remote and bucket are reachable; never paste
rclone configuration or credentials into a ticket or terminal transcript.

The remote layout is owned by [`roles/backup.md`](roles/backup.md#remote-layout):

```text
<rclone-remote>:<bucket>/<environment>/<timestamp>/
  mariadb.sql.gz
  sites.tar.gz
  manifest.json
```

Use the actual `vault_backup_remote_name` and `vault_backup_bucket` values for
`<rclone-remote>` and `<bucket>`; the examples below are placeholders, not
required names. Turn on bucket versioning at your provider. The retention rule
deletes by age, so a wrong prefix is the one mistake it cannot undo.

The dump and the sites archive do not include Redis. `redis-cache` is disposable,
and `redis-queue` is not restored by this procedure. Queued jobs from the backup
window may be lost; see
[`roles/redis.md`](roles/redis.md#persistence-and-data-loss).

A backup that has never been restored is a hope, not a backup. Use the
controlled, isolated procedure in [`RESTORE.md`](RESTORE.md) for quarterly
restore drills and disaster recovery. **Do not restore production data over the
live development or production site as a test.**

ERPNext also documents a Google Drive integration that can upload system
backups and public/private files after OAuth authorization:
[Google Drive Integration](https://docs.frappe.io/erpnext/google_drive). This
deployment's configured recovery source remains the role-managed database dump
and sites archive above. Treat Google Drive as an additional candidate, not an
automatic replacement: verify its scheduled behavior, retained backup contents,
access controls, encryption, retention and a complete isolated restore before
changing the recovery policy. Keep backup credentials and site secrets out of
any shared Drive location.

Changing the schedule, destination or credentials is a `backup.yml` change, not a
`site.yml` change. Re-running `backup.yml` re-applies the script, units and rclone
configuration, then runs one verification backup.

---

## 17. Routine operations

### Weekly

Run these on the host, as the admin (prefix each with `sudo` where needed).

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'

docker exec redis-cache redis-cli ping
docker exec redis-queue redis-cli ping
docker exec redis-queue redis-cli info persistence \
  | grep -E 'rdb_last_bgsave_status|aof_enabled'
docker exec redis-queue redis-cli dbsize

systemctl list-timers erp-backup.timer
sudo journalctl -u erp-backup --since "2 days ago" | tail -20

docker exec crowdsec cscli decisions list
docker exec crowdsec cscli alerts list --limit 10
docker exec crowdsec cscli metrics show appsec
docker exec crowdsec cscli appsec-configs list

docker exec crowdsec cscli bouncers list
systemctl is-active crowdsec-firewall-bouncer

docker system df
df -h /
```

### Monthly

```bash
# Configuration drift, read-only.
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml --check --diff
```

A clean diff means the server still matches the repository. A diff is either an
undocumented manual change or an update waiting to be applied. Both are worth
knowing before an incident.

```bash
# Certificate expiry.
echo | openssl s_client -connect erp.example.com:443 -servername erp.example.com 2>/dev/null \
  | openssl x509 -noout -dates

# Is a reboot required after a kernel update?
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required

# Are the host bouncer tables present and the notification path alive?
sudo nft list tables | grep crowdsec
docker exec crowdsec cscli notifications test telegram

# Did hub content drift or become tainted?
docker exec crowdsec cscli hub list | grep -i tainted
```

Certificate renewal follows the mode. HTTP-01 renewals need port 80 reachable.
DNS-01 renewals need the Cloudflare token in the Traefik environment. A failed
renewal is a Lane 1 fix.

The Telegram test message is sent once a month so a broken token or chat is
discovered before an incident. A notification failure does not affect the site.

### Reboots

Unattended upgrades never reboot the host. A kernel update waits until you choose
a window:

```bash
ls -l /var/run/reboot-required
sudo reboot
```

After the reboot, run `playbooks/smoke.yml`. Containers have
`restart: unless-stopped` and Docker has `live-restore`, but a smoke check is how
you know.

### Update CrowdSec

CrowdSec has three separate update paths. Do not treat them as one:

| What | How | Risk |
|---|---|---|
| Hub content (parsers, scenarios, AppSec rules) | `cscli hub update` and `cscli hub upgrade`, then a supported reload | Detection changes; a bad rule causes false positives |
| Engine image | Pull a new tag and recreate the container with the same volumes | AppSec is unavailable during the restart; fail-closed means an HTTP outage |
| Host firewall bouncer package | `apt` upgrade, then restart `crowdsec-firewall-bouncer` | Dynamic host blocking is briefly unavailable; UFW remains |

```bash
docker exec crowdsec cscli hub update
docker exec crowdsec cscli hub upgrade
docker exec crowdsec cscli hub list | grep -i tainted

# Supported reload; use the method that works for the installed image.
docker kill --signal=HUP crowdsec

# Verify that AppSec survived the reload.
docker exec crowdsec cscli metrics show appsec
docker logs --tail 50 traefik
```

If the reload does not keep AppSec listening, stop and use a maintenance window.
Do not leave Traefik pointing at a dead AppSec listener during business hours.

A full container restart is a maintenance-window operation because every HTTP
request is blocked while CrowdSec is down. Before the window:

1. Read the release notes.
2. Record the current image tag and hub state for rollback.
3. Back up the CrowdSec volumes if the engine version changes.
4. Tell the users.
5. After the restart, run `playbooks/smoke.yml` and the WAF acceptance suite.

Do not update the CrowdSec engine, the Traefik bouncer plugin and the host bouncer
package at the same time.

### Update the edge

Traefik and the CrowdSec bouncer plugin are pinned in
`group_vars/all/main.yml`. A version bump is a Lane 1 change. Edit the version,
review the diff, run `--check --diff`, apply the change, then run smoke.

Changing the edge mode or the certificate resolver is also a Lane 1 change.
Update the environment settings first, then run `site.yml`.

A Traefik restart is briefly an HTTP outage even when CrowdSec is healthy. If
`streamStartupBlock` is enabled, Traefik also waits for the initial decision
stream before it serves. Start CrowdSec first, or use `site.yml`.

### Rotate secrets

See [`SECRETS.md`](SECRETS.md). Two rotations are not applied by re-running
Ansible alone: the database root password and the Frappe administrator password.
`SECRETS.md` gives the order for each one.

---

## 18. Add or remove an admin

The admin list is in the encrypted vault, not in the repository. Both the account
name and the public key are there.

### 18.1 Add an admin

1. Ask the new admin to generate a key pair (section 5.2) and send you the public
   key.
2. Generate an initial Unix password and its yescrypt hash (section 5.3).
3. Edit the environment vault:

```bash
ansible-vault edit --vault-id dev@prompt group_vars/development/vault.yml
```

```bash
ansible-vault edit --vault-id prod@prompt group_vars/production/vault.yml
```

```yaml
vault_base_operators:
  - name: "alice"
    keys:
      - "ssh-ed25519 AAAAC3... alice@laptop"
  - name: "bob"
    keys:
      - "ssh-ed25519 AAAAC3... bob@laptop"

vault_operator_password_hashes:
  alice: "$y$j9T$..."
  bob: "$y$j9T$..."
```

4. Run `server.yml` for that environment and verify the new account:

```bash
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/server.yml
```

5. Give the initial password to the new admin out of band. Ask them to run
   `passwd` at first login, then update their own vault hash.
6. Add their dashboard username and bcrypt hash to
   `vault_traefik_dashboard_users` and run `playbooks/traefik.yml`.
7. Create a personal Frappe Desk user. Do not give them the shared
   `Administrator` password.
8. If they will be an additional production reviewer, add them to the GitHub
   `production` environment.
9. Give them the environment vault password through the agreed password-manager
   or sealed-copy process.

Admin access is per environment. Adding someone to development does not add them
to production.

### 18.2 Remove an admin

1. Remove their entry from `vault_base_operators` and
   `vault_operator_password_hashes` in every environment they could access.
2. Run `server.yml` for each of those environments. The role removes the
   account, its home directory and its keys from the host.
3. Remove their dashboard entry and run `playbooks/traefik.yml`, so the old
   dashboard credential stops working.
4. Remove repository access, GitHub reviewer status and Desk access.
5. If they ever held an environment vault password, rekey that vault.
6. Check `journalctl -u ssh`, `last` and the sudo log for unfamiliar activity.

Removing a name from the vault without running `server.yml` changes nothing on
the server.

### 18.3 Rotate an admin's SSH key

1. Replace the public key in that admin's entry in `vault_base_operators`.
2. Run `playbooks/server.yml` for the affected environments.
3. Confirm the old key no longer works.

The `authorized_keys` file is written with `exclusive: true`, so removing a key
from the vault revokes it on the next run.

### 18.4 Rotate an admin's password

1. As the admin, run `passwd` on a host.
2. Generate a new yescrypt hash with `mkpasswd --method=yescrypt`.
3. Update `vault_operator_password_hashes.<name>` in the environment vault.
4. Update the password manager and `/tmp/become_pass` for this session.

The vault hash is used when the account is created or rebuilt. It is not forced
over an existing password on every run, so `passwd` is not overwritten. Keep the
vault hash in step with the real password, or a rebuilt host will come back with
the old one.

---

## 19. Troubleshooting

Run host commands as the named admin. The admin is not in the Docker group, so
prefix Docker commands with `sudo` unless you are explicitly working as
`deployowner`.

### `You must pass --limit` or a vault decryption error

You ran without `--limit <env>`. Ansible then loads both environments and cannot
decrypt the other one's vault. Always pass `--limit` and `-e target_env=`.

### The vault will not decrypt

The vault id and the password must match:
`dev` for `group_vars/development/vault.yml`, `prod` for
`group_vars/production/vault.yml`. Check that `/tmp/vault_pass` holds the right
password and that only one `--vault-id` is passed.

### `Refusing to touch host access` from `roles/base`

The vault is missing `vault_base_operators`, an admin has no key, an admin has no
matching entry in `vault_operator_password_hashes`, or a value still starts with
`CHANGE_ME`. The failure message names the file to edit.

### `Permission denied (publickey)` for your admin account

The key in that admin's `vault_base_operators` entry does not match the key you
are presenting, or `AllowUsers` does not include the account. Check:

```bash
sudo sshd -T | grep -i allowusers
sudo cat /home/<admin>/.ssh/authorized_keys
```

A key that works on development does not automatically work on production. Admin
access is granted per environment.

### `Permission denied (publickey)` for `ci-deploy`

The account exists but `sshd` is not allowing it, or the key was not installed.
Check that `AllowUsers` includes `ci-deploy` and that
`vault_ci_deploy_authorized_keys` is populated and applied:

```bash
sudo sshd -T | grep -i allowusers
sudo cat /home/ci-deploy/.ssh/authorized_keys
```

### `sudo: a password is required` in the pipeline

The restricted sudoers rule is missing or names a different path. Check:

```bash
sudo visudo -c
sudo grep -r erp /etc/sudoers.d/
```

The rule must name the exact absolute path of both scripts, and the scripts must
be root-owned and not writable by `ci-deploy`.

### `sudo` asks for a password you do not have

Use your own admin password. There is no `deployowner` password. If you have
forgotten yours, another admin can reset it with `sudo passwd <admin>` from a
session or the provider console, then update the vault hash.

### Locked out after running `server.yml`

You should not be: every SSH change is validated with `sshd -t`, and the role
refuses to disable password authentication until every admin has a key. Use the
provider console, inspect `/etc/ssh/sshd_config.d/`, and check
`systemctl status ssh`.

### `manifest unknown` or `not found` during a deploy

The digest is not in the registry, or the runner is not logged in to a private
registry. Digests cannot be guessed. Use the one printed by the build.

### The production job never appears after a development deploy

The development smoke check failed. Open that job. The production job is created
only when development passes.

### The approval button is missing

Either you triggered the run (self-review is disabled) or you are not the
designated reviewer for the `production` environment. If you triggered the run
and are the only reviewer, use the audited control-machine path.

### `mariadb` or a Redis service is unreachable from the app

They are on separate internal networks, and each service must join the network for
the data store it needs:

```bash
docker inspect backend --format '{{json .NetworkSettings.Networks}}'
docker inspect websocket --format '{{json .NetworkSettings.Networks}}'
docker inspect frappe-frontend --format '{{json .NetworkSettings.Networks}}'
docker exec redis-cache redis-cli ping
docker exec redis-queue redis-cli ping
docker network inspect erp-db \
  --format '{{range .Containers}}{{.Name}} {{end}}'
docker network inspect erp-cache \
  --format '{{range .Containers}}{{.Name}} {{end}}'
```

The backend must be on `erp_default`, `erp-db` and `erp-cache`. The
websocket must be on `erp_default` and `erp-cache`, not `erp-db`. The
frontend must be on `erp_default` and `traefik-public`, and on neither data
network.

### Traefik will not start and the log mentions the bouncer plugin

The pinned plugin version is not in the Traefik plugin registry. Check
`traefik_bouncer_version` against <https://plugins.traefik.io>, then run
`playbooks/traefik.yml`.

### Traefik is running, but the dashboard or a router is missing

Check the health status, startup log, file log, and loaded dynamic configuration:

```bash
sudo docker inspect --format '{{.State.Health.Status}}' traefik
sudo docker logs --tail 100 traefik
sudo docker exec traefik tail -n 100 /var/log/traefik/traefik.log
sudo docker exec traefik tail -n 50 /var/log/traefik/access.log
```

For the dashboard, confirm the SSH tunnel targets `127.0.0.1:443`, the request
uses the configured dashboard hostname, and your source is allowed by
`dashboard-allow`. A `401` points to the username/hash in
`<base_dir>/traefik/secrets/dashboard-users`; a missing router or `404` points
to the Host rule or dynamic config. Use the authenticated dashboard's
`/api/rawdata` to see which routers and middlewares loaded.

### ACME reports `permission denied` writing `acme.json`

Traefik runs as UID `65532` and stores certificates in the persistent
`traefik-acme` volume. Inspect the directory and, if it exists, the file without
printing their contents:

```bash
sudo docker exec --user 0 traefik sh -c \
  'stat -c "%a %u:%g %n" /etc/traefik/acme; if [ -e /etc/traefik/acme/acme.json ]; then stat -c "%a %u:%g %n" /etc/traefik/acme/acme.json; fi'
```

The directory must be writable by UID `65532`; an existing `acme.json` must be
owned by that UID and mode `0600`. If ownership or mode is wrong, repair only
those permissions and preserve the volume contents:

```bash
sudo docker exec --user 0 traefik sh -c '
  chown 65532:65532 /etc/traefik/acme
  chmod 0700 /etc/traefik/acme
  if [ -f /etc/traefik/acme/acme.json ]; then
    chown 65532:65532 /etc/traefik/acme/acme.json
    chmod 0600 /etc/traefik/acme/acme.json
  fi
'
sudo docker restart traefik
sudo docker logs --tail 100 traefik
```

Do not delete `traefik-acme` or use mode `0777`; it contains the ACME account
key and issued certificates. If this recurs after the volume is recreated,
correct the volume initialization in the role rather than relying on a
one-time repair.

### The site works but CrowdSec blocks nobody

Work through the chain in order:

```bash
sudo docker exec crowdsec ls -l /var/log/traefik/access.log
sudo docker exec crowdsec ls -l /etc/crowdsec/acquis.d/traefik.yaml
sudo docker exec crowdsec ls -l /logs/auth.log
sudo docker exec crowdsec ls -l /etc/crowdsec/acquis.d/sshd.yaml
sudo docker exec crowdsec cscli alerts list
sudo docker exec crowdsec cscli decisions list
sudo docker exec crowdsec cscli metrics show appsec
sudo docker exec crowdsec cscli bouncers list
sudo systemctl status crowdsec-firewall-bouncer
```

If the key was rotated, the old bouncer entry is still registered. Delete the
stale Traefik entry by the name shown in `cscli bouncers list`, then run
`playbooks/crowdsec.yml`.

### Cloudflare appears unable to reach CrowdSec LAPI

Cloudflare does not and must not connect to LAPI. LAPI is private on
`crowdsec-net`; only Traefik and CrowdSec join that network. Test from Traefik,
the client whose reachability matters:

```bash
sudo docker exec traefik \
  wget --no-verbose --tries=1 --spider http://crowdsec:8080/health
sudo docker network inspect crowdsec-net \
  --format '{{range .Containers}}{{.Name}} {{end}}'
sudo docker logs --tail 100 crowdsec
sudo docker exec crowdsec cscli bouncers list
```

The health probe must succeed, and both `traefik` and `crowdsec` must appear on
the network. If the name does not resolve or the connection is refused, check
that CrowdSec is healthy and attached to `crowdsec-net`, then re-run
`playbooks/crowdsec.yml`. If the health probe succeeds but the bouncer is
missing or has no recent pull, check the LAPI key registration and Traefik logs.
Do not publish port `8080` publicly or add the application containers to
`crowdsec-net`.

### Every HTTP request returns `403`

AppSec is fail-closed, so this is often a CrowdSec problem rather than a Frappe
problem. Check the three layers, then use the canonical triage in
[`WAF.md`](WAF.md#the-decision-flow):

```bash
docker exec crowdsec cscli metrics show appsec
docker exec crowdsec cscli bouncers list
docker logs --tail 100 traefik
docker run --rm --network container:traefik alpine \
  wget -qO- http://crowdsec:8080/health
```

- If AppSec is unreachable, check the container, the `crowdsec-net` network and
  whether the AppSec acquisition loaded.
- If the bouncer key is rejected, AppSec returns `401` and the request is blocked
  regardless of the failure flags. Rotate the key back or re-register it.
- If the decision stream is stale, `updateMaxFailure: 0` makes the bouncer fail
  closed. Check the LAPI and the plugin log.
- If Traefik never starts serving after a restart, `streamStartupBlock` is waiting
  for the initial stream. Start CrowdSec first.

Do not disable AppSec globally as the first response. If the site is down and the
change is the cause, roll back the last rule or plugin change and restore the WAF.

### A normal Frappe workflow returns `403` but there is no IP decision

This is an AppSec rule match, not a ban. Identify the rule, then follow the narrow
exception process in [`WAF.md`](WAF.md#handling-a-false-positive). Do not add an
exclusion for all of `/app` or `/api`.

### SSH is blocked after a CrowdSec decision

Use the provider console. List the decisions, remove only the false one, and fix
the scenario. The host bouncer has no permanent admin bypass by design.

```bash
docker exec crowdsec cscli decisions list
docker exec crowdsec cscli decisions remove --ip <address>
```

### The host bouncer is active but a banned address still reaches SSH

Check the correct address family and decision set. The bouncer splits decisions
by origin and IPv4/IPv6, so the first set you inspect may be empty.

```bash
sudo nft list sets | grep crowdsec
sudo nft list table ip crowdsec
sudo nft list table ip6 crowdsec6
```

### Telegram messages do not arrive


```bash
sudo docker exec crowdsec cscli notifications list
sudo docker exec crowdsec cscli notifications test telegram
sudo docker logs --tail 100 crowdsec
```

The test command sends a real generic notification to the configured chat and
does not create a ban. Confirm the plugin is listed and the test message arrives.
If `telegram` is missing, verify `crowdsec_telegram_enabled` and re-run
`playbooks/crowdsec.yml`. If the plugin is listed but the message does not
arrive, check the CrowdSec log and the vault token/chat ID through the normal
secret-rotation process; never print `telegram.yaml` or the token.

### A container published a port the firewall should have blocked

Docker does not go through UFW. `roles/base` installs DOCKER-USER rules for this.
Check:

```bash
sudo iptables -S DOCKER-USER
ls -l /etc/systemd/system/docker.service.d/10-firewall.conf
```

### The certificate check fails in development

This is expected. Development uses the staging CA, so the certificate is not
publicly trusted. Every other smoke assertion must still pass.

### Certificate issuance fails in direct mode

HTTP-01 needs port 80 reachable from the internet. Check the firewall and the DNS
record. If a proxy sits in front, it must pass
`/.well-known/acme-challenge` to the origin.

### Certificate issuance fails in Cloudflare DNS mode

Check the Traefik daemon log and the DNS record in Cloudflare. The token must be
scoped to the correct zone and allow `Zone:Zone:Read` and `Zone:DNS:Edit`; the
DNS-01 resolver must match `traefik_cert_resolver: cloudflare`. Confirm the
public DNS answer and Cloudflare's configured origin separately. Check that
`<base_dir>/traefik/.env` exists and is mode `0600` without displaying its
contents. It should be owned by `deployowner:deployowner`:

```bash
sudo stat -c '%a %U:%G %n' "<base_dir>/traefik/.env"
```

Never use `docker inspect` to print the container environment because it
contains `CF_DNS_API_TOKEN`. Re-run `playbooks/traefik.yml` after correcting the
vault token or resolver.

### The first boot fails in the configurator

Read `docker logs configurator`. The usual causes are a missing root secret, a
missing mail secret while email is enabled, MariaDB or either Redis service not
ready, or incomplete mail settings. The backend does not start until the
configurator exits successfully, so fix the cause and re-run `site.yml`.

### The site is unreachable after enabling the Cloudflare allowlist

Confirm the application DNS record is orange-cloud proxied and its Cloudflare
origin is the server's public address. With
`traefik_origin_cloudflare_only: true`, a gray-cloud record or direct request to
the origin is expected to be rejected; do not turn off origin protection as a
workaround. If the record is orange, check `traefik_trusted_ips` and
`cloudflare-allow`, then verify using the public application hostname so the
request traverses Cloudflare.

### The dashboard is unreachable

Open the SSH tunnel and check that Traefik is healthy, the private allowlist
includes `127.0.0.1/32`, the Host header matches the dashboard hostname, and the
tunnel forwards to `127.0.0.1:443`. Inspect
`sudo docker logs --tail 100 traefik` and
`sudo docker exec traefik tail -n 100 /var/log/traefik/traefik.log`; do not
expose the dashboard publicly to work around a tunnel or allowlist problem.

### The dashboard page loads but your login is rejected

Check that your username has a line in
`<base_dir>/traefik/secrets/dashboard-users` and that the bcrypt hash in
`vault_traefik_dashboard_users` is current. Regenerate your own hash, update the
vault map, and run `playbooks/traefik.yml`.

### The disk is filling up

`roles/docker` removes images unused for 168 hours on every run. Check with
`docker system df`.

### A deploy succeeded but the site is stale

Clear the caches the way the role does:

```bash
cd /home/deployowner/app_server_dev
sudo docker compose exec -T backend sh -c 'test -f sites/<site>/site_config.json' || {
  sudo docker logs --tail 100 configurator
  exit 1
}
sudo docker compose exec -T backend bench --site <site> clear-cache
sudo docker compose exec -T backend bench --site <site> clear-website-cache
```

Use `/home/deployowner/app_server` for production. If the site check fails, read
the configurator log. Do not run the cache clears against a missing or
half-created site.

### The workflow file changed in the same PR as an application change

Treat it as a security review, not a code review. `.github/workflows/**` is owned
by an admin in `CODEOWNERS` precisely so this is visible.

---

## 20. Decommission a server

1. Remove the DNS records for the application and the dashboard, or point them at
   the replacement.
2. Remove the host's key from `vault_ci_deploy_authorized_keys` and run
   `server.yml` against the remaining servers.
3. If the environment is retired, remove its `vault_base_operators` entries and
   its vault. If the host is being replaced, keep the admins and run `server.yml`
   on the replacement.
4. Take a final backup and verify it restores somewhere else.
5. Destroy the host. Do not reuse the disk.
6. If the host held a unique production secret, rotate it. Assume the disk is
   readable by whoever has the hardware.

---

## Appendix A — Full command reference

Use the block for the environment you are working on. Every command assumes the
repository root and the environment variables from section 4.

**Development**

```bash
# Provision or harden the host, as the named admin.
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/server.yml

# First run only, as root.
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  -e ansible_user=root -e ansible_become_user=root \
  -e ansible_port="${SSH_PORT}" \
  --vault-id dev@/tmp/vault_pass \
  --private-key ~/.ssh/id_root \
  playbooks/server.yml

# Edge only.
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/traefik.yml

# CrowdSec only.
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/crowdsec.yml

# Full stack.
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml

# Smoke.
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/smoke.yml

# Control-machine image update.
ansible-playbook -i inventory/inventory.yml \
  --limit development -e target_env=development \
  -e erp_image=sha256:<digest> \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/update.yml
```

**Production**

```bash
# Provision or harden the host, as the named admin.
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/server.yml

# First run only, as root.
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  -e ansible_user=root -e ansible_become_user=root \
  -e ansible_port="${SSH_PORT}" \
  --vault-id prod@/tmp/vault_pass \
  --private-key ~/.ssh/id_root \
  playbooks/server.yml

# Edge only.
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/traefik.yml

# CrowdSec only.
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/crowdsec.yml

# Full stack.
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/site.yml

# Smoke.
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/smoke.yml

# Control-machine image update.
ansible-playbook -i inventory/inventory.yml \
  --limit production -e target_env=production \
  -e erp_image=sha256:<digest> \
  --vault-id prod@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/update.yml
```

Clean up the session files when you finish:

```bash
shred -u /tmp/vault_pass /tmp/become_pass
```

## Appendix B — Where each value lives

| Value | Location |
|---|---|
| Admin account names and public keys | `vault_base_operators` in `group_vars/<env>/vault.yml` (encrypted) |
| Admin Unix password hashes | `vault_operator_password_hashes` in the environment vault |
| Dashboard users and bcrypt hashes | `vault_traefik_dashboard_users` in the environment vault |
| Application and infrastructure secrets | The environment vault |
| Server address, admin name | Environment variables on the control machine; GitHub Environment Variables for the pipeline |
| SSH port | `vault_ssh_port` in the environment vault; `SSH_PORT` overrides it for one run |
| Domain, site name, dashboard host, mail identity | `vault_domain`, `vault_site_name`, `vault_traefik_dashboard_host`, `vault_mail_*` in the environment vault |
| Edge mode, rate limits, bouncer switch | `group_vars/<env>/main.yml` |
| CI public key | `vault_ci_deploy_authorized_keys` in the environment vault |
| CI private key | GitHub Environment secret `CI_DEPLOY_SSH_KEY` |
| Stack files and `.env` | `<base_dir>` on the host, owned by `deployowner` |
| Deploy audit log | `/var/log/erp-deploys.log` on the host, `0600 root` |

## Related pages

- [`SECRETS.md`](SECRETS.md) for the credential inventory and rotation.
- [`ROLES.md`](ROLES.md) for the role map and canonical inventories.
- [`WAF.md`](WAF.md) for the `403` decision flow and acceptance suite.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) for the model behind these commands.
- [`DEVELOPMENT.md`](DEVELOPMENT.md) for the developer workflow.
