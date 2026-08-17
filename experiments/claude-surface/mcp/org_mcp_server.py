#!/usr/bin/env python3
"""Minimal MCP server wrapping the org-markdown CLI (ORGMD-8 prototype).

Evaluation artifact only -- NOT wired into the plugin runtime. It exposes the
standalone `bin/org` CLI as MCP tools over the stdio transport so a Claude client
(Claude Desktop, Claude Code, etc.) can call them.

Design notes:
- Zero third-party dependencies. The MCP stdio transport is newline-delimited
  JSON-RPC 2.0, which the standard library can speak directly, so this file runs
  under any stock `python3` without `pip install mcp`. That keeps the prototype
  honest about the *shape* of an MCP integration without dragging in an SDK.
- All real work is delegated to `bin/org`; this process is a thin adapter that
  turns a `tools/call` into a subprocess invocation and returns the CLI's JSON.

Tools exposed:
- `list_views`  -> the agenda view ids this CLI knows about.
- `agenda`      -> run `org agenda --view <view>` and return its JSON payload.

Run it by hand for a smoke test:
    python3 org_mcp_server.py --self-test
"""

from __future__ import annotations

import json
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Final, TypedDict, cast


def loads_obj(text: str) -> dict[str, object]:
    """Parse JSON expected to be an object.

    `json.loads` returns `Any`; this is the one trust boundary where we assert
    the decoded shape is a string-keyed map, so the rest of the module stays
    strictly typed instead of propagating `Any`.
    """
    return cast("dict[str, object]", json.loads(text))

# --- CLI location -----------------------------------------------------------
# This file lives at <repo>/experiments/claude-surface/mcp/org_mcp_server.py, so the
# repo root is three parents up and the CLI is <root>/bin/org.
REPO_ROOT: Final[Path] = Path(__file__).resolve().parents[3]
ORG_BIN: Final[Path] = REPO_ROOT / "bin" / "org"

PROTOCOL_VERSION: Final[str] = "2024-11-05"
SERVER_NAME: Final[str] = "org-markdown"
SERVER_VERSION: Final[str] = "0.1.0"

# Views the CLI ships today. The CLI has no `org views` command yet (see
# DECISION.md follow-ups), so we hard-code the known ids for `list_views`.
KNOWN_VIEWS: Final[tuple[str, ...]] = ("tasks", "calendar", "inbox")


class JsonRpcError(Exception):
    """A JSON-RPC error to be reported back to the client."""

    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code: int = code
        self.message: str = message


class CliResult(TypedDict):
    """Outcome of shelling out to `bin/org`."""

    ok: bool
    stdout: str
    stderr: str
    code: int


def run_org(args: list[str]) -> CliResult:
    """Invoke `bin/org` with the given args and capture its output."""
    proc: subprocess.CompletedProcess[str] = subprocess.run(
        [str(ORG_BIN), *args],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
        check=False,
    )
    return CliResult(
        ok=proc.returncode == 0,
        stdout=proc.stdout,
        stderr=proc.stderr,
        code=proc.returncode,
    )


# --- Tool implementations ---------------------------------------------------
# Each tool returns the MCP `content` list. On CLI failure we surface stderr as
# text content rather than raising, so the model sees a usable error string.


def tool_list_views(_arguments: dict[str, object]) -> list[dict[str, object]]:
    """Return the agenda view ids the CLI understands."""
    return [{"type": "text", "text": json.dumps({"views": list(KNOWN_VIEWS)})}]


def tool_agenda(arguments: dict[str, object]) -> list[dict[str, object]]:
    """Run `org agenda --view <view>` and hand back its JSON verbatim."""
    view: object = arguments.get("view")
    if not isinstance(view, str) or view == "":
        raise JsonRpcError(-32602, "agenda: 'view' (string) is required")

    result: CliResult = run_org(["agenda", "--view", view])
    if not result["ok"]:
        detail: str = result["stderr"].strip() or f"org exited {result['code']}"
        return [{"type": "text", "text": f"org agenda failed: {detail}"}]

    # stdout is already the CLI's JSON; pass it through untouched so the schema
    # the client sees is exactly the CLI's contract.
    return [{"type": "text", "text": result["stdout"].strip()}]


