# Documentation conventions

This page is for anyone editing the documentation. It defines where a fact
belongs, how a page is shaped, how diagrams are drawn, and what a reviewer
checks. The goal is simple: a reader should never have to guess which page is
authoritative.

> **Target state.** This page describes the system as it is meant to be. The
> remaining code work is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).
> When this page and the code disagree, this page is authoritative.

## One owner per fact

Every shared fact has exactly one canonical page. If the same fact appears on two
pages, one of them is a link.

| Topic | Canonical page | Everyone else |
|---|---|---|
| Product description, lanes, identities, trust boundaries | [`ARCHITECTURE.md`](ARCHITECTURE.md) | One-line summary and a link |
| Scope, rationale, trade-offs | [`DECISIONS.md`](DECISIONS.md) | Link to the ADR |
| Variables, precedence, playbook order, edge-mode values, network/volume/container inventories | [`ROLES.md`](ROLES.md) | Role pages keep only role-specific deltas |
| Role internals, files it writes, its verification | [`roles/<role>.md`](roles/) | Link from `ROLES.md` |
| Provisioning, day-2 operations, troubleshooting, decommissioning | [`RUNBOOK.md`](RUNBOOK.md) | Role pages link to the procedure |
| Restore drills and disaster recovery | [`RESTORE.md`](RESTORE.md) | `RUNBOOK.md` and role pages link to the procedure |
| Credentials, rotation, onboarding/offboarding, break-glass | [`SECRETS.md`](SECRETS.md) | Role pages link |
| WAF policy, acceptance suite, `403` triage, exceptions | [`WAF.md`](WAF.md) | Others link |
| Developer workflow and data rules | [`DEVELOPMENT.md`](DEVELOPMENT.md) | Others link |
| Vocabulary | [`GLOSSARY.md`](GLOSSARY.md) | No page redefines a term |
| Documentation and diagram rules | this page | — |
| Build status | [`IMPLEMENTATION.md`](../IMPLEMENTATION.md) | No page duplicates status |

## Page shape

Every page follows this order:

1. `H1` title.
2. One sentence that names the audience and the outcome.
3. Status banner, for pages that describe the target state.
4. Body.
5. `## Related pages` as the last section.

Top-level pages use this banner:

```markdown
> **Target state.** This page describes the system as it is meant to be. The
> remaining code work is tracked in [`IMPLEMENTATION.md`](../IMPLEMENTATION.md).
> When this page and the code disagree, this page is authoritative.
```

The implementation link is `IMPLEMENTATION.md` in the root `README.md`,
`../IMPLEMENTATION.md` in a page directly under `docs/`, and
`../../IMPLEMENTATION.md` in a role page.

Two pages are exceptions. `docs/README.md` is a hub and carries the same banner
with a `../` link. `DECISIONS.md` is a decision record and carries a
"decision record" note instead of the target-state banner.

### Role pages

Every role page uses this order:

```text
# `role` — one-line job
> **Target state.** ...
## What this role is for
## At a glance
## Inputs
## What the role creates and changes
## Security invariants
## Idempotency and change behaviour
## Verification
## Failure modes
## Implementation checklist
## Related pages
```

Optional sections are allowed, but `Failure modes` appears before any
`Changing ...` section, and `Implementation checklist` is the last section before
`Related pages`. The `At a glance` table must include role path, called-by,
runs-as, depends-on, used-by and main tags. "Runs as" uses one of these two
sentences:

- `A named admin, becoming deployowner through sudo with the admin's own password`
- a specific exception, such as the `base` bootstrap as `root` or the host
  firewall bouncer service as `root`

The role page must answer these questions without the reader opening another
page, except for the shared inventory in [`ROLES.md`](ROLES.md):

| Question | Required section |
|---|---|
| Why does this role exist? | What this role is for |
| What does it consume, and which values are required versus default? | Inputs |
| What role-specific files, containers, networks and volumes does it create, with what modes and owners? | What the role creates and changes |
| What must never become false? | Security invariants |
| What happens on a second run, and what triggers a restart? | Idempotency and change behaviour |
| How do I prove it worked? | Verification |
| What are the known failure modes and the first check? | Failure modes |
| What must the implementation satisfy? | Implementation checklist |

