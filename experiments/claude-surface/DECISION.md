# ORGMD-8 — Deciding the Claude surface: MCP server vs skill + CLI

**Status:** decided (prototype-backed). **Date:** 2026-08-17.
**Scope:** how Claude should reach org-markdown data. Read-only v1; capture/refile
mutation is a later phase.

Both options were prototyped against the real `bin/org agenda --view <id>` CLI and
exercised end to end — see `EXERCISE.md`, `mcp/` and `skill/`. This note records the
recommendation.

## TL;DR recommendation

> **Ship the skill + CLI as v1 for local use. Keep the MCP server as the deliberate
> path for the planned remote "Remote MCP Server" epic — do not adopt MCP locally
> yet.**

The skill wins on everything that matters for a single-user, local, read-only v1:
zero setup, zero long-lived process, and a perfect fit with "the CLI is the
backend." MCP earns its keep only once org needs to be reached from *outside* the
machine (the homelab + tunnel epic) or by non-Claude-Code MCP clients — and that is
exactly where the epic already points it.

## Side-by-side

| Dimension | Skill + CLI | MCP server |
|---|---|---|
| **Setup / registration** | Drop a `SKILL.md` in `~/.claude/skills/`. No command, no restart, no daemon. | Register in client config (`claude mcp add` / desktop JSON), restart client. A process is spawned per session. |
| **Discoverability** | Skill `description` is matched by Claude Code automatically; also `/org-agenda`. Claude Code only. | Tools + JSON Schema advertised via `tools/list` to **any** MCP client (Desktop, Code, others). Better cross-client discovery. |
| **Auth / security** | Inherits the shell. `allowed-tools: Bash(org agenda*)` scopes it to one read-only command. Local FS trust only. | No auth in the local prototype (stdio inherits the user). Auth becomes a real design surface — and a real *requirement* — the moment it's remote. |
| **Streaming / large output** | CLI stdout straight into context (~5 KB for `tasks`). Model can post-filter, or we add CLI-side filter flags. No streaming, not needed at this size. | Same payload, wrapped in JSON-RPC `content`. MCP has no incremental streaming for a single tool result either; identical output-size story, more envelope. |
| **Maintenance burden** | One markdown file. The contract *is* the CLI; nothing to keep in sync. | A server process + JSON-RPC/protocol-version handling to maintain and test, on top of the CLI. Real code that can rot. |
| **Fit with "CLI is the backend"** | Ideal. The skill is literally "run `org`, read JSON." Zero backend logic duplicated. | Also good — it shells out to `org` too — but adds an adapter layer between Claude and the backend that the skill doesn't need. |
| **Read-only v1 fit** | Excellent. Exactly the shape of the ask. | Fine, but heavier than the ask. |
| **Future mutation (capture/refile)** | Add `org capture` / `org refile` subcommands + a few lines of skill instruction + a wider `allowed-tools`. Mutation guarded by the same Bash-permission prompt the user already sees. | Add tools with input schemas; per-tool description gives the model more structure, and schemas make destructive args explicit. Marginally nicer for mutation, but only after the CLI can mutate at all. |

## Why the skill, concretely

1. **Setup friction is the whole game for a personal tool.** The skill is a file you
   drop in a directory; it's discovered and used with no registration, no restart, no
   background process. The MCP path needs client config and a spawned server before
   it does anything. For one user on one machine, that overhead buys nothing.
2. **It is the thinnest possible expression of "CLI is the backend."** The skill adds
   *no* code — it points Claude at `org` and documents the JSON contract. The MCP
   server, by contrast, is ~250 lines that mostly re-encode a call the shell can make
   directly. Every line of that is maintenance the skill doesn't incur.
3. **Read-only v1 needs no protocol.** The value MCP adds — a typed tool surface any
   client can discover, and a natural place to hang auth — is precisely the value a
   local, single-client, read-only integration doesn't need yet. Paying for it now is
   premature.

Both were run against the real CLI and both work; this is an ergonomics/fit call, not
a "does it function" call.

## What would change the call (toward MCP)

- **Remote access / the homelab epic lands.** Once org must be reached over a
  Cloudflare tunnel from off-device, MCP (with proper auth) is the right surface and
  the skill's "shell out locally" model no longer applies. See below.
- **Non-Claude-Code clients matter.** If Claude Desktop or other MCP hosts become a
  target, the advertised tool schema is worth more than a Claude-Code-only skill.
- **Mutation grows complex/destructive.** If capture/refile arguments get rich enough
  that explicit JSON Schemas materially reduce model error, the typed tool surface
  starts to pay off. (Even then, do it once, on the remote server.)
- **Multiple tools proliferate.** A handful of related tools with schemas is tidier as
  an MCP server than as an ever-growing skill body.

## Relationship to the planned "Remote MCP Server" epic

The user's own direction (per project memory) already has a **"Remote MCP Server"
epic**: Walter homelab + Syncthing (replacing iCloud) + Cloudflare Tunnel, no-auth
**read-only v1**. That is the natural and intended home for MCP — a server reachable
off-device, speaking a standard protocol.

So the two surfaces are **not competitors; they're phased**:

- **Now (local):** skill + CLI. Cheapest path to "Claude can read my agenda on this
  laptop," no infrastructure.
- **Later (remote):** the MCP server, hosted behind the tunnel, is the cross-device
  surface. **This prototype is a direct down-payment on that epic** — it already
  shells out to `org` and returns the exact agenda JSON, so it can be lifted onto the
  homelab host largely as-is (add auth + real remote transport). Building it *locally
  now* would be redundant with the skill and premature relative to the epic; keeping
  it as the remote seed is the right sequencing.

Net: a local MCP prototype today would duplicate the skill without delivering the
remote value MCP exists to provide. Adopt the skill locally; grow the MCP server on
the homelab track.

## CLI limitations found (follow-ups for Claude-facing work)

These are notes, not changes (this ticket is additive):

1. **No machine-readable view list.** There's no `org views --json`; the MCP prototype
   hard-codes `tasks/calendar/inbox` and the skill lists them in prose. Add a
   discovery command so either surface can enumerate views dynamically.
2. **No output-shaping flags.** `agenda` returns the whole view. Server-side
   `--state`, `--tag`, `--since`, or `--limit` flags would cut context for large
   vaults and reduce reliance on the model to post-filter.
3. **Read-only only.** No `org capture` / `org refile` (or equivalent) exists, so
   neither surface can mutate. Mutation subcommands gate the "future mutation" row
   above for *both* surfaces.
4. **Errors are human strings on stderr.** Fine for a skill; a remote MCP server would
   benefit from structured error codes (exit code + machine-readable reason) so it can
   map cleanly onto JSON-RPC errors.
5. **`bin/org` needs `luajit` on PATH.** Worth documenting as a hard dependency for
   any host (local skill user or remote MCP box).
