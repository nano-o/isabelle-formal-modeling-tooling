# Isolating Isabelle agents with JAI

*Status: a design note written for the earlier layout, in which the tooling
lived in the project under `formal/tooling/` and ic2 ran in one Docker
container per worktree (`formal/tooling/scripts/offer-exchange-ic2.sh`). The
tooling now runs a native ic2 server per worktree from a separate clone (see
the README), so the Docker broker sections no longer apply as written; the
JAI policy, the credential rules and the I/Q sections still do. Paths such
as `/path/to/project` are placeholders.*

This document describes how to run proof agents under
[JAI](https://jai.scs.stanford.edu/) without giving them Git credentials while
preserving both supported workflows:

- Isabelle/jEdit with I/Q and I/R in the jEdit worktree; and
- headless ic2 in a dedicated ic2 worktree.

The two workflows cross the jail boundary differently. I/Q is already an
authenticated, root-scoped capability. ic2 currently reaches its container
through the host Docker daemon, so safely using it from a strict jail requires
a narrow host-side broker or a trusted person/process to relay wrapper
commands.

This design complements [security.md](security.md). It does not replace the
workflow rules in [`formal/AGENTS.md`](../../AGENTS.md).

## Goals

- Run each agent in a named JAI jail in `strict` mode.
- Do not expose SSH keys, an SSH agent, `gh` state, Git credential stores, or
  GitHub tokens to an agent.
- Preserve live, shared editing through I/Q in the jEdit worktree.
- Preserve direct theory editing and full ic2 checking in an ic2 worktree.
- Keep raw Docker authority outside the agent jail.
- Leave fetching private objects, reviewing changes, publishing branches, and
  opening pull requests to a trusted host-side actor.

Local Git operations do not intrinsically require remote credentials. A
trusted coordinator can create branches and linked worktrees locally, and an
agent can optionally inspect their Git state without acquiring the ability to
fetch from or push to a private remote.

## Base JAI policy

Use a distinct named strict jail for each role or trust boundary. Strict mode
provides an empty, persistent jail home and runs the command as the
unprivileged `jai` user. Do not bind the real home directory, `.ssh`,
`.config/gh`, `.git-credentials`, `.gnupg`, or the host runtime directory into
the jail.

The agent client still needs its own service authentication. Initialize that
inside the named jail so its state is stored in the jail-specific home rather
than exposing the host's complete `.codex` or `.claude` directory. This is
separate from Git authentication.

In addition to JAI's default secret-variable filtering, explicitly remove the
common Git credential paths from the environment:

```text
unsetenv GH_TOKEN
unsetenv GITHUB_TOKEN
unsetenv SSH_AUTH_SOCK
unsetenv GIT_ASKPASS
unsetenv SSH_ASKPASS
unsetenv GIT_SSH
unsetenv GIT_SSH_COMMAND
setenv GIT_CONFIG_GLOBAL=/dev/null
```

Before relying on this boundary, audit repository-local remote URLs and Git
configuration for embedded credentials. This repository normally uses an SSH
remote without an embedded credential, but the policy should not assume that
all repositories do.

JAI gives its current working directory read/write access by default. Use
`nocwd` plus explicit `rdir` and `dir` entries when a workflow needs a smaller
surface. Also avoid placing assigned worktrees under `/tmp`, because every JAI
jail has a private `/tmp`; use a persistent, explicitly granted worktree
directory instead.

## Isabelle/jEdit and I/Q in the jEdit worktree

### What I/Q protects

I/Q has security provisions specifically suited to this boundary:

- it binds only to `127.0.0.1`;
- clients must authenticate for each connection;
- read operations are limited to configured allowed read roots;
- mutations are limited to configured allowed mutation roots; and
- the authentication token remains outside the repository.

The project launcher sets the I/Q mutation root to `formal/` and supplies the
persistent token from `~/.config/isabelle-iq/auth-token`. The jailed MCP bridge
can reach the server because the current JAI implementation shares the host
network namespace; its private PID, runtime, and temporary-file namespaces do
not prevent a connection to `127.0.0.1:8765`.

I/Q is therefore an intentional, narrowly scoped write capability from the
agent jail into the live jEdit document. The jailed agent should otherwise see
the repository read-only and must continue to make all theory changes through
I/Q, as required by `formal/AGENTS.md`.

### Agent profile

A representative `~/.jai/codex-iq.conf`, invoked from the repository root, is:

```text
conf .defaults
jail codex-iq
mode strict

nocwd
rdir ${PWD}
rdir /home/you/.config/isabelle-iq

setenv IQ_MCP_BRIDGE_LOG_FILE=/tmp/iq-bridge.log

unsetenv GH_TOKEN
unsetenv GITHUB_TOKEN
unsetenv SSH_AUTH_SOCK
unsetenv GIT_ASKPASS
unsetenv SSH_ASKPASS
unsetenv GIT_SSH
unsetenv GIT_SSH_COMMAND
setenv GIT_CONFIG_GLOBAL=/dev/null
```

The bridge normally writes `bridge_log.txt` beside `iq_bridge.py`. Redirecting
it to the jail's private `/tmp` lets the repository remain read-only.

Start the agent from the repository root so the checked-in `.codex/config.toml`
and its relative bridge path resolve correctly:

```bash
cd /path/to/project
jai -C codex-iq codex
```

Authenticate the agent client inside this named jail once, using its normal
login flow. Do not grant the jail the host's Git or GitHub credential
directories. Inside a proof session, authenticate I/Q with the read-only token
file and verify the connection with `list_files` before doing other work.

### Where jEdit runs

There are two defensible placements, depending on the threat model.

#### Practical credential and damage isolation

Run jEdit normally on the host with the existing launcher, and run only the
agent inside JAI:

```bash
"$ISABELLE_TOOLING_ROOT/scripts/launch_jedit.sh" \
  --project formal \
  --session MyProject \
  --venv "$ISABELLE_TOOLING_ROOT/.venv" \
  MyProject/Theory.thy
```

This protects Git credentials and prevents ordinary agent shell commands from
writing outside I/Q's allowed mutation root. It is appropriate when checked
theories and the agent's Isabelle edits are trusted not to contain hostile
Isabelle/ML.

#### Stronger Isabelle/ML isolation

I/Q restricts MCP file operations, but it is not a sandbox for code evaluated
by Isabelle. A theory can contain an `ML` command, and jEdit evaluates such
code with the authority of the jEdit process. If deliberately hostile theory
content is in scope, run jEdit in a separate credential-free strict jail as
well.

Run that jail from `formal/`, so its default read/write grant covers only the
formal tree:

```bash
cd /path/to/project/formal
jai -mstrict -j isabelle-jedit \
  -r "$HOME/.config/isabelle-iq" \
  -r "$ISABELLE_TOOLING_ROOT" \
  "$ISABELLE_TOOLING_ROOT/scripts/launch_jedit.sh" \
    --project . \
    --session MyProject \
    --venv "$ISABELLE_TOOLING_ROOT/.venv" \
    --token-file "$HOME/.config/isabelle-iq/auth-token" \
    MyProject/Theory.thy
```

The launcher records the jEdit it starts in the checkout's Git data, so that
ic2 refuses that checkout while jEdit runs. A jail that hides the checkout's
Git data, or mounts it read-only, leaves nothing recorded (the launcher warns
in the second case), and ic2 cannot see this jEdit; the ic2-worktree marker
described below is then the only safeguard.

Install the I/Q plugin once from inside the same named jEdit jail so the plugin
JAR is stored in that jail's persistent Isabelle user directory. GUI access is
an additional capability: prefer a nested display or similarly isolated GUI.
Granting an agent-controlled process access to the main X11 session weakens
the boundary substantially.

Both placements preserve the existing human-and-agent PIDE workflow. The
stronger placement additionally confines Isabelle/ML to the formal tree, the
jEdit jail home, and its private temporary directory.

## ic2 in an ic2 worktree

The ic2 worker must not receive I/Q access. It edits saved theory files
directly in one ic2 worktree and checks them through the tooling clone's
`scripts/ic2.sh`, run from that worktree. Before editing it runs `ic2.sh
preflight`, which passes only in a checkout marked as an ic2 worktree that
no running jEdit owns.

### Trusted provisioning

A trusted host-side coordinator performs the operations that may need shared
Git metadata or remote authentication:

1. Inspect the jEdit worktree and resolve the exact committed base.
2. Create a local branch and an ic2 worktree under an explicitly managed
   worktree parent with `ic2.sh worktree add`, which also marks it.
3. Start the worktree's ic2 server, or register the worktree with the ic2
   broker described below.

For example, outside the worker jail:

```bash
JEDIT_WT=/path/to/project
WT=/path/to/worktrees/proof-1
BRANCH=ic2-proof-1

cd "$JEDIT_WT" && "$ISABELLE_TOOLING_ROOT/scripts/ic2.sh" worktree add "$WT" -b "$BRANCH" HEAD
cd "$WT" && "$ISABELLE_TOOLING_ROOT/scripts/ic2.sh" start
```

Creating and marking the worktree are local. Worktrees need no submodule:
the tooling and AutoCorrode live in the tooling clone. The marker is in the
worktree's own Git data, under the common Git directory's `worktrees/`, so
the worker below can read it but not write one.

### Worker jail

Give the worker read access to the whole assigned checkout and write access
only to its `formal/` subtree. Disable I/Q explicitly:

```bash
WT=/path/to/worktrees/proof-1
COMMON="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir)"
BROKER_DIR=/run/user/1000/jai-ic2/proof-1

jai -D -mstrict -j ic2-proof-1 \
  -r "$WT" \
  -d "$WT/formal" \
  -r "$COMMON" \
  -r "$ISABELLE_TOOLING_ROOT" \
  -r "$BROKER_DIR" \
  codex -C "$WT" -c 'mcp_servers.iq.enabled=false'
```

The read-only common Git directory is required: a linked worktree's `.git`
file points into it, and `ic2.sh preflight` reads the worktree's marker
there. It also permits `git status`, `git diff` and branch inspection. In a
`.bare` repository it is the `.bare` directory, not `PROJECT/.git`, which is
a one-line file.

Do not give the worker write access to the common `.git` directory merely to
allow commits. Besides changing shared refs, writable Git metadata gives an
agent persistence opportunities through configuration and hooks. A safer
handoff is for the trusted coordinator to review the saved worktree diff and
create the local commit afterward. No remote action should occur as part of
this handoff.

### Why Docker needs a broker

The current project wrapper eventually invokes the host Docker client:

```text
worker -> offer-exchange-ic2.sh -> docker exec -> ic2 container
```

Giving `/var/run/docker.sock` to the jailed worker would allow it to bypass the
JAI filesystem boundary by asking Docker to mount arbitrary host paths. A CLI
allowlist inside the agent product is not an OS security boundary when the
same jailed process can open the Docker socket directly.

Instead, run a small trusted broker outside JAI. Each broker instance is bound
to exactly one canonical worktree and its derived container name. Expose only
that broker's Unix socket directory to the corresponding worker jail.

The broker should accept only the operations needed by `formal/AGENTS.md`:

```text
server status
check <relative .thy path>
wait [--interval N] [--timeout N]
query diagnostics <relative .thy path> --json
query sorry <relative .thy path> --json
approved repl operations
health
stop
stop --remove
```

It should:

- resolve every theory path beneath the assigned `formal/` directory and
  reject absolute paths, `..`, symlink escapes, and other worktrees;
- invoke only the tooling clone's `ic2.sh` for the assigned worktree;
- return stdout, stderr, and the exit status without evaluating shell text;
- reject raw Docker commands, arbitrary container names, arbitrary start
  options, token-file mounts, volume deletion, and interactive `check attach`;
- serialize commands for the one ic2 server; and
- record an audit log outside the worker's writable filesystem.

Container creation can remain a trusted provisioning operation. The broker
then needs only to operate or restart the already-defined container. The ic2
container retains its existing containment: only the selected formal tree is
mounted read/write, runtime networking is disabled, capabilities are dropped,
and the host Docker socket is not mounted.

Until such a broker exists, a trusted person or supervisor can relay the exact
wrapper commands requested by the worker. That preserves the security
boundary, but the proof job is not fully autonomous.

### Validation and handoff

The worker follows the existing ic2 sequence through the broker:

1. Edit only the assigned theory scope.
2. Submit `check` and use `wait` to reach a terminal result.
3. Query diagnostics and sorry positions as JSON.
4. Check every changed theory.
5. Stop its container without deleting the heap volume.
6. Report changed files and exact validation results.

The final `isabelle build -D formal` can run in a credential-free
strict jail using that jail's private Isabelle home, or it can be run by the
trusted host-side coordinator. The coordinator then reviews the diff and may
create a local commit. Merging, cherry-picking, pushing, or opening a pull
request remains a separate human-authorized action.

## Capability summary

| Component | Writable host state | Credential/capability |
| --- | --- | --- |
| jEdit-worktree proof agent | None directly; theory edits through I/Q | Agent-service auth and read-only I/Q token |
| Host jEdit, practical placement | I/Q mutation root under `formal/` | I/Q token; no Git credential needed |
| Jailed jEdit, stronger placement | `formal/` and private jail home | I/Q token only |
| ic2 worker | Assigned worktree's `formal/` | Agent-service auth and per-job broker socket |
| ic2 broker | Docker operations for one derived container | Host Docker authority, not exposed to worker |
| ic2 container | Mounted assigned `formal/` and named heap volume | Internal I/R token only; no network or Git credentials |
| Trusted coordinator | Worktrees, shared Git metadata, optional local commits | Host Git credentials only when a private fetch is necessary |

## Implementation work

The I/Q arrangement requires only JAI profiles and token-directory grants; the
existing project launcher and MCP configuration already provide the necessary
root restrictions.

Fully autonomous ic2 work under strict JAI still needs:

1. a per-job host-side broker and a small jailed client;
2. path-validation and command-grammar tests for that broker;
3. JAI profile templates for the I/Q agent, jailed jEdit, and ic2 worker; and
4. documentation updates that identify the broker as the only permitted ic2
   control path from a strict jail.

Do not implement the ic2 design by exposing the Docker socket to a casual or
bare jail. Docker authority would allow the agent to recover the host
credentials that JAI was intended to hide.