A role page names the shared networks, volumes and containers it uses, but does
not repeat the full global inventory. That inventory lives in
[`ROLES.md`](ROLES.md). The role page adds only the role-specific delta: mode,
owner, mount point, one-line purpose or verification command.

Add a short `## Implementation checklist` before `Related pages` with three to
eight testable statements. This is documentation, not code. It gives the
implementer a definition of done.

## Markdown rules

- One `H1` per page. Use sentence case for `H2` and `H3`. Never skip a heading
  level.
- Start with audience and outcome: "This page is for X; after reading it you can
  Y." Do not start with "Introduction".
- Use tables for reference matrices, bullets for rules, and numbered lists for
  procedures. Keep tables to five columns or fewer where possible.
- Fence every code block with a language. For host-level procedures, state
  **where it runs** in the surrounding text or a comment: control machine, host
  root shell, `deployowner` shell, or inside a container.
- Use `<angle-brackets>` for placeholders and `$UPPER_CASE` for environment
  variables. Do not prefix commands with `$`; it breaks copy-paste.
- Put UI paths in **bold** and file paths, commands, variables and identifiers in
  `` `backticks` ``.
- Use a fixed admonition label set. GitHub does not render custom admonitions, so
  use a blockquote with a bold lead-in:
  - `> **Target state.**`
  - `> **Important.**`
  - `> **Security.**`
  - `> **Rollout vs steady state.**`
  - `> **Note.**`
- Leave one blank line around headings, lists, tables and code fences.
- Use relative links with descriptive text. Do not paste bare URLs as the link
  text.
- End with `## Related pages`, at most eight links.
- Do not copy runtime or package versions into `docs/`. Point to the pin in
  `group_vars/` or the role defaults. `DECISIONS.md` is exempt because it
  records the reasoning, not the operational values.
- Do not use screenshots for topology or flow. Use Mermaid.

## Mermaid rules

- **One concept, one diagram.** Do not repeat a topology in two pages. If a page
  needs a reminder, use one sentence and a link to the diagram.
- **Choose by purpose:**
  - `flowchart` for topology, trust boundaries and decisions.
  - `sequenceDiagram` for time-ordered interactions.
  - `stateDiagram-v2` for rollout states, if a state machine is genuinely useful.
  - Do not use experimental diagram types or `architecture-beta`.
- **Stable syntax only.** Use `flowchart`, `sequenceDiagram` and
  `stateDiagram-v2`. Avoid HTML other than `<br/>`.
- **Caption every diagram** with a bold line above it:
  `**Figure 2 — Public request path.** The public router and the dashboard router are separate.`
- **Add a plain-text sentence** before or after the diagram that says what it
  proves. The page must still work if Mermaid does not render.
- **Subgraphs are trust boundaries**, not layout boxes. Label them (`Lane 1`,
  `Lane 2`, `erp-db`, `Host-level enforcement`).
- **Limit size:** keep diagrams readable; split one that grows beyond roughly 18
  nodes or three subgraph levels.
- **Direction:** `TB` for layered trust boundaries, `LR` for pipelines and
  topologies.
- **Node labels:** sentence case, at most four short lines, `<br/>` for breaks.
  No secrets, public IP addresses, versions or mutable values. Loopback
  addresses and fixed internal ports are allowed when they explain a path.
- **Edge labels:** lowercase verb phrases, for example `-->|renders|`.
- **No colour-only meaning.** Colour is decoration; the label carries the meaning.
- **No `click` directives.** Put links in the text after the diagram.
- **One palette per diagram.** New diagrams use the shared palette below. Do not
  mix themed classes with the default theme in the same figure.

```text
classDef human fill:#e8eef8,stroke:#3d5a80,color:#1e1e1e
classDef service fill:#f4f4f4,stroke:#787878,stroke-dasharray:4 3,color:#1e1e1e
classDef gate fill:#e2dbc8,stroke:#8e6a00,stroke-width:2px,color:#1e1e1e
classDef unpriv fill:#eef4ee,stroke:#4a7a4a,color:#1e1e1e
classDef blocked fill:#f8e8e8,stroke:#a33,color:#1e1e1e
```

