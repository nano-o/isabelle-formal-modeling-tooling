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
bin/isabelle-tooling   command interface: skills list/show, init/sync/update/remove, doctor
scripts/isabelle_tooling.py  its implementation; project_files.py holds the rules shared with agent-board
scripts/new-project.sh the session renderer behind `init`, reading templates/ from the pinned commit
scripts/render-agents.sh  render the two host worker profiles from agents/
extension/             skills, worker profiles, the iq bridge launcher; project/ is what init installs
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

I/Q takes its token from `IQ_AUTH_TOKEN`, which `scripts/launch_jedit.sh`
sets from that file (see "The jEdit workflow"); without it, I/Q makes up a
random token. The project's `iq` server, `extension/bin/iq-bridge.sh`,
authenticates every connection with the same file (`IQ_TOKEN_FILE` overrides
the path for the launcher, the bridge and doctor alike), so agents never read
the token and need no permission for it. When the two disagree, every I/Q
call fails with "I/Q did not accept the token".

## Quick start: a new project

With the tooling clone set up (above), `ISABELLE_TOOLING_ROOT` naming it in
the shell the agent host starts from, and the clone checked out at `stable`,
the validated commit, run this in the project before starting a host session
there:

```bash
"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" init --session MyProject   # --formal-rel formal --source-rel . by default
git add -A -- PATHS...                                                    # the paths init printed; it never stages or commits
git commit -m "Add the Isabelle tooling"
```

`init` writes the descriptor `isabelle-tooling.conf` pinned at `stable`, an
empty session under `formal/`, and the project files: the five skills under
`.agents/skills/` (Claude Code sees them through `.claude/skills/`), the
`ic2-prover` worker profiles in `.claude/agents/` and `.codex/agents/`, the
`iq` MCP server in `.mcp.json` and in a managed block of
`.codex/config.toml`, and a short block in the root `AGENTS.md` (with
`CLAUDE.md` pointing at it) that sends agents to `formal/AGENTS.md` and the
skills. Nothing in them names a machine path.

Then trust the project in Codex CLI, or approve the `iq` server at the first
Claude Code start, start a session and ask the agent to finish the setup:
the `isabelle-setup` skill walks through what is left and runs `isabelle-tooling
doctor`. The steps only you can do are the ones under "Setting up the tooling
clone" that write under your home directory, and removing an installed
Isabelle plugin, a user-level `iq` server or `ic2-prover` profile, which
doctor names with the command to run.

To coordinate several agents in the project, add agent-board, a separate
tool with its own README: put `agent-board` on `PATH` (or set
`AGENT_BOARD_COMMAND`), run `agent-board init` and optionally
`agent-board install-hook`, and commit what it printed. The two installers
own disjoint files and can run in either order; stage what the first printed
before running the second.

Later:

- `isabelle-tooling sync --check` compares the project files with the pinned
  commit, read-only; `sync` reinstalls exactly that commit's files and
  refuses to overwrite a managed file someone edited.
- `isabelle-tooling update REV` (a commit, or `stable`) is the only command
  that moves the pin. The runtime clone must be at the pin: one clone serves
  every project pinned to its commit, and doctor fails for a project on
  another.
- `isabelle-tooling remove` takes the project files and descriptor out,
  leaving the session and the instruction files.
- `isabelle-tooling skills list` and `skills show NAME` print the skills of
  the project's pin (outside a project, of `stable`) from Git, never from a
  working tree, and need no prover.
- To develop the skills, work in a separate worktree of this repository and
  run `isabelle-tooling sync --link --source <worktree>` in a project: the
  installed skills become symlinks into it until `sync` restores the copies.
  Link mode is never committed, and doctor fails on it without
  `--allow-dirty`.

A project whose descriptor predates project files adopts them with
`isabelle-tooling update REV`, which refuses if any file it would install is
already there. The contracts behind all of this are in
[docs/delivery-contracts.md](docs/delivery-contracts.md).

## The extension directory

