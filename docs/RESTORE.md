# Frappe restore and recovery guide

This guide covers restore drills and recovery of the Frappe site deployed by
this repository. It distinguishes an application-data restore from a full
host disaster recovery: the scheduled backup contains a MariaDB logical dump
and the Frappe `sites` volume, but is not a complete copy of the host,
deployment secrets, application image, or MariaDB system database.

> **Destructive operation.** Restoring imports the backup over the target
> site's database tables and replaces the contents of its `erp_sites-vol`
> volume. Never use the live development or production site as a
> restore-drill target. Verify the environment, site name, timestamp and
> manifest before stopping services or changing any data.

The provisioning and backup details are owned by the
[`RUNBOOK.md`](RUNBOOK.md) and [`backup` role page](roles/backup.md). Backups are
installed and verified by `playbooks/backup.yml`, which is separate from
`site.yml` and `update.yml`; a freshly provisioned host has no backup until that
playbook has run successfully.

## Recovery model and limits

The repository-managed `erp-backup` job writes three files under one
timestamped prefix:

```text
<rclone-remote>:<bucket>/<environment>/<timestamp>/
  mariadb.sql.gz
  sites.tar.gz
  manifest.json
```

- `mariadb.sql.gz` contains the Frappe site's database, not the MariaDB
  `mysql` system database or grants.
- `sites.tar.gz` contains the site's files and `site_config.json`. Treat it as
  sensitive: that configuration contains the site's database credentials,
  mail password and site encryption key.
- `manifest.json` identifies the environment, site and backup timestamp and
  records an application version label. It does **not** currently record the
  exact application image digest.
- Redis is not in the backup. Cache data is disposable; queued jobs may be
  lost.

For a restore to a MariaDB instance that already has the site's database user
and grants, the data pair is intended to restore the database and sites files.
A restore target must have an empty database with that same database identity.
The dump creates the database only if it does not exist and replaces tables
represented in the dump; it does not drop the whole database or remove
unrelated tables. If the target database is not empty, stop until a tested
procedure has emptied it while preserving or restoring the required grants.
A clean-host disaster recovery has extra prerequisites: the same site database
name, database user and password from the archived `site_config.json` must
exist in MariaDB and have privileges on the restored database. The SQL dump
does not recreate those grants. The normal Ansible first-site path creates a
new site's database identity; do not assume it will match an older backup.
Before relying on a newly provisioned host for recovery, test and document the
database-user recreation path for the deployed Frappe/MariaDB versions.

Likewise, the manifest's version label is not a content identity. Identify the
compatible image digest from the deploy audit log or the corresponding
GitHub Actions run. Do not guess from a tag or deploy an arbitrary newer image
against a restored database.

The normal application recovery order is:

1. Select and validate one matching backup set.
2. Prepare an isolated target with the matching environment configuration,
   image and database identity.
3. Stop application writers.
4. Restore the database and sites volume from that same set.
5. Start and validate the site while keeping outbound effects controlled.
6. Decide whether to promote the recovered target or discard the drill.

## Backup source: object storage and Google Drive

The current deployment-managed recovery source is the daily
S3-compatible/rclone backup described above. It is configured by
`vault_backup_remote_name`, `vault_backup_bucket` and the backup credentials.
The full destination is:

```text
<rclone-remote>:<bucket>/<environment>/<timestamp>/
```