ToolHandler = Callable[[dict[str, object]], list[dict[str, object]]]

TOOLS: Final[dict[str, ToolHandler]] = {
    "list_views": tool_list_views,
    "agenda": tool_agenda,
}

TOOL_SCHEMAS: Final[list[dict[str, object]]] = [
    {
        "name": "list_views",
        "description": "List the org-markdown agenda view ids available to query.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "agenda",
        "description": (
            "Return an org-markdown agenda view as structured JSON. "
            "Groups of task/calendar items with title, state, priority, date, tags, file, line."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "view": {
                    "type": "string",
                    "description": "Agenda view id, e.g. 'tasks', 'calendar', or 'inbox'.",
                    "enum": list(KNOWN_VIEWS),
                }
            },
            "required": ["view"],
            "additionalProperties": False,
        },
    },
]


# --- JSON-RPC / MCP dispatch ------------------------------------------------


def handle_request(method: str, params: dict[str, object]) -> dict[str, object]:
    """Route an MCP request method to its result payload."""
    if method == "initialize":
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        }

    if method == "tools/list":
        return {"tools": TOOL_SCHEMAS}

    if method == "tools/call":
        name: object = params.get("name")
        arguments: object = params.get("arguments", {})
        if not isinstance(name, str) or name not in TOOLS:
            raise JsonRpcError(-32601, f"unknown tool: {name!r}")
        if not isinstance(arguments, dict):
            raise JsonRpcError(-32602, "arguments must be an object")
        content: list[dict[str, object]] = TOOLS[name](cast("dict[str, object]", arguments))
        return {"content": content, "isError": False}

    raise JsonRpcError(-32601, f"unknown method: {method}")


def serve() -> None:
    """Read newline-delimited JSON-RPC from stdin, write responses to stdout."""
    for raw in sys.stdin:
        line: str = raw.strip()
        if line == "":
            continue

        message: dict[str, object] = loads_obj(line)
        msg_id: object = message.get("id")
        method: object = message.get("method")
        params_obj: object = message.get("params", {})
        params: dict[str, object] = (
            cast("dict[str, object]", params_obj) if isinstance(params_obj, dict) else {}
        )

        # Notifications (no id, e.g. notifications/initialized) get no response.
        if msg_id is None:
            continue
        if not isinstance(method, str):
            continue

        try:
            result: dict[str, object] = handle_request(method, params)
            response: dict[str, object] = {"jsonrpc": "2.0", "id": msg_id, "result": result}
        except JsonRpcError as err:
            response = {
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {"code": err.code, "message": err.message},
            }

        _ = sys.stdout.write(json.dumps(response) + "\n")
        _ = sys.stdout.flush()


def self_test() -> int:
    """Drive the dispatch layer without a client, for a grounded smoke test."""
    init: dict[str, object] = handle_request("initialize", {})
    print("initialize ->", json.dumps(init))

    names: list[str] = [str(schema["name"]) for schema in TOOL_SCHEMAS]
    print("tools/list ->", names)

    call: dict[str, object] = handle_request(
        "tools/call", {"name": "agenda", "arguments": {"view": "tasks"}}
    )
    # We built `content` ourselves in handle_request, so its shape is known.
    content: list[dict[str, object]] = cast("list[dict[str, object]]", call["content"])
    text: object = content[0]["text"]
    payload: dict[str, object] = loads_obj(text) if isinstance(text, str) else {}
    groups_obj: object = payload.get("groups", [])
    groups: list[object] = cast("list[object]", groups_obj) if isinstance(groups_obj, list) else []
    n_groups: int = len(groups)
    print(f"tools/call agenda(view=tasks) -> title={payload.get('title')!r} groups={n_groups}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        raise SystemExit(self_test())
    serve()