`extension/` holds what projects receive: the `skills/` tree
(`isabelle-setup` for binding a project, `isabelle-proving` for the two
theory-editing workflows and the proof discipline, `isabelle-modeling` for
the code-level model standard and its conventions interview,
`isabelle-differential` for testing an exported model against its
implementation, `isabelle-assurance` for stating what the work
establishes); the worker profiles `agents/ic2-prover.md` (Claude Code) and
`agents/ic2_prover.toml` (Codex CLI), both rendered from
`agents/ic2-prover.instructions.md` by `scripts/render-agents.sh` (`make
validate` fails when either is stale); `bin/iq-bridge.sh`, the `iq` server's
launcher; and `project/`, the manifest and the templates of the managed
entries and blocks.

The two `iq` declarations differ on purpose. Claude Code expands
`${ISABELLE_TOOLING_ROOT}` in a `.mcp.json` `command`; Codex CLI expands no
variable in a stdio `command` and passes a server only the variables its
`env_vars` names, so its block runs the launcher through `bash -c` and
forwards `ISABELLE_TOOLING_ROOT` and the token variables.
`tests/extension_manifest_test.py` holds both shapes in place.

Until extension v0.7.1 the tooling was also delivered as a Claude Code and
Codex CLI plugin, from a `release` branch with its own marketplaces and a
release script. That route was removed after the project files replaced it;
the `v0.x` tags keep it, and it can be restored from Git. Doctor still fails
while either host has an Isabelle plugin or its marketplace installed, since
it would duplicate the project's files.

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
tooling_revision=<40-hex> # the pin: the tooling commit whose project files are installed
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
`export_name`, `model_dispatch`, and `audit_collection` configure the model
runner and the export check (below). `tooling_revision` is optional in the
format, but project files need it: `init` writes it and `update` is the only
command that changes it, touching only that line.

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

## Several agents on one repository

Agents that share a repository and its worktrees can coordinate through
agent-board, a separate repository with its own CLI, skill and Claude Code
digest hook; it used to live here as `scripts/board.sh`. A checkout opts
in with `agent-board.conf` at its root, which `agent-board init` writes with
the board's own project files; this tooling never installs the board. When
the checkout is configured and `agent-board` resolves
(`AGENT_BOARD_COMMAND`, else `PATH`),
`ic2.sh start` and `stop` post a note as `ic2`, waiting at most five
seconds for the board. The proof resources agents claim are theory files,
proof branches and `token:jedit`, the human's I/Q session in the main
worktree. A delegation brief's first line makes the proof worker
independent (`Mode: independent. Handle: HANDLE.`) or supervised (`Mode:
supervised by HANDLE.`); both worker profiles describe the two modes.

## Differential testing: the model runner and the export check

Differential testing is a method the `isabelle-differential` skill teaches,
not a framework; the corpus, the validator, the mutation policy, and the
implementation adapter are project code. Two pieces are the same for every
project and live here.

`scripts/model-runner.sh` evaluates the exported code-level model over
records. It builds the session, exports the code named by the descriptor's
`export_name`, loads it into `isabelle ML_process` together with the
project's `model_dispatch` file and `model-runner/runner.ML`, and keeps
input and output rows aligned. Records are opaque: each non-comment line goes
to the project's `Model_Dispatch.dispatch : string -> string`, whose result
is appended after a tab; `Model_Dispatch.Reject` marks a malformed record.
The dispatch file is trusted semantic code that converts and routes but never
decides (see the skill).

```bash
"$ISABELLE_TOOLING_ROOT/scripts/model-runner.sh" batch corpus.tsv model.tsv
"$ISABELLE_TOOLING_ROOT/scripts/model-runner.sh" resident   # answers stdin line by line
```

Batch mode installs the output atomically and aborts on a rejected record or
a dispatch failure. Resident mode prints `#ready`, then one answer per input
line: the echoed record with its suffix, `#reject<TAB>LINE<TAB>MESSAGE`,
`#error<TAB>LINE<TAB>MESSAGE`, or `#` for a blank line. Everything before
`#ready` is loader output the client discards.