ERPNext also offers a [Google Drive integration](https://docs.frappe.io/erpnext/google_drive)
that can upload system backups and public/private files after OAuth
authorization. It is an additional backup path, not a proven replacement for
this repository's recovery procedure. Before changing the official recovery
source, verify the exact contents and format, scheduled backup behavior,
retention, access control, encryption, account recovery, and a complete
isolated restore. The documentation notes that for compressed backups over
1 GB, the integration uploads the latest available backup rather than
generating a new one; verify that behavior against the version in use.

Do not let a Drive copy or the object-storage copy be the only copy of the
Google/OAuth credentials, vault passwords, or image digest needed to recover
the host. Keep an independent, access-controlled copy of recovery credentials.

## Before a restore drill

Use a disposable VM/host or an isolated clone of development with separate
Docker volumes. The clone must not share the live site's database, volumes,
DNS records, or public traffic. Restrict ingress at both the provider firewall
and host firewall; prevent outbound mail, webhooks, payment calls and other
external side effects while restored data is being inspected.

Record these values before starting:

| Value | Where to obtain it |
|---|---|
| Environment (`development` or `production`) | The source environment and the backup prefix |
| Backup timestamp | The exact timestamp directory in the remote |
| Frappe site name | The environment vault and the backup's `site_config.json` |
| Compatible application image digest | `/var/log/erp-deploys.log` or the matching deployment Actions run |
| Target stack directory | Development: `/home/deployowner/app_server_dev`; production: `/home/deployowner/app_server` |
| rclone remote and bucket | `vault_backup_remote_name` and `vault_backup_bucket` in the correct environment vault |

For a drill, restore **development data into an isolated development target**.
Do not use production data for a routine drill. If a production recovery is
required, use a controlled recovery host and authorized production credentials.

### Check that the backup set is complete

On the target host, enter a root shell and set the actual remote, bucket,
environment and timestamp. Use only a timestamp copied from the storage
listing; do not type a guessed prefix.

```bash
sudo -i
export RCLONE_CONFIG=/root/.config/rclone/rclone.conf
export BACKUP_REMOTE="<rclone remote name>"
export BACKUP_BUCKET="<bucket name>"
export EXPECTED_ENV="development"
export STAMP="<timestamp copied from the remote>"
export EXPECTED_SITE_NAME="<Frappe site name from the environment vault>"
export RESTORE_DIR="/var/backups/restore/${STAMP}"

case "$EXPECTED_ENV" in
  development|production) ;;
  *) echo "STOP: EXPECTED_ENV must be development or production" >&2; exit 1 ;;
esac
if [[ ! "$STAMP" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; then
  echo "STOP: STAMP must match the timestamp directory format" >&2
  exit 1
fi
```

List available timestamp folders and confirm that the chosen folder belongs to
the intended environment:

```bash
rclone lsf --dirs-only "${BACKUP_REMOTE}:${BACKUP_BUCKET}/${EXPECTED_ENV}/"
rclone lsf "${BACKUP_REMOTE}:${BACKUP_BUCKET}/${EXPECTED_ENV}/${STAMP}/"
```

Download the three files into a root-only directory:

```bash
if [ -e "$RESTORE_DIR" ]; then
  echo "STOP: restore directory already exists; inspect it and choose a fresh path" >&2
  exit 1
fi
install -d -o root -g root -m 0700 "$RESTORE_DIR"
rclone copy \
  "${BACKUP_REMOTE}:${BACKUP_BUCKET}/${EXPECTED_ENV}/${STAMP}" \
  "$RESTORE_DIR"
chmod 0600 "$RESTORE_DIR"/*
```

Check the manifest without printing its identifying values:

```bash
python3 - "$RESTORE_DIR/manifest.json" "$EXPECTED_ENV" "$STAMP" \
  "$EXPECTED_SITE_NAME" "$RESTORE_DIR/sites.tar.gz" <<'PY'
import json
import tarfile
import sys
from pathlib import PurePosixPath

path, expected_environment, expected_timestamp, expected_site, sites_archive = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    manifest = json.load(handle)

if manifest.get("environment") != expected_environment:
    raise SystemExit("STOP: manifest environment does not match the selected target")
if manifest.get("timestamp") != expected_timestamp:
    raise SystemExit("STOP: manifest timestamp does not match the selected backup")
if manifest.get("site_name") != expected_site:
    raise SystemExit("STOP: manifest site does not match the selected target")
required = {"mariadb.sql.gz", "sites.tar.gz", "manifest.json"}
if not required.issubset(set(manifest.get("contains", []))):
    raise SystemExit("STOP: manifest does not list all required backup files")

with tarfile.open(sites_archive, "r:gz") as archive:
    expected_path = PurePosixPath(expected_site, "site_config.json")
    matches = []
    for member in archive.getmembers():
        parts = PurePosixPath(member.name).parts
        if parts and parts[0] == ".":
            parts = parts[1:]
        if PurePosixPath(*parts) == expected_path and member.isfile():
            matches.append(member)
    if len(matches) != 1:
        raise SystemExit("STOP: archive does not contain exactly one expected site_config.json")
    config_file = archive.extractfile(matches[0])
    if config_file is None:
        raise SystemExit("STOP: cannot read archived site_config.json")
    config = json.load(config_file)
    if not config.get("db_name") or not config.get("db_password"):
        raise SystemExit("STOP: archived site_config.json lacks the database identity")

print("Manifest, site path and required database identity match.")
print("The compatible application image digest must still be confirmed separately.")
PY

gzip -t "$RESTORE_DIR/mariadb.sql.gz"
tar -tzf "$RESTORE_DIR/sites.tar.gz" >/dev/null
```

If any command fails, stop. Do not continue with a partial, corrupt, wrong
environment, or wrong timestamp set. The check above confirms the manifest
and archived site name and that the database identity is present. Do not print
`site_config.json` to a shared terminal or paste it into a ticket.

The remote files and the restore directory contain production data and
credentials. Keep the directory mode restricted. Do not copy it to a developer
laptop or an unencrypted disk.

## Restore on an isolated target

This procedure is for a target with the correct site and MariaDB database
identity already present. If the target is a new MariaDB instance without the
matching per-site user/grants, **stop** and complete the clean-host recovery
prerequisite described above before importing data.

### Stop writers and protect the target

Confirm the shell is on the disposable target, the stack directory is the
expected one, and no live production DNS points at it. Ensure no deployment or
backup is running. Check that `systemctl is-active erp-backup.service` reports
`inactive`; if it is active, wait for it to finish and verify its result. Then
stop the scheduled backup timer and the Frappe writers:

```bash
systemctl is-active erp-backup.service
systemctl stop erp-backup.timer
cd /home/deployowner/app_server_dev/erp
docker compose stop scheduler queue-short queue-long websocket backend frappe-frontend
```

For a different approved target, use its verified stack directory. Do not
continue if `docker compose ls` or `docker ps` suggests this is the live
environment or the wrong Docker host.

### Restore the database and site files

The database dump includes a `--databases` header and should target the database
named in the archived site's `site_config.json`. The MariaDB root password is
read from the container secret; it is not placed in the command line.

```bash
gzip -dc "$RESTORE_DIR/mariadb.sql.gz" \
  | docker exec -i mariadb-database sh -c \
      'MYSQL_PWD="$(cat /run/secrets/db_root_password)" exec mariadb -uroot'
```

The next command **deletes every current entry** in `erp_sites-vol` before
extracting the backup. Confirm the target and manifest again immediately before
running it:

```bash
ERP_IMAGE_ID="$(docker compose images -q backend)"
if [ -z "$ERP_IMAGE_ID" ]; then
  echo "STOP: backend image is not present; recover the compatible image first" >&2
  exit 1
fi
docker run --rm --user 0 \
  --network none \
  --mount type=volume,source=erp_sites-vol,target=/data \
  --mount "type=bind,source=${RESTORE_DIR},target=/restore,readonly" \
  --entrypoint bash \
  "$ERP_IMAGE_ID" \
  -ec 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + &&
       tar -C /data -xzf /restore/sites.tar.gz'
```

The restore does not include Redis or the assets volume. Redis is intentionally
not restored; queued jobs can be lost or need to be re-created. Verify that
assets for the compatible application image exist before declaring the site
recovered. If the site has custom apps, confirm they are present in that image;
do not install apps or build assets by modifying a running production
container.

### Start cautiously and validate

Restore data can contain production email settings, webhook credentials and
scheduled work. Keep provider-level egress restricted and do not send real
emails or execute external integrations during a drill. Start the stack only
after verifying the restored site identity and the image digest:

```bash
docker compose up -d
docker compose ps -a
docker logs --tail 100 configurator
docker logs --tail 100 backend
```

Run infrastructure smoke from the control machine, not from the target host's
root shell. Use a temporary inventory containing only the disposable target;
do not use the normal inventory unless you have verified that its environment
host resolves to this disposable machine. For a development drill, create the
inventory on the control machine:

```bash
umask 077
cat > /tmp/recovery-inventory.yml <<'YAML'
all:
  children:
    development:
      hosts:
        recovery_target:
          ansible_host: <DISPOSABLE_HOST_IP>
          ansible_user: <ADMIN_USER>
          ansible_port: <SSH_PORT>
YAML
export RECOVERY_INVENTORY=/tmp/recovery-inventory.yml
```

Set the real connection values, then verify the inventory and resolved host
list contain only the disposable machine before running the smoke:

```bash
ansible-inventory -i "$RECOVERY_INVENTORY" --graph
ansible-playbook -i "$RECOVERY_INVENTORY" \
  --limit development -e target_env=development \
  --list-hosts playbooks/smoke.yml
```

The expected host list is exactly `recovery_target`. Then run:

```bash
ansible-playbook -i "$RECOVERY_INVENTORY" \
  --limit development -e target_env=development \
  --vault-id dev@/tmp/vault_pass \
  --become-password-file /tmp/become_pass \
  --private-key ~/.ssh/id_ed25519 \
  playbooks/smoke.yml
```

For a production recovery, use a temporary inventory with the recovery target
in the `production` group, and use `--limit production`,
`-e target_env=production`, and the production vault id. Never point either
command at the live environment for a restore drill.

Infrastructure smoke is necessary but not sufficient. Through the isolated
host's controlled access path, validate:

- The expected site name and public host configuration are present.
- A named test user can log in; do not use the shared `Administrator` account
  for ordinary access.
- Representative documents and attachments are present and readable.
- An authenticated API read succeeds.
- A small, non-destructive background task completes.
- Realtime/WebSocket behavior works if it is part of the application workflow.
- No real email, webhook, payment or other external side effect was triggered.

If any check fails, preserve logs without exposing credentials and stop the
drill. Do not point production DNS at a failed restore.

## Production recovery decision

For an actual production outage, first decide whether to restore in place or
promote a newly prepared recovery host. Do not overwrite the remaining source
volumes before confirming the selected backup and that no newer valid backup
exists.

Before switching traffic, the recovery owner must verify all of the following:

1. The backup manifest matches `production`, the expected site and one
   timestamp; both data files pass integrity checks.
2. The recovery host has the required environment configuration and vault
   secrets, protected at rest and delivered only to the recovery operators.
3. The compatible application image digest is known from deployment records.
   The backup manifest alone does not provide it.
4. The MariaDB site database identity and grants match the restored
   `site_config.json`. A fresh database does not get these from
   `mariadb.sql.gz`.
5. The restored application passes infrastructure smoke and the relevant
   application workflows.
6. Outbound integrations are reviewed, the production hostname/certificate
   path is correct, and the traffic cutover is deliberate and reversible.

If any of these conditions cannot be verified, treat the restore as incomplete
and do not promote it. After a successful recovery, take a new backup and
verify that it reaches the configured remote.

## Finish a restore drill

Record the backup timestamp, image digest used, environment, test cases,
failures, and elapsed recovery time in the team's approved incident/recovery
record. Stop the isolated stack; `docker compose down` does not delete its
named volumes. Then securely destroy the disposable VM and its attached
storage using the provider's supported disposal process. Remove the host-side
restore copy only after the drill has been accepted:

```bash
docker compose down
case "$RESTORE_DIR" in
  /var/backups/restore/*) ;;
  *) echo "STOP: refusing to remove an unexpected restore path" >&2; exit 1 ;;
esac
if [ "$RESTORE_DIR" != "/var/backups/restore/${STAMP}" ]; then
  echo "STOP: restore path does not match the validated timestamp" >&2
  exit 1
fi
rm -rf -- "$RESTORE_DIR"
```

Do not use this cleanup command on a live host. The restored sites archive and
local files contain application data and credentials.

## Recovery gaps to close before claiming full disaster recovery

- Add an exact, tested procedure for recreating the MariaDB per-site user and
  grants on a clean host from the archived site configuration without exposing
  its database password in process arguments or logs.
- Record the application image digest in the backup manifest, or retain a
  reliable backup-timestamp-to-deployment-digest record outside the host.
- Test the entire clean-host recovery path, including vault/key retrieval,
  image availability, site identity, assets, MariaDB encryption, and DNS/TLS
  cutover.
- Decide whether ERPNext's Google Drive integration is a secondary copy or a
  candidate replacement only after an isolated restore test from that source.

Until these gaps are closed and tested, describe the current automation as a
scheduled application-data backup plus a tested restore path for a target that
retains compatible MariaDB identity—not as a complete host disaster-recovery
solution.
