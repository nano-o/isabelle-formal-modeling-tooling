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
: Fixtures: a bare `git init` repository; a clone of stellar-core-internal
  with both components and a `Demo` session (by the user's choice, in
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