`scripts/export-check.sh` checks that the executable model is the proved one.
It audits every code equation of every constant in the exported program and
every fact of the descriptor's `audit_collection` (default `export_audit`, a
`named_theorems` the theories add their refinement theorems to): no oracle
may appear in a derivation (`sorry` is the `skip_proof` oracle), and no axiom
declared by a project theory unless it is a definition, a typedef, or HOL's
contentless `type`-class arity; axioms of the distribution and imported
libraries are the trusted baseline. It also scans project sources for
`code_printing`, `code_module`, and `code_reserved` declarations touching a
symbol of the exported program, accepted only through `--allow SYMBOL`.

```bash
"$ISABELLE_TOOLING_ROOT/scripts/export-check.sh"            # from inside the checkout
"$ISABELLE_TOOLING_ROOT/scripts/export-check.sh" --verbose  # list every audited theorem
```

The audit runs inside the session heap, so the check builds with
`isabelle build -b`; the first run rebuilds the session once even after a
plain build passed. Heaps record theorem names and oracles but not full proof
terms, so an axiom used from ML without ever being stored as a named fact is
invisible; the check cannot vouch for the code generator, Poly/ML, or the
dispatch ML either. `tests/fixtures/export-check/` holds a clean fixture and
three that must fail: a `code_printing` override, a code equation proved by
a declared `oracle`, and a code equation resting on an `axiomatization` in an
imported theory.

## Doctor

```bash
"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling" doctor [--project-root DIR] [--allow-dirty]
```

Checks, in order: the descriptor and its roots; that `ISABELLE_TOOLING_ROOT`
names this clone; Isabelle and its version; the AutoCorrode submodule
against the recorded gitlink; a clean tooling clone and submodule (modified
scripts execute while `HEAD` still matches, so a dirty clone fails unless
`--allow-dirty`, which passes and marks the report); the project files
against the pin and the clone against the pin (`sync --check`; link mode is
a note only with `--allow-dirty`); the host configuration of both hosts, read
from `CLAUDE_CONFIG_DIR` and `CODEX_HOME` when set, where an Isabelle plugin
or its marketplace, a user-level `iq` MCP server or a user-level
`ic2-prover` profile fails; exactly one ic2 component, registered from this
clone, with its JAR built; systemd user scopes; the I/Q plugin stamp and
token; the I/R environment against the lock file; and, when the project has
`agent-board.conf`, the board: `agent-board` must resolve and report
interface 1 with the `doctor` and `project` capabilities, and each check of
its `doctor --json` is reported as `board: ID: MESSAGE`. It prints
remediation commands and never runs them, and it writes nothing, in the
project or in the clone.

## Validation

```bash
make validate         # bash -n, ShellCheck, the tests behind a mock isabelle, the project-file tests
make check-isabelle   # export-check fixtures and the model runner, against a real Isabelle
```

Host fixtures (a fresh session driving the setup skill, a doctor run, an
`isabelle build`) are run non-interactively in a checkout that has the
project files: `claude -p ...`, and `codex exec -C <checkout> ...` once the
checkout is trusted.
Under Codex, pass `-c model_reasoning_effort=medium` for these runs; the
user's default of `xhigh` turns a two-minute fixture into a ten-minute one and
adds nothing to a smoke check. Run them in the background with a timeout.

The Phase 4 host fixture, `tests/host/phase4-fixture.sh claude|codex WORKDIR`,
copies the C project in `tests/fixtures/host/fee/` into a fresh checkout,
installs the project files with `isabelle-tooling init`, and drives one host
through two turns: setup and the conventions interview, then
the user's answers and the whole method (model, differential test, one
proved property, assurance section). `tests/host/phase4-check.sh PROJECT`
then runs the mechanical acceptance (doctor, settled conventions, clean
build, export check, `run.sh`, the named property); the side-by-side review
of the theory against `src/fee.c` is a reader's job, by section 4 of the
`isabelle-modeling` skill. Run the fixture separately for each host, with
distinct `--session` names if both run at once, so their heaps do not
collide.

See [docs/architecture.md](docs/architecture.md) for the process layout, and
the standing notes [docs/security.md](docs/security.md) and
[docs/jai-agent-isolation.md](docs/jai-agent-isolation.md), which describe the
isolation design that this native workflow deliberately defers.
