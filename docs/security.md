# Security model

ic2 is intentionally powerful. A checked Isabelle theory may contain ML code,
and upstream ic2 does not impose I/Q-style allowed read/write roots. The Docker
boundary is therefore part of this setup's security model, not merely a
packaging convenience.

## Default containment

`start-ic2.sh` applies these defaults:

- the container runs as a non-root user whose UID/GID match the image builder;
- only the selected theory worktree is bind-mounted read/write;
- the Isabelle user/heap directory is a dedicated named volume;
- runtime networking is disabled with `--network none`;
- all Linux capabilities are dropped;
- `no-new-privileges` is enabled;
- no host Docker socket is mounted into the container.

Loopback remains available inside a network-disabled container, which is
sufficient for ic2's internal I/R connections.

## Filesystem scope

Do not mount the host home directory, SSH directory, agent-client
configuration, credential stores, or unrelated source trees into the
container. Anything mounted readably is potentially readable by Isabelle/ML
code evaluated during a check.

Use a dedicated Git worktree for unattended tasks. This makes the editable
surface explicit and lets the human review or discard the result through Git.
The coordinating agent may create that worktree on the human's behalf, but it
must resolve an ambiguous dirty base rather than transferring uncommitted
changes implicitly. The project-scoped proof-worker profiles —
`.codex/agents/ic2-prover.toml` for Codex and `.claude/agents/ic2-prover.md`
for Claude Code — disable I/Q so a delegated worker cannot attach to the main
worktree's live jEdit server. The Claude Code profile also restricts the worker
to the built-in shell and file tools, and `.claude/settings.json` pre-approves
only this repository's own script entry points rather than Docker itself.
The coordinator and worker must not edit the delegated worktree concurrently.

The persistent Isabelle volume may contain built heaps and user configuration.
Use a different volume per trust boundary; `start-ic2.sh` derives one from the
container name. The stop script deliberately never deletes volumes.

## Docker authority

Access to the host Docker daemon is effectively host-level authority. Prefer
allowing agents to invoke the narrow `scripts/ic2.sh` wrapper rather than
giving them unrestricted permission to run arbitrary Docker commands.

The wrapper still permits every `isabelle ic2` subcommand inside the selected
container. Review upstream ic2's threat model before using untrusted theories.

## Authentication

The CLI control path uses an owner-only Unix-domain socket inside the container
and has no I/Q authentication step. This is the preferred agent interface.

I/R uses an internal token. `ic2 repl-create` prints ready-to-run commands
containing that token; treat logs or transcripts containing those commands as
local secrets. The token protects a loopback-only service inside an already
isolated container.

The optional ic2 MCP listener is disabled by default. When enabled, pass a
token file with `start-ic2.sh --token-file FILE`; the file is bind-mounted
read-only and the entrypoint loads its value into `IQ_AUTH_TOKEN`. Do not store
the token value in Git, `AGENTS.md`, Docker image layers, or command arguments.

## Network and dependencies

The image build needs network access for the Ubuntu base packages and the
locked I/R Python dependencies unless all layers and packages are cached.
Runtime theory checking does not need external network access in the normal
configuration.

If a theory deliberately invokes a network-dependent external tool, enable
only the minimum Docker network access needed and document that expansion.
Avoid host networking, which would also make host-local services reachable.