Load the `mermaid` skill before adding or changing a diagram, and follow its
flowchart or sequence syntax reference. Validate the render on GitHub before
merging.

## Figure ownership

| Page | Diagram | Type |
|---|---|---|
| `README.md` (root) | Simplified two-lane flow | `flowchart LR` |
| `ARCHITECTURE.md` | Two privileged lanes | `flowchart TB` |
| `ARCHITECTURE.md` | Detection and enforcement | `flowchart TB` |
| `ROLES.md` | Build order, then runtime path as two separate figures | `flowchart` |
| `RUNBOOK.md` | Edge-mode decision | `flowchart TD` |
| `RUNBOOK.md` | Deploy sequence | `sequenceDiagram` |
| `WAF.md` | `403` decision flow | `flowchart TB` |
| `SECRETS.md` | Who can do what | `flowchart LR` |
| `roles/base.md` | Access model | `flowchart LR` |
| `roles/traefik.md` | Request path, dashboard, host enforcement | `flowchart TB` |
| `roles/crowdsec.md` | Detection chain | `flowchart TB` |
| `roles/crowdsec-firewall-bouncer.md` | How it works | `flowchart LR` |
| `roles/redis.md` | Topology | `flowchart LR` |
| `roles/erp.md` | Service map | `flowchart LR` |
| `roles/backup.md` | Backup flow | `flowchart LR` |
| `DEVELOPMENT.md` | Development loop | `flowchart LR` |

Do not add a second diagram for a concept that already has one. Link to the
section instead.

## Review checklist

Before merging a documentation change:

- [ ] Every relative link resolves and every `#anchor` matches a heading.
- [ ] The page has one `H1`, sentence-case headings, and no skipped levels.
- [ ] The page opens with audience and outcome, and ends with `Related pages`.
- [ ] Target-state pages carry the banner; `DECISIONS.md` carries the decision
      note.
- [ ] No banned synonyms: "deploy owner" (use `deployowner`), "target system",
      "accepted stack" or "finished system". Where both bouncers are in scope,
      name the Traefik bouncer or the host firewall bouncer.
- [ ] Every shared fact is on its canonical page; other pages link.
- [ ] No full procedure is duplicated between `RUNBOOK.md`, `RESTORE.md`,
      `SECRETS.md` and a role page; every command is written out in full, with
      development and production variants where they differ.
- [ ] Host-level code blocks say where they run, and procedures state the
      expected result.
- [ ] Every diagram has a caption, a plain-text summary, one consistent palette
      and a successful render.
- [ ] No runtime or package version is copied into `docs/`.
- [ ] Role pages pass the template and the spec-readiness questions above.

## Definition of ready for coding

Coding starts only when these are true:

- [ ] Root `README.md` is the landing page and links to the docs and the tracker.
- [ ] Every target-state page carries the same banner; `DECISIONS.md` carries the
      decision note instead.
- [ ] `docs/README.md` has one reading path per audience.
- [ ] `RUNBOOK.md` takes a newcomer from a fresh host to a serving development
      site without external knowledge, and shows the production commands
      alongside the development ones.
- [ ] `GLOSSARY.md` covers the deployment vocabulary used across the docs.
- [ ] Each shared fact has one canonical page.
- [ ] Every deploy example uses a `sha256:` digest.
- [ ] Development and production smoke behaviour is stated identically in
      `ARCHITECTURE.md`, `RUNBOOK.md`, `roles/erp.md` and ADR-005.
- [ ] `ci-deploy` ordering is consistent across `RUNBOOK.md`, `roles/base.md`,
      `ARCHITECTURE.md` and `IMPLEMENTATION.md`.
- [ ] The SSH port and the bootstrap connection are unambiguous.
- [ ] Every role page passes the spec-readiness questions and has an
      implementation checklist.
- [ ] No page contains a runtime or package version.

## Related pages

- [`README.md`](README.md) for the documentation map.
- [`GLOSSARY.md`](GLOSSARY.md) for the vocabulary.
- [`ROLES.md`](ROLES.md) for the role template in context.
