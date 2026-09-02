# Isabelle formal-modeling tooling

Host-side tooling for projects that build a bit-precise Isabelle/HOL model of
an implementation and prove properties about it. It provides one pinned
Isabelle workflow for a project checkout: a native [ic2](AutoCorrode/ic2)
server per Git worktree for headless checking, queries, and I/R proof REPLs;
the Isabelle/jEdit launcher with the I/Q agent plugin for interactive work; a
setup checker; and the scripts that build the pieces. It targets Linux hosts
only (GNU userland, bash 4 or later, the official Linux Isabelle
distribution).

This is a **tooling clone**: keep it outside every project checkout, at a
path of your choosing. Everything it builds — the I/R Python environment and
the ic2 JAR — stays inside the clone. It writes nothing under `$HOME` on its
own; the three persistent steps that do are Isabelle's, jEdit's, and I/Q's
conventions, each shown below with its effect and undo.

```text
AutoCorrode/           pinned submodule (github.com/nano-o/AutoCorrode): ic2, I/Q, I/R
scripts/common.sh      descriptor parser, checkout resolver, shared helpers
scripts/ic2.sh         project entry point: start/stop/name/wait/health + `isabelle ic2 ...`
scripts/start-ic2.sh   native `ic2 server start` wrapper (base session, heap bound)
scripts/stop-ic2.sh    native `ic2 server stop` wrapper
scripts/build-ic2.sh   register the ic2 component and build its JAR
scripts/doctor.sh      check the whole setup, print remediations, run nothing
scripts/setup-ir-venv.sh      create the I/R Python environment (.venv/)
scripts/install-iq-plugin.sh  build/install/stamp the I/Q jEdit plugin
scripts/launch_jedit.sh        launch host jEdit with I/Q and I/R
tests/                 helper tests behind a mock `isabelle` (make validate)
docs/                  architecture; standing notes on isolation and security
```

## Prerequisites

- **Isabelle2025-2**, installed by you where you choose, with its `bin/` on
  `PATH` or named by `ISABELLE_TOOLING_ISABELLE`. The tooling never downloads
  Isabelle; `doctor` names the expected release and
  <https://isabelle.in.tum.de> when it is missing. Only this one release is
  supported; theories are not portable across releases.
- Git, Python 3.10 or newer, Make, OpenSSL; ShellCheck when changing the
  scripts; TeX Live only for a project's PDF document build.
- systemd with a user session, for the prover memory bound (optional; without
  it servers start unbounded and `doctor` says so).

## Setting up the tooling clone

```bash
git clone --recurse-submodules https://github.com/<you>/isabelle-formal-modeling-tooling
cd isabelle-formal-modeling-tooling
scripts/setup-ir-venv.sh        # .venv/ inside the clone
scripts/build-ic2.sh            # see below; the one ic2 step under $HOME
scripts/install-iq-plugin.sh    # for the jEdit workflow only; jEdit must be closed
```

`build-ic2.sh` runs `isabelle components -u <clone>/AutoCorrode/ic2`, which
adds one line to `$ISABELLE_HOME_USER/etc/components` (Isabelle discovers
components only through that file), then builds `AutoCorrode/ic2/lib/ic2.jar`
inside the clone. Register exactly one ic2 component, from this clone; two
registrations make Isabelle load whichever comes first, and `doctor` fails on
it. Undo with `isabelle components -x <clone>/AutoCorrode/ic2`. When the clone
moves, unregister the old path and register the new one.

`install-iq-plugin.sh` places one JAR and a provenance stamp under
`$ISABELLE_HOME_USER/jedit/jars/`, where jEdit requires plugins to be. The
I/Q token lives at `~/.config/isabelle-iq/auth-token` (mode 600), the bridge's
own convention:

```bash
mkdir -p ~/.config/isabelle-iq && (umask 077; openssl rand -hex 32 > ~/.config/isabelle-iq/auth-token)
```

## Binding a project: the descriptor

A project checkout carries one committed file at its root,
`isabelle-tooling.conf`. It is data in a small `key=value` format — UTF-8, one
key per line, full-line `#` comments, the value is everything after the first
`=` — never sourced or passed to `eval`. The parser rejects duplicate keys,
unknown keys, missing required keys, an unsupported `format_version`,
absolute path values, and any `..` component.

