# Exercising both prototypes against the real CLI

Both grips were run against the working `./bin/org agenda --view tasks` on this
machine (luajit 2.1, macOS). This file captures what each path actually looks like
end to end, so the comparison in `DECISION.md` is grounded rather than hypothetical.

## Common backend call

```
$ ./bin/org agenda --view tasks
{"groups":[{"items":[{"all_day":false,"children":[],"depth":0,
"file":"/Users/phil/org/archive/arive-linear.md","line":9,"source":"Arive",
"state":"TODO","tags":["ARI","roster-member-flow"],
"title":"Build social data pipeline"}, ... ],"key":"Arive"}, ...],
"title":"Tasks","view_id":"tasks"}
```

~5.2 KB of JSON, 7 groups. Unknown view / missing flag → exit 1 with a message on
stderr (`org agenda: unknown view 'nope'`).

## Path A — MCP server

`experiments/claude-surface/mcp/org_mcp_server.py` (stdio JSON-RPC, no deps).

Self-test:

```
$ python3 experiments/claude-surface/mcp/org_mcp_server.py --self-test
initialize -> {"protocolVersion": "2024-11-05", ... "serverInfo": {"name": "org-markdown", "version": "0.1.0"}}
tools/list -> ['list_views', 'agenda']
tools/call agenda(view=tasks) -> title='Tasks' groups=7
```

Real stdio session (client → server → client), summarized:

```
id 1 initialize: {'name': 'org-markdown', 'version': '0.1.0'}
id 2 tools: ['list_views', 'agenda']
id 3 content[:80]: {"groups":[{"items":[{"all_day":false,"children":[],"depth":0,"file":"/Users/phi
id 4 content[:80]: org agenda failed: org agenda: unknown view 'nope'
```

End to end: client spawns the server → `initialize` handshake → `tools/list`
advertises `agenda`/`list_views` with JSON Schema → model calls `tools/call` →
server runs `bin/org agenda --view tasks` → CLI JSON returned as text content. The
bad-view case returns the CLI's stderr as an error string without dropping the
connection.

User setup: register once (`claude mcp add org -- python3 .../org_mcp_server.py`,
or a `claude_desktop_config.json` block), restart the client. See `mcp/README.md`.

## Path B — skill + CLI

`experiments/claude-surface/skill/SKILL.md` (frontmatter + instructions; `allowed-tools`
pre-authorizes `Bash(org agenda*)`).

The skill tells Claude to run the command and interpret the JSON. Running the exact
command the skill prescribes and applying its "walk groups → items → children, count
open items" instruction against real data:

```
$ ./bin/org agenda --view tasks | python3 interpret.py
View: 'Tasks'  (7 groups)
  - Arive: 7 open  [IN_PROGRESS: ["Add 'Invite Roster Member' action"]]
  - Arive (deprecated): 4 open  [IN_PROGRESS: ['Chat']]
  - Development config: 1 open
  - Org Markdown Project: 4 open
  - Refile: 1 open  [IN_PROGRESS: ['Add escalation actions']]
  - Trackstar Game: 0 open
  - nfl-predict__main: 2 open
```

(`interpret.py` stands in for the reasoning the model does inline — it is not a
shipped file.) End to end: user asks "what's on my plate" → skill matches → Claude
runs `org agenda --view tasks` via Bash → reads the JSON off stdout → answers in
prose. No process to keep alive, no handshake.

User setup: drop `SKILL.md` under `~/.claude/skills/org-agenda/` (or a plugin/
project `.claude/skills/`). No registration command, no restart.
