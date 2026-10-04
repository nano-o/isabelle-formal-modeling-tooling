# Validation records

`stable` names the commit that appended the newest entry below. Each entry
is a validation record commit: the commit at which the new-project fixtures
of [new-project-delivery-plan.md](new-project-delivery-plan.md) passed, plus
the entry itself. The mechanical checks are rerun at exactly that commit
before `stable` moves to it. The plan's History has the details of each run.

## 2026-09-29: the first `stable`

Candidates
: isabelle-formal-modeling-tooling `2d10fe9`, this commit's parent. The
  fixtures ran at `e25d1ef`, which differs from it only in the plan's
  History and status line. AutoCorrode `dbd474f`, a local commit on the
  fork's `6f69263`.
: agent-board `6a467ea`. The fixtures ran at `c6b934c`, which differs from
  it only in its README's status. Board CLI interface 1, state format 2.

Hosts
: Claude Code 2.1.284 with claude-opus-5-5, in auto permission mode.
: Codex CLI 0.155.1 with gpt-6-astra at medium reasoning effort, in the
  workspace-write sandbox with automatic review.
: Isabelle2025-2, Git 2.43, Python 3.12.3, on Linux.

Setup
: The runtime was a detached worktree of this repository at the
  candidate, with its own Isabelle user home (`USER_HOME`) and fresh host
  configuration roots.
: Fixtures: a bare `git init` repository; a stellar-core clone with both
  components and a `Demo` session (by the user's choice, in
  place of a codebase other than stellar-core); and, for adoption, a
  snapshot of the offer-exchange checkout at `319fed13e0`.

Passed
: Installers, doctors and the command interface: 71 checks on the bare
  repository and 70 on the stellar-core clone at `e25d1ef`.
: Adoption of an existing descriptor.
: Discovery of one copy of each skill, worker profile and `iq` server,
  from the root and from a subdirectory, on both hosts.
: Link mode: a fresh session saw a development-worktree edit.
: I/Q on both hosts, Claude Code in auto mode included, with no agent
  reading the token.
: One digest route per host.
: The worker smoke proof on both hosts, through ic2 and the board protocol.
: The nine behavioural scenarios, once per host.

Fixed during the run
: F1: agents had to read the I/Q token. The bridge now authenticates each
  connection itself (`e25d1ef`).
: F2: a jEdit started without `scripts/launch_jedit.sh` has a random I/Q
  token. The setup skill now says how to start jEdit (`7a4f065`).
: F3: ic2 socket paths could exceed ic2's limit. Server names are capped,
  and doctor checks the Isabelle home (`7a4f065`).

Accepted
: F4: Codex CLI 0.155 lists the main session's I/Q tools to a spawned
  `ic2_prover` despite its profile. Only the worker's instructions keep it
  from calling them (`11a6bcb`).
: Each behavioural scenario ran once per host, not three times.

## 2026-09-29: the plugin route removed

Candidates
: isabelle-formal-modeling-tooling `32d490a`, this commit's parent. The
  fixtures ran at `a65609b`, which differs from it only in the plan's
  History. AutoCorrode `dbd474f`, as before.
: agent-board `bf1b1ff`, its `stable`, unchanged.

Hosts
: Claude Code 2.1.284 with claude-opus-5-5, in auto permission mode.
: Codex CLI 0.155.1 with gpt-6-astra at medium reasoning effort, in the
  workspace-write sandbox with automatic review.
: Isabelle2025-2, Git 2.43, Python 3.12.3, on Linux.

Setup
: As on the first `stable`: a detached worktree of this repository at the
  candidate as the runtime, with its own Isabelle user home and fresh host
  configuration roots; the bare repository and the stellar-core clone with
  its `Demo` session.

Passed
: Installers, doctors and the command interface: 76 checks on the bare
  repository and 75 on the stellar-core clone, all but the check of
  `init` at the previous `stable`, whose doctor fails while the runtime is
  at the candidate.
: Updating to the candidate from the offer-exchange checkout as adopted in
  step 5 (`9b5ba74cc6`) and from its commit before adoption
  (`319fed13e0`).
: On both hosts: the worker smoke proof through ic2 and the board; one copy
  of each skill, worker profile and `iq` server from a subdirectory; I/Q
  without the token; one digest route.

Not rerun
: The behavioural scenarios and link mode: the change leaves the board
  skill, the instruction blocks, the worker profile's text and the link
  code as they were validated.

Observations
: A ref guard started by `git worktree add -b` in the new worktree does
  not know the coordinator's handle and refused its own claim; setting
  `AGENT_BOARD_AGENT` works (agent-board, not this repository).
: Codex CLI still lists the main session's I/Q tools to `ic2_prover` (F4).

## 2026-09-29: install-iq-plugin.sh points to the launcher

Candidates
: isabelle-formal-modeling-tooling `3432dbd`, this commit's parent. The
  fixtures ran at `245550f`, which differs from it only in the plan's
  History. AutoCorrode `dbd474f`, as before.
: agent-board `cf0fdd2`, the validation record of `7dae935`, whose ref
  guard passes the unchanged branch update of `git worktree add -b`.

Hosts
: Claude Code 2.1.285 with claude-opus-5-5, in auto permission mode.
: Codex CLI 0.159.2 with gpt-6-astra at medium reasoning effort, in the
  workspace-write sandbox with automatic review.
