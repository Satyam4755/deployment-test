# Deployment

Ansible-based deployment for the ERP Frappe stack: a hardened Ubuntu
host, a Traefik edge, a CrowdSec AppSec WAF, MariaDB, Redis, offsite backups,
and a digest-pinned GitHub Actions deploy pipeline.

> **Target state.** This repository describes the system as it is meant to be.
> The remaining code work is tracked in [`IMPLEMENTATION.md`](IMPLEMENTATION.md).
> When a page and the code disagree, the page is authoritative.

> **Identifiers.** Real domains, hostnames, registry names, mail identities,
> backup destinations, SSH ports and personal names live in Ansible Vault, not
> in this repository. See
> [ADR-026](docs/DECISIONS.md#adr-026--confidential-identifiers-live-in-the-vault-and-the-repository-is-non-identifying).

## Start here

Read [`docs/README.md`](docs/README.md). It is the single entry point and links
every other page by audience and task.

## Repository layout

| Path | What it is |
|---|---|
| `docs/` | The specification: architecture, roles, runbooks, security policy |
| `roles/` | The Ansible implementation |
| `playbooks/` | Ordered entry points for each phase |
| `group_vars/` | Shared and per-environment configuration; the production vault is encrypted and the development vault is local and gitignored |
| `examples/` | Tracked vault templates and CI fixtures; placeholders only |
| `scripts/` | Repository checks, including the sensitive-data guardrail |
| `inventory/` | The development and production hosts |
| `IMPLEMENTATION.md` | Build status and the gap between the docs and the code |

## Status

Current build state: [`IMPLEMENTATION.md`](IMPLEMENTATION.md).
