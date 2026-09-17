# Architecture

## Components

The host owns everything: the Isabelle2025-2 installation, the project Git
worktrees, the agent, Isabelle/jEdit for human review, and this tooling clone
with its AutoCorrode submodule, I/R Python environment, and built ic2 JAR.

The earlier containerized design (in this repository's history and in the
project that extracted it) is gone from the core workflow; isolation is
deferred and will return as a wrapper around the native commands described
here. See [jai-agent-isolation.md](jai-agent-isolation.md) and
[security.md](security.md) for the preserved design and threat notes.

## Lifecycle

`start-ic2.sh` runs `isabelle ic2 server start --daemon` from the project's
formal root, with the base session as logic, the formal root as a session
directory, `-o document_variants=` to suppress typesetting, and, where
available, `-o process_policy=systemd-run --user --scope -p MemoryMax=…`,
which Isabelle prefixes to the Poly/ML command:

```text
isabelle ic2 server start --daemon -n ic2-<checkout>-<hash>   (JVM daemon)
  ├── systemd-run --user --scope … poly …                     (Headless.Session prover)
  └── python3 …/AutoCorrode/ir/repl.py                        (I/R bridge, from the clone's .venv)
```

`--daemon` returns once the server is serving; a cold heap build continues in
the background and `server status` shows the phase. The daemon subscribes to
the session's phase changes: if the prover process terminates it marks the
server failed with the exit code, cancels the in-flight check with reason
`prover_died`, tears down the I/R bridge, and refuses further work until the
server is stopped and started again.

## Control path

```text
agent
  → scripts/ic2.sh ACTION            (resolves the checkout, derives the server name)
  → isabelle ic2 … -n NAME           (client JVM, cwd = formal root)
  → $ISABELLE_HOME_USER/ic2/NAME.sock
  → resident Headless.Session
```

The control socket is a Unix-domain socket in a mode-0700 directory; there is
no network listener unless `--mcp` is requested. Several servers coexist by
name; `isabelle ic2 server status` without `-n` lists them all, so an orphaned
server is visible rather than hidden.

## Resolution

Every script derives the project from the committed descriptor at the
checkout root, found by `--project-root` or by walking up from the current
directory, and the tooling clone from its own location. See the README for
the descriptor format and the naming rule.

## Coordination

`board.sh` keeps a repository's coordination board under its Git common
directory (`<common dir>/isabelle-tooling/board`), the one directory every
linked worktree shares without it being part of a working tree. Presence,
posts and claims are plain files. `board.sh` delegates to the Python standard
library implementation in `board.py`. A stable kernel `flock` serializes
presence-dependent decisions, complete JSON claim snapshots, post sequence
allocation/publication, and cursor updates. Digests emit one snapshot outside
the lock and acknowledge only after successful output. Format 2 requires an
explicit migration with old writers stopped; legacy cursors replay.
Shared `pre-commit` and `reference-transaction` hooks check staged paths and
prepared ref updates. Editing, editor tokens, and branch rename destinations
still need cooperative pre-operation guards; ref rejection does not undo
index or worktree changes. `ic2.sh` posts server notes, and the extension's
Claude Code hooks inject the digest into a session. See
[coordination-board.md](coordination-board.md).