: Isabelle2025-2, Git 2.43, Python 3.12.3, on Linux.

Setup
: As in the previous record, with the board checkout under test named by
  `AGENT_BOARD_ROOT`; the stellar-core clone pinned at both candidates.

Passed
: `make validate`, including a test of `install-iq-plugin.sh` against a
  stand-in AutoCorrode checkout: the numbered steps that start a plain
  `isabelle jedit` are dropped, the launcher is named, and a failed build
  fails the script without a stamp.
: The installer against the real AutoCorrode Makefile, into the fixtures'
  Isabelle user home.
: Installers, doctors and the command interface: 76 checks on the bare
  repository and 75 on the stellar-core clone, all but the check of
  `init` at the previous `stable`, whose doctors fail while the runtimes
  are at the candidates.
: On both hosts: the worker smoke proof through ic2 and the board, with
  no guard refusal.

Not rerun
: The behavioural scenarios and link mode: no skill, instruction block,
  worker profile or link code changed.

Observations
: Neither smoke coordinator claimed the branch and then created its
  worktree unaided, the path refused in step 6; the board's regression
  test covers it.

## 2026-10-01: the Apache 2.0 license, and no machine paths in the docs

Candidates
: isabelle-formal-modeling-tooling `cabf405`, this commit's parent: the
  Apache License 2.0 as `LICENSE`, a `NOTICE` naming the Stellar
  Development Foundation as copyright holder, and the docs without local
  paths or the names of private projects. AutoCorrode `dbd474f`, as
  before.
: agent-board `bc84193`, the same license and documentation change, with
  its own copyright holder.

Hosts
: None: no host session ran, because nothing a host loads changed.
: Isabelle2025-2, Git 2.43, Python 3.12.3, on Linux.

Setup
: As in the previous record, with the board checkout under test named by
  `AGENT_BOARD_ROOT`. The stellar-core clone is now a clone of public
  stellar-core `release/v29.0.0`, pinned at both candidates.

Passed
: `make validate`.
: Installers, doctors and the command interface: 76 checks on the bare
  repository and 75 on the stellar-core clone, all but the check of
  `init` at the previous `stable`, whose doctors fail while the runtimes
  are at the candidates.

Not rerun
: The behavioural scenarios, link mode and the worker smoke proof: only
  `LICENSE`, `NOTICE`, the README and the docs changed, and no skill,
  instruction block, worker profile, script or link code.

## 2026-10-03: theory projects

Candidates
: isabelle-formal-modeling-tooling `abd12cd`, this commit's parent: a
  project kind `theory` for projects with no implementation to model
  (`init --kind theory`, `model_kind` in the descriptor,
  `templates/theory/`, skills selected by the manifest's `kinds`), a root
  instruction block that names no kind's skills, and a rule in
  `isabelle-proving` that every locale with assumptions has a proved
  model. The fixtures ran at `dcb7809`, which differs from it only in
  the plan's History. AutoCorrode `dbd474f`, as before.
: agent-board `aaba6dd`, the validation record of `3b2ba94`, whose shared
  module has the same project kinds.

Hosts
: Claude Code 2.1.289 with claude-opus-5-5, in auto permission mode.
: Codex CLI 0.160.0 with gpt-6-astra at medium reasoning effort, in the
  workspace-write sandbox with automatic review.
: Isabelle2025-2, Git 2.43, Python 3.12.3, on Linux.

Setup
: As in the previous record, with the board checkout under test named by
  `AGENT_BOARD_ROOT`. The previous `stable`, `f013ec6`, served as the
  older runtime by moving the runtime worktree to it.
: A new fixture: a fresh `git init` repository with `init --kind theory`
  at the candidate, once per host.

Passed
: `make validate` and `make check-isabelle`, which now builds both
  templates' sessions and a theory session importing
  `HOL-Library.FSet`.
: Between real revisions, 39 checks: the previous runtime updated a code
  project to the candidate (five skills, the new block, no
  `model_kind`); from the candidate, a code project moved back and a
  theory project was refused, unchanged; `init --revision f013ec6`
  rendered a code project byte-identical, pin aside, to one at the
  candidate, and refused `--kind theory`; the previous runtime stopped
  with `unknown key: model_kind` in `sync --check`, `sync`, `update`,
  doctor and `scripts/ic2.sh start` on the theory project, changing
  nothing.
: Installers, doctors and the command interface: 76 checks on the bare
  repository and 75 on the stellar-core clone, all but the check of
  `init` at the previous `stable`, whose doctors fail while the runtimes
  are at the candidates.
: The shared module is byte-identical in both repositories.
: On both hosts, in the theory fixture: discovery of exactly the two
  project skills and the worker profile; a recursive function and a
  lemma through ic2, with no conventions block, no `Word` import and no
  code-level skill read; and, asked for a locale with assumptions, a
  model lemma for it added unprompted. Doctor passed and the session
  built.

Not rerun
: The behavioural scenarios, link mode on a host and the worker smoke
  proof: the worker profiles, the board skill and the link code did not
  change. The instruction block and the setup and proving skills did, and
  the theory fixture exercised them on both hosts.

Observations
: Codex lists no MCP server in discovery while no jEdit serves I/Q, as in
  earlier runs; the project's `.codex/config.toml` carries the `iq`
  block.
: Until `stable` moves, `init --kind theory` without `--revision` is
  refused, naming the missing `templates/theory/` at `stable`.
