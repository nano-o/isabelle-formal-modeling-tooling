---
name: isabelle-pide-ai
description: Set up Isabelle2026 and use the project's PIDE AI MCP server to develop, inspect, and verify Isabelle proofs. Use for theory or ML work in a project with isabelle_version=Isabelle2026.
---

# Proving with Isabelle2026 and PIDE AI

Run `"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" doctor` from the project.
If the PIDE AI component needs setup, use the tooling clone's
`scripts/setup-pide-ai.sh`. It fetches the tooling's pinned upstream commit,
registers it in the Isabelle2026 user home, and builds its JARs. On a host
with both Isabelle releases, point `ISABELLE_TOOLING_ISABELLE2026` at the
2026 installation or executable before starting the agent host.

The project's `isabelle-pide-mcp` server starts a session with the project
session's requirements and keeps the project theories editable. Use
`list_sessions` and `get_session_state` to check readiness. Read and edit a
theory with `read` and `edit_get_state`, and use `get_state` to inspect the
surrounding proof and diagnostics. Check the theory beyond the edited
commands, especially after changes to imports or declarations. Tool paths
are relative to the project root.

Use Isabelle symbol escapes on disk, for example `\<forall>` and
`\<open>`. The launcher configures PIDE AI to save files in that form. PIDE
AI and jEdit maintain independent document state. Coordinate file ownership
before editing, and save or reload editor buffers before switching between
them. Independent agents can work in separate worktrees.

Use `isabelle build -D <formal-root>` with the Isabelle2026 executable for
final validation. Use the project's formal instructions for build options
and its conventions for proof completeness.
