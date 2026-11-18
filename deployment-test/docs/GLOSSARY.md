# Glossary

The vocabulary used across the documentation. Entries define the term as it is
used **here**, not every possible meaning. Where a term has a canonical page, the
entry links to it.

> **Target state.** This page describes the system as it is meant to be. The
> remaining code work is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).
> When this page and the code disagree, this page is authoritative.

## Terms

| Term | Meaning |
|---|---|
| Acquisition | A CrowdSec configuration file that tells the engine which log or listener to read. This stack has one acquisition for the Traefik access log, one for host SSH authentication, and one for the AppSec listener. |
| Admin | A named person with a Linux account on a host, their own SSH key, their own sudo password, and their own dashboard login. Admins are root-equivalent by design. See [`ARCHITECTURE.md`](ARCHITECTURE.md#users-and-identities). |
| ADR | Architecture Decision Record. A record of a choice, its context, and what was traded away. ADRs explain the target state; the operational pages carry the instructions. See [`DECISIONS.md`](DECISIONS.md). |
| AOF | Redis append-only file persistence. It is **not** enabled here. The queue uses RDB snapshots, so a crash can lose jobs accepted since the last snapshot. |
| AppSec | CrowdSec's web application firewall component. It inspects request method, path, headers and body shape, then returns allow or block. It is in-band and fail-closed in this stack. See [`WAF.md`](WAF.md). |
| Bench | The Frappe command-line tool and process manager. In containers it runs commands such as `bench serve`, `bench worker`, `bench schedule` and `bench new-site`. |
| Bouncer | A component that fetches CrowdSec decisions and enforces them. This stack has two: the **Traefik bouncer** for HTTP and the **host firewall bouncer** for nftables. They use separate keys and have different failure models. |
| Break-glass | An emergency path used only when normal access is unavailable. On the host it is the provider console as `root`. In Frappe it is the built-in `Administrator` account. Neither is a daily shared login. |
| CAPI | CrowdSec's Central API. It supplies the community blocklist and console integration. CAPI updates are automatic and are separate from hub updates. |
| `ci-deploy` | The pipeline's Linux account. It logs in with one SSH key and may run only `erp-deploy` and `erp-smoke` as root. It has no other groups, no vault password, and no sudo password. |
| Cloudflare DNS, no proxy | An edge mode where Cloudflare answers DNS (grey cloud) but traffic goes straight to Traefik. The certificate uses DNS-01. There is no router allowlist. |
| Cloudflare proxy mode | An edge mode where Cloudflare sits in front of Traefik (orange cloud). The public app router accepts Cloudflare and the private network, and rejects direct public traffic. |
| Container | An isolated process with its own files and libraries. Traefik, CrowdSec, MariaDB, Redis and the Frappe services all run as containers. |
| Control machine | An admin's own machine. It runs Ansible and holds the vault password and that admin's SSH key. It is not a shared server. |
| CRS | OWASP Core Rule Set, used by CrowdSec AppSec. It is rolled out out-of-band first and moved in-band only after a separate review. |
| CrowdSec | The detection engine and Local API (LAPI). It reads logs, produces decisions, runs AppSec, and feeds both bouncers. See [`roles/crowdsec.md`](roles/crowdsec.md). |
| Decision | A CrowdSec record that says an address should be banned for a period of time. Decisions are enforced by the bouncers; they are not the same as an AppSec rule match. |
| `deployowner` | A locked service identity that owns the stack directories and `.env` files. It is the only account in the `docker` group. Admins reach it with `sudo -u deployowner`, using their own password. Always write the account name as one word. |
| Desk | The Frappe web interface used for application configuration and data. A Desk user is an application user, not a Linux account. |
| Designated reviewer | The person listed as the required reviewer on the `production` GitHub Environment. They approve production runs they did not trigger. Self-review is disabled, so they cannot approve their own run. |
| Developer | A person who writes application code and uses the development Desk, but has no Linux account on a shared host. Developers are outside both privileged lanes. See [`DEVELOPMENT.md`](DEVELOPMENT.md). |
| erp | The Frappe/ERP application deployed by this repository. It runs as the `erp` Ansible role and the `erp` Compose project. |
| Digest | The immutable `sha256:` identity of an image. Two different images cannot share a digest. The pipeline promotes a digest, not a tag. |
| Direct mode | The simplest edge mode: no proxy, clients connect straight to Traefik, and the certificate uses HTTP-01. Port 80 must be reachable. |
| Edge | The public front door: Traefik and, optionally, Cloudflare. It terminates TLS and applies routing and security middleware. |
| Entrypoint | The Traefik listener on port 80 or 443. It handles TLS and trusted proxy headers. It does not block. |
| ERP | Enterprise resource planning. The business application built on Frappe and deployed here as the ERP stack. |
| Fail-closed | If the security component is unavailable or errors, the request is blocked. The Traefik bouncer is fail-closed when AppSec or its decision stream is unavailable. |
| Fail-open | If the component is unavailable, traffic continues. The host firewall bouncer is fail-open for new decisions because a layer-3 firewall cannot default-deny the whole host without an outage. |
| Frappe | The web framework and Desk application that runs the ERP. It provides the site, the database schema, background jobs, real-time updates and the REST API. |
| GitHub Environment | A GitHub Actions deployment target with its own secrets, variables and protection rules. This repository uses `development` and `production`; `production` requires one designated reviewer and prevents self-review. |
| Host firewall bouncer | The `crowdsec-firewall-bouncer-nftables` systemd service. It drops banned addresses in its own nftables tables, covering SSH and forwarded container traffic. It is separate from UFW and from the Traefik bouncer. |
| Hub | CrowdSec's catalogue of parsers, scenarios, collections and AppSec rules. Hub content is updated separately from the engine image. |
| Idempotent | Safe to run again: a second run converges to the same state instead of duplicating or undoing work. Every Ansible role here is expected to be idempotent. |
| Inventory | The file that lists the servers and their environment groups. This repository keeps both environments in one file and guards against running without exactly one in scope. |
| LAPI | CrowdSec's Local API. Traefik, AppSec and the host firewall bouncer read decisions from it. It listens on host loopback `127.0.0.1:8080` and on `crowdsec-net` inside Docker. |
| Lane 1 | Infrastructure work by named admins from their own control machines. It can change anything on the host. |
| Lane 2 | Application deployment by GitHub Actions. It can change one image digest and nothing else. |
| Middleware | A Traefik step that runs before a request reaches the application, such as the bouncer, an allowlist, a rate limit or a security header. |
| Playbook | An ordered Ansible file that applies roles to a host. The guard requires exactly one environment in scope. |
| RDB | Redis database snapshot persistence. The queue uses RDB; the cache is ephemeral and has no volume. |
| Requester | The person who dispatches a deployment workflow. On `production`, the requester cannot be the approver. |
| Role | A reusable Ansible folder of tasks, templates and defaults. Each role owns one part of the server. See [`ROLES.md`](ROLES.md). |
| Router | The Traefik rule that matches a host and attaches middlewares. This is where access is allowed or denied. |
| Router allowlist | A middleware that rejects requests from addresses outside a list. The public app uses `cloudflare-allow` in Cloudflare proxy mode; the dashboard has its own private-only allowlist in every mode. |
| Site | One Frappe installation with its own database and site directory. This stack runs one site per environment. |
| Smoke check | Two related but different checks. `erp-smoke` is the CI health check (containers, edge, certificate, bouncer, AppSec). `playbooks/smoke.yml` is the full control-machine check, including LAPI, acquisition and a test decision. See [`DECISIONS.md`](DECISIONS.md#adr-005--ci-smoke-is-a-health-check-the-full-chain-check-stays-on-an-admins-control-machine). |
| SNI | Server Name Indication. The TLS client sends the hostname it wants, and Traefik selects the matching certificate. Strict SNI is part of the TLS policy. |
| Socket proxy | The filtered Docker API proxy that Traefik uses instead of mounting the Docker socket. It allows only the read-only calls Traefik needs. |
| SSH tunnel | A private path to the dashboard through an SSH connection. The dashboard is never exposed publicly. |
| Staging CA | The Let's Encrypt staging certificate authority. Development uses it by design, so its certificate is not publicly trusted. It is not a staging environment; there is no staging environment. |
| Stream mode | The Traefik bouncer caches the decision list and refreshes it on an interval instead of asking LAPI on every request. |
| Target state | The system as described by the documentation, which the code is being brought into line with. `IMPLEMENTATION.md` records the remaining gap. |
| `targetpw` | A sudoers option that asks for the **target** user's password instead of the invoking user's password. It is deliberately not used here; sudo asks for the admin's own password. |
| Telegram notification | CrowdSec's HTTP notification plugin sending alerts to the Telegram Bot API. There is no dedicated Telegram plugin. |
| Traefik bouncer | The CrowdSec plugin in Traefik. It enforces HTTP IP decisions and forwards requests to AppSec. It uses the Traefik/AppSec LAPI key and is fail-closed. |
| Trusted proxy | An address whose `X-Forwarded-For` header Traefik believes. This is not an allowlist. |
| Vault | An encrypted file that holds the environment's secrets and, in `vault_base_operators`, the admin account names and public keys. It is opened with a separate vault password held by admins. Production and development use different vaults and different vault ids. |
| Virtual patching | A WAF rule that blocks exploitation of a known vulnerability without changing the application code. It is the first in-band AppSec rule set here. |
| WAF | Web application firewall. In this stack it means CrowdSec AppSec plus the Traefik bouncer settings that enforce it. |
| yescrypt | The password hashing scheme used for admin Linux password hashes in the vault. The plaintext password is never stored. |

## Related pages

- [`README.md`](README.md) for the documentation map and reading paths.
- [`CONVENTIONS.md`](CONVENTIONS.md) for the terminology rules.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) for the model behind these terms.
