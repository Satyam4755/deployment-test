# Documentation

This is the specification for the ERP deployment: a hardened Ubuntu host, a
private Traefik edge, a fail-closed CrowdSec AppSec WAF, MariaDB, Redis, the
Frappe application, and offsite backups. The gap between the specification and
the code is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).

> **Target state.** This page describes the system as it is meant to be. The
> remaining code work is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).
> When this page and the code disagree, this page is authoritative.

## Choose your path

| If you are... | Start with |
|---|---|
| New to the project | [`ARCHITECTURE.md`](ARCHITECTURE.md), then [`ROLES.md`](ROLES.md) |
| Deploying a server for the first time | [`RUNBOOK.md`](RUNBOOK.md), top to bottom |
| Deploying an application build | [`RUNBOOK.md`](RUNBOOK.md#151-deploy-an-application-image) |
| Changing infrastructure | [`ROLES.md`](ROLES.md), then [`RUNBOOK.md`](RUNBOOK.md#155-change-configuration) |
| Handling a credential or a person's access | [`SECRETS.md`](SECRETS.md) |
| Restoring a site or running a recovery drill | [`RESTORE.md`](RESTORE.md) |
| Investigating a `403` or changing the WAF | [`WAF.md`](WAF.md) |
| Writing application code | [`DEVELOPMENT.md`](DEVELOPMENT.md) |
| Reviewing a design choice | [`DECISIONS.md`](DECISIONS.md) |
| Looking up a term | [`GLOSSARY.md`](GLOSSARY.md) |

## How the documentation is organised

### Understand

| Page | It answers |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Who can change what, what can reach what, and why the boundaries are drawn there |
| [`ROLES.md`](ROLES.md) | Which role owns each setting, in what order the roles run, and the shared network, volume and container inventory |
| [`GLOSSARY.md`](GLOSSARY.md) | The meaning of a term as it is used here |
| [`SERVER_HARDENING.md`](SERVER_HARDENING.md) | What each host and edge hardening control does, its trade-offs, and remote-access/VNC impact |

### Deploy and operate

| Page | It answers |
|---|---|
| [`RUNBOOK.md`](RUNBOOK.md) | How to provision, deploy, rotate, diagnose and operate, with development and production commands side by side |
| [`RESTORE.md`](RESTORE.md) | Restore drills, destructive-operation safeguards, recovery prerequisites, and the limits of the current backups |
| [`SECRETS.md`](SECRETS.md) | Where each credential lives, how it is rotated, and how access changes |
| [`WAF.md`](WAF.md) | How the WAF decides, how to prove it is safe, and how to handle a false positive |
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | How application code is written and tested locally |

### Reference

| Page | It answers |
|---|---|
| [`DECISIONS.md`](DECISIONS.md) | Why a design choice was made and what was traded away |
| [`IMPLEMENTATION.md`](../IMPLEMENTATION.md) | What remains to build and how it is accepted |
| [`CONVENTIONS.md`](CONVENTIONS.md) | How the documentation is written and who owns each fact |

Every role page is linked from [`ROLES.md`](ROLES.md). The host firewall
bouncer is a component page, not a separate role:
[`roles/crowdsec-firewall-bouncer.md`](roles/crowdsec-firewall-bouncer.md).

## The model in one paragraph

Two privileged lanes share one artefact: the application image. Infrastructure
admins provision hosts from their own control machines; the pipeline deploys one
image digest and holds no access to the host configuration. Developers work
outside both lanes, and the public edge can reach the application only through
Traefik and the WAF. The full trust model is in
[`ARCHITECTURE.md`](ARCHITECTURE.md).

## Documentation rules

The short version:

- Docs describe the target state. [`IMPLEMENTATION.md`](../IMPLEMENTATION.md)
  records what is still to build.
- Every shared fact has one canonical owner. Other pages link to it.
- Procedures live in `RUNBOOK.md`, `SECRETS.md`, `WAF.md` or
  `RESTORE.md` or `DEVELOPMENT.md`. Role pages explain structure and verification.
- Every diagram has a caption, a plain-text summary, stable Mermaid syntax and a
  consistent palette.
- Markdown rules, the full ownership matrix and the Mermaid standards are in
  [`CONVENTIONS.md`](CONVENTIONS.md).

## Related pages

- [`CONVENTIONS.md`](CONVENTIONS.md) before editing a page or adding a diagram.
- [`IMPLEMENTATION.md`](../IMPLEMENTATION.md) for the build tracker.
