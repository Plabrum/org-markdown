# MCP prototype — `org` as an MCP server

`org_mcp_server.py` is a **minimal, dependency-free** MCP server (stdio transport,
newline-delimited JSON-RPC 2.0) that wraps the standalone `bin/org` CLI. It is an
**evaluation artifact** for ORGMD-8 — it is not wired into the plugin and is not
meant to ship as-is.

## Tools exposed

| Tool         | Args              | Returns                                              |
|--------------|-------------------|-----------------------------------------------------|
| `list_views` | —                 | `{"views": ["tasks","calendar","inbox"]}`           |
| `agenda`     | `view` (string)   | The CLI's agenda JSON verbatim (groups → items).    |

Each tool shells out to `bin/org` and returns its stdout as MCP text content. On a
non-zero exit the server returns the CLI's stderr as an error string (see the
`view=nope` case in the smoke test) rather than crashing the connection.

## Smoke test (no client needed)

```bash
python3 experiments/claude-surface/mcp/org_mcp_server.py --self-test
# initialize -> {...serverInfo...}
# tools/list -> ['list_views', 'agenda']
# tools/call agenda(view=tasks) -> title='Tasks' groups=7
```

Drive the real stdio protocol by hand:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"agenda","arguments":{"view":"tasks"}}}' \
  | python3 experiments/claude-surface/mcp/org_mcp_server.py
```

## Registering it with a client

**Claude Code** (project- or user-scoped `.mcp.json` / `claude mcp add`):

```bash
claude mcp add org -- python3 /ABS/PATH/org-markdown/experiments/claude-surface/mcp/org_mcp_server.py
```

**Claude Desktop** (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "org": {
      "command": "python3",
      "args": ["/ABS/PATH/org-markdown/experiments/claude-surface/mcp/org_mcp_server.py"]
    }
  }
}
```

The server resolves `bin/org` relative to its own location (`../../../bin/org`), so
no extra config is needed as long as the repo layout is intact. `luajit` must be on
`PATH` for the CLI itself to run.

## Notes / limitations surfaced

- The CLI has no machine-readable "list views" command, so `list_views` hard-codes
  the three known ids. A real server would want `org views --json`. (Follow-up.)
- Everything here is read-only. Mutation (capture/refile) would need new `org`
  subcommands before it could be exposed as MCP tools.