```ini
format_version=1
source_rel=.              # where the code under study lives, relative to the checkout root
formal_rel=formal         # where ROOT/ROOTS and the theories live
tooling_revision=<40-hex> # commit of this clone the artifacts were validated against
build_session=MyProject
session_dir=MyProject     # relative to formal_rel
ic2_base_session=HOL      # the logic ic2 starts from: never the project session
ic2_max_heap=12G          # prover memory bound; optional
isabelle_version=Isabelle2025-2
```

`source_rel` and `formal_rel` are independent, so an in-tree layout (`.` and
`formal`) and an assurance repository that holds the theories and references
the code (`X` and `.`) are the same mechanism. `ic2_base_session` is
deliberately not the project session: when the project session is the
server's logic, its theories are heap nodes and ic2 cannot expose their
per-command diagnostics or `sorry` positions after edits. Optional keys
`export_name`, `model_dispatch`, and `audit_collection` are reserved for the
model runner and export check and are parsed but not yet consumed.

Every entry point resolves the project the same way: `--project-root DIR`
reads the descriptor there; otherwise the nearest ancestor of the current
directory that contains the descriptor wins, so the scripts work from any
directory inside a checkout, including a fresh Git worktree, which carries
the descriptor like every other checkout. No descriptor on the path is an
error that names the flag.

## The ic2 workflow

Each checkout gets its own server, named
`ic2-<checkout basename>-<8 hex of sha256(checkout path)>` with its socket
and log under `$ISABELLE_HOME_USER/ic2/`. Servers share the host's read-only
base heap; nothing is built per worktree. From anywhere inside the checkout:

```bash
ic2.sh start --cpus 8                        # idempotent: already running is success
ic2.sh server status                         # without -n, `isabelle ic2 server status` lists every server
ic2.sh check MyProject/Theory.thy --command-timeout 15
ic2.sh wait --timeout 900                    # poll to ok / failed / idle; never use `check attach`
ic2.sh query diagnostics MyProject/Theory.thy --json
ic2.sh query sorry MyProject/Theory.thy --json
ic2.sh repl-create /abs/path/MyProject/Theory.thy:87 r87
ic2.sh health                                # RSS and CPU of the server's process tree
ic2.sh stop
```

`check` takes paths relative to the formal root; `repl-create` takes an
absolute path, and `check status` prints the exact command for a located
failure. `start` passes `-o document_variants=` so the headless server never
tries to typeset, and, where `systemd-run --user` works, wraps the Poly/ML
process in a transient scope with `MemoryMax` set from `ic2_max_heap` (or
`--max-heap`). That is a resource limit, not a security boundary; when the
prover exceeds it the kernel kills it, the daemon reports `state=failed
reason=prover process terminated (rc=137)`, the in-flight check settles as
`failed reason=prover_died`, and check, query, and REPL requests are refused
until `stop` and `start`. The wrapper's own liveness check — a Poly/ML
descendant of the server pid — is a fallback that is inconclusive from a
shell in a private PID namespace and says nothing then.

Final validation of a session, including its document, stays the host command
`isabelle build -D <formal root>`.

## The jEdit workflow

```bash
scripts/launch_jedit.sh --project <formal root> --session MyProject --venv <clone>/.venv MyProject/Theory.thy
```

The launcher accepts `--read-root DIR` for directories I/Q may read outside
the project. Agents reach the live PIDE document through the I/Q MCP bridge,
`AutoCorrode/iq/iq_bridge.py`, launched from this clone.

## Doctor

```bash
scripts/doctor.sh [--project-root DIR] [--allow-dirty]
```

Checks, in order: the descriptor and its roots; Isabelle and its version; the
AutoCorrode submodule against the recorded gitlink; a clean tooling clone and
submodule (modified scripts execute while `HEAD` still matches, so a dirty
clone fails unless `--allow-dirty`, which passes and marks the report); the
descriptor's `tooling_revision` against the clone's `HEAD`; exactly one ic2
component, registered from this clone, with its JAR built; systemd user
scopes; the I/Q plugin stamp and token; the I/R environment against the lock
file. It prints remediation commands and never runs them.

## Validation

```bash
make validate     # bash -n, ShellCheck, and the tests behind a mock isabelle
```

See [docs/architecture.md](docs/architecture.md) for the process layout, and
the standing notes [docs/security.md](docs/security.md) and
[docs/jai-agent-isolation.md](docs/jai-agent-isolation.md), which describe the
isolation design that this native workflow deliberately defers.
