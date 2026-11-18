# Server hardening: controls, impact, and remote access

This page explains what the current Ansible configuration does, why it is
there, and what it could affect operationally. It describes the checked-in
implementation, not a promise that every provider or network behaves the same.
For incident procedures and the full trust model, see
[`RUNBOOK.md`](RUNBOOK.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Summary

The host is configured to accept inbound SSH on its configured SSH port and
web traffic on ports 80 and 443. Other inbound traffic is denied. SSH access is
limited to named accounts and public keys. The application edge is Traefik;
the database and Redis services are not published directly to the host.

The controls most likely to affect remote administration are:

1. The SSH port and `AllowUsers` list must match the account and port you
   actually use.
2. UFW is reset to the managed allowlist, so a separate guest service such as
   direct VNC is not reachable unless deliberately added.
3. IPv6 router advertisements are disabled. This can affect IPv6 if the
   provider relies on router advertisements to configure the server.
4. Strict reverse-path filtering may affect asymmetric or policy-routed
   networks.

The provider's web/virtual console is normally an out-of-band management path:
the host's SSH daemon, UFW and guest network settings do not normally filter
it. Keep it available as a recovery path, but verify this with the provider.

## Controls and their impact

| Area | Current control | Benefit | Operational impact or limitation |
|---|---|---|---|
| Accounts | Each operator has a named account, own SSH keys and passworded sudo. Operators removed from the vault roster are removed on the next run. | Actions are attributable and access can be revoked per person. | Operators are still root-equivalent because they have full sudo. |
| Service identity | `deployowner` has a locked password and is excluded from SSH `AllowUsers`. It owns the stack and is the only account granted Docker socket access. | Separates application file ownership and routine stack work from human SSH identities. | Docker access is effectively root. Anyone who compromises `deployowner` or its Docker access can take over the host. |
| Pipeline identity | When registered with a real key, `ci-deploy` can run only the root-owned `erp-deploy` and `erp-smoke` commands through sudo. It has no supplementary groups. | Limits CI's host capabilities compared with a general admin account. | The deployment scripts are privileged interfaces and must remain root-owned and reviewed. |
| SSH authentication | Root, password and keyboard-interactive SSH authentication are disabled. Public keys are enabled, and `AllowUsers` lists the configured operators plus CI when registered. | Blocks password guessing and prevents unlisted accounts from using SSH. | A missing key, wrong username, or incorrect SSH port can prevent a new login. Keep an existing session open while testing another login. |
| SSH features and crypto | Agent/X11 forwarding and tunnel interfaces are disabled; TCP forwarding is restricted to `local`. SSH algorithms are explicitly limited to modern choices, and authentication/session attempts are bounded. | Reduces forwarding and older-crypto attack surface and limits brute-force sessions. | Local TCP forwarding remains permitted; it can support an SSH local-port tunnel to a guest VNC service. Remote/dynamic forwarding, X11 forwarding, and tun/tap tunnels are restricted. Older SSH clients may not support the configured algorithms. |
| SSH change safety | Each file change is checked with `sshd -t`; the handler validates again and reloads sshd rather than restarting it. Keys are installed before password login is disabled. | Prevents syntactically invalid configuration from being activated and avoids intentionally dropping the active SSH session on reload. | A syntactically valid but incorrect user or port policy can still block subsequent logins. These checks reduce, but do not eliminate, lockout risk. |
| UFW | IPv4 and IPv6 filtering are enabled; inbound defaults to deny, outbound to allow. The role resets UFW and permits only the configured SSH port and TCP 80/443. SSH is rate-limited. | Keeps the public host surface small and reduces repeated SSH attempts. | Existing manual UFW rules are removed. A stale or wrong SSH port setting can block new SSH sessions. Outbound traffic is not restricted. |
| Docker firewall | A `DOCKER-USER` chain drops Docker-forwarded traffic outside the same SSH/web port allowlist, and a systemd drop-in reapplies it after Docker starts. | Prevents Docker's port publishing from bypassing the intended inbound allowlist. | An intentionally published extra container port will not be externally reachable through this policy without changing the allowlist. |
| Network sysctls | Reverse-path filtering is enabled; redirects and source routing are disabled; SYN cookies are enabled; suspicious packet logging is enabled. | Hardens common network-stack behaviors and makes some spoofing/routing attacks harder. | Strict reverse-path filtering can interfere with asymmetric routes, VPNs, multiple interfaces, or custom policy routing. Test such setups explicitly. |
| IPv6 sysctls | IPv6 redirects and router advertisements are disabled. | Prevents the host from accepting redirect/route configuration from the network. | If the provider relies on SLAAC/router advertisements to assign an IPv6 address or default route, IPv6 connectivity may fail. Static/provider-managed IPv6 can continue to work. |
| Kernel sysctls | ASLR is maximized; kernel pointers and dmesg are restricted; ptrace and unprivileged BPF are restricted; protected links and non-dumpable setuid behavior are enabled. | Reduces information disclosure and common local privilege-escalation opportunities. | These settings can affect specialized diagnostics, tracing, or software that expects unprivileged BPF/ptrace; ordinary SSH and desktop traffic should not be affected. |
| IP forwarding | IPv4 forwarding is set to `0` in the base sysctl file. | Avoids making the host a general IPv4 router by default. | Docker bridge networking may enable forwarding for container connectivity. Check the effective value after Docker is running; this setting does not normally block traffic addressed to the server itself. |
| Updates and reboot | Unattended upgrades are enabled for configured Ubuntu security and update origins; unattended reboot and automatic removal of unused packages are disabled. | Applies package updates without an unattended host reboot or package cleanup. | Updates can still restart individual services. A person must arrange a reboot when needed. |
| Logging and time | Journald persists logs, caps storage/retention, compresses and forwards to syslog. Chrony synchronizes time. | Limits disk exhaustion from log growth and supports reliable audit/security event timestamps. | Logs older than the configured retention can be removed; a full root filesystem can still result from other data. |
| Default file permissions | A restrictive umask is configured; `/etc/shadow` and `/etc/gshadow` are root-owned and mode `0640`. | Reduces accidental disclosure of newly created files and password databases. | Applications that rely on world-readable files may need explicit permissions. |
| Swap | A root-owned, mode-`0600` swap file is enabled and persisted across boots. | Provides an OOM safety buffer for memory pressure. | Uses disk and is slower than RAM; it is not a substitute for adequate memory. The role intentionally refuses to resize an existing swap file automatically. |
| Docker daemon | Docker uses `no-new-privileges`, bounded/rotated logs, live restore and a configured data root/address pool. | Reduces setuid escalation in containers, controls log growth, and avoids stopping containers for some daemon restarts. | User-namespace remapping is not enabled because it would require storage ownership migration. Live restore does not remove all maintenance downtime. |
| Edge and workloads | Traefik is unprivileged, read-only, capability-restricted and resource-bounded. Its socket proxy filters Docker API access. MariaDB is on an internal network, uses encryption settings and a mounted root-password secret; DB/Redis have no host-published ports. | Limits edge container privileges, protects the Docker socket, and narrows direct access to data services. | This hardening is not uniform: the Frappe and Redis compose services do not currently define the same read-only filesystem, dropped capabilities, explicit non-root user, or resource limits. |
| CrowdSec | CrowdSec reads Traefik, SSH and AppSec events. The host nftables bouncer polls decisions and drops banned IPv4/IPv6 sources; the LAPI is loopback-only. | Adds adaptive source-address blocking for SSH and forwarded traffic as well as static UFW rules. | If LAPI is unavailable, the host bouncer cannot obtain new decisions; UFW remains. Behind a Cloudflare proxy, the host sees Cloudflare's address rather than the visitor's real address. |
| HTTP WAF | The Traefik bouncer uses CrowdSec IP decisions and AppSec. It fails closed: unavailable/erroring AppSec blocks requests. HTTP redirects to HTTPS; TLS is at least 1.2; the dashboard has an IP allowlist and authentication. | Rejects known bad request shapes and banned IPs before they reach the application. | An AppSec outage can make the website unavailable with `403` responses. This does not normally affect SSH or provider-console VNC. |
| Playbook guardrails | Playbooks require one explicit target environment and refuse execution in CI. The server playbook reports effective SSH/firewall state and checks Docker group membership for the login user. | Prevents common wrong-environment runs and catches selected access-policy drift. | These checks do not replace a tested recovery path or protect against changes made outside Ansible. |

Implementation references: [`roles/base`](../roles/base/),
[`roles/docker`](../roles/docker/), [`roles/traefik`](../roles/traefik/),
[`roles/crowdsec`](../roles/crowdsec/), and
[`playbooks/server.yml`](../playbooks/server.yml).

## VNC and other remote desktop access

### Provider console / web VNC

The provider's console is normally connected through the hosting provider's
management plane, not to a VNC port on the guest. In that common arrangement:

- guest UFW does not block the provider console;
- SSH authentication changes do not disable it;
- guest IPv6 or routing changes do not normally disable the console;
- it can be used to inspect or repair the guest if SSH is unavailable.

Provider implementations differ. Confirm that the console is enabled and that
you know how to reach it before applying SSH/firewall changes. Do not rely on
it as a substitute for testing the configured SSH access.

### VNC server running inside the guest

The managed inbound allowlist does **not** include a VNC port such as TCP 5900.
A VNC server on the guest therefore will not be directly reachable from outside
after UFW is enabled (and Docker-published VNC is also constrained by
`DOCKER-USER`). If needed, prefer binding VNC to loopback and connecting through
an SSH local-port forward; `AllowTcpForwarding local` permits local forwarding.
Do not expose a VNC port publicly just to work around an SSH issue.

## Before and after applying `server.yml`

### Before

1. Confirm provider-console access works and keep its session available.
2. Confirm the SSH port used by the server matches `SSH_PORT` / `ansible_port`.
3. Confirm the SSH login username is in the environment's operator roster and
   that its public key is installed and usable.
4. If IPv6 matters, record `ip -6 addr` and `ip -6 route` and confirm whether
   the provider uses router advertisements.
5. If the host is multi-homed, uses a VPN, or routes traffic for another
   network, review the reverse-path-filtering and forwarding settings first.
6. Follow the documented bootstrap procedure for a first run; it is distinct
   from subsequent key-only admin runs. See [`playbooks/server.yml`](../playbooks/server.yml).

### After

1. Keep the original SSH session open and make a separate new SSH connection
   with the expected user, key, host and port.
2. Check `sudo /usr/sbin/sshd -t`, `sudo /usr/sbin/sshd -T`, and
   `sudo ufw status verbose`. Verify the intended account is in `AllowUsers`
   and the SSH port is allowed.
3. If applicable, re-check `ip -6 addr`, `ip -6 route`, VPN/routing, and
   container connectivity after Docker starts.
4. Confirm the provider console is still available before ending the
   maintenance window.

If a new SSH connection fails, use the provider console to inspect sshd
configuration and UFW rather than disabling the firewall remotely without a
recovery path.

## Environment-dependent CrowdSec activation

The base host controls are shared across environments. The HTTP CrowdSec
bouncer is environment-dependent: development currently sets
`traefik_crowdsec_enabled: true`, while production currently sets it to
`false` as a rollout gate. The host firewall bouncer is installed by the
CrowdSec role separately. Check the current environment variables before
assuming the web WAF is active. See
[`group_vars/development/main.yml`](../group_vars/development/main.yml),
[`group_vars/production/main.yml`](../group_vars/production/main.yml), and
[`WAF.md`](WAF.md).
