# Validation records

`stable` names the commit that appended the newest entry below. Each entry
is a validation record commit: the commit at which the fixtures below
passed, plus the entry itself. The mechanical checks are rerun at exactly
that commit before `stable` moves to it. Entries up to 2026-10-08 refer to
the History of the delivery plan or the theory projects plan for the
details of each run; both plans were removed on 2026-10-12 and are in Git
history.

## Fixtures

Moved verbatim from the delivery plan on 2026-10-12.

The acceptance fixtures are new projects: a bare `git init` repository and a
small existing codebase other than stellar-core. Run board alone, Isabelle
alone, and both in each installation order, separately on Claude Code and
Codex CLI, with isolated host configuration roots, starting sessions both at
the repository root and in a subdirectory. Board-only runs have no Isabelle
descriptor, installation or `ISABELLE_TOOLING_ROOT`; Isabelle-only runs have
no board executable. Combined runs also cover independent pin mismatches and
`remove` of one component while keeping the other. Record both source
revisions, the CLI compatibility version, host versions and outcomes. Run
Codex fixtures at medium reasoning effort, in the background, with stdin
closed.

With Isabelle, confirm skill, agent and I/Q discovery (Codex's upward scan
is documented; Claude Code's root `.mcp.json` and symlinked skill aliases
from a subdirectory start need proving); `link`, make one unmistakable skill
edit, start a fresh session and observe it with no reinstall; connect
through I/Q; delegate one smoke proof to the worker; `copy` and confirm the
tree is clean.

Exercise the command interface: `skills show` emits exactly the selected
Git object's bytes, with no provenance on stdout; `skills list` reports the
same revision; inspection works without a prover or network. Cover the
project pin when the tooling checkout has a different `HEAD` or uncommitted
skill edits, inspection outside a project (reads `stable`), unknown skill
names, malformed descriptors and missing pinned objects. Check that `init`
installs the complete integration at `stable`, `sync` preserves the pin, and
only `update` changes it. Include a skill with a supporting reference file,
to show that installation preserves the directory and not just `SKILL.md`.

Installer tests cover unrelated MCP servers, TOML content outside the
managed block, unmanaged collisions, edited owned entries, blocks and files,
obsolete entries, missing pinned commits, runtime mismatch, a pre-existing
root `AGENTS.md`, `CLAUDE.md` as a symlink and as a regular file, refusal
with unstaged or untracked managed paths, two installers started at once,
destinations on another filesystem than the temporary directory, and an
injected failure after each publication step, including during Isabelle
`init`'s session scaffold: the printed commands restore the tree, `check`
and doctor fail until they do, and a retry then succeeds. Adoption runs
`update` against a snapshot of the offer-exchange checkout (a linked
worktree at its current commit), with its own `.claude/skills/`, root
`AGENTS.md` and `CLAUDE.md` symlink. Both doctors are checked to be
read-only: `git status` and a file listing of the project and the runtime
checkouts are the same before and after.

For the board, run the original shell tests and behavioural regressions,
renamed with the code, before changing behaviour. Delete the three
regressions that exercise `migrate` together with it, and rewrite the one
that uses the bare `jedit` shorthand for `token:jedit`; the remaining 28
must pass unchanged. Add coverage for executable resolution, shared state
and lock identity across linked worktrees, both Git guards under real Git
operations, foreign-hook chaining, a commit in another worktree with an
explicit handle, a guard whose recorded executable no longer matches, a
failure between the two guard writes, a `core.hooksPath` outside the Git
directory, the incomplete-state cases, and the ic2 notifier returning
within its timeout while another process holds the board lock. Verify
exactly one digest route and one coordination skill in fresh host sessions,
using the explicit digest workflow on Codex.

In fresh sessions started at the root and in a subdirectory, list the
worker profiles and tools each host offers, and have the proof worker
attempt an I/Q call, which must be unavailable to it. Exactly one worker
definition and one main-session `iq` server may be visible, so that a
passing smoke proof cannot hide a user-level or plugin duplicate.

Behavioural scenarios, on both hosts: an ordinary editing task that does
not mention the board, where the agent should consult the skill and board
and claim before editing; the same after compaction or resume; an
independent delegated worker without inherited context; a supervised worker
with only its brief, where the coordinator claims first and keeps ownership
until the worker stops, the worker stays in scope with no board or Git
operations, and the coordinator commits without bypassing guards; several
supervised workers with disjoint assignments; a scope-expansion request; a
missed check-in or unavailable coordinator; an explicit transfer to
independent mode; and a check that the exception does not suppress ordinary
coordination. These depend on model behaviour, so treat them as recorded
observations rather than pass/fail gates: run each at least three times per
host, record every outcome and how compaction or resume was triggered, and
fix any protocol violation in the skill, instruction block or worker profile
before moving `stable`. After failure injection, recheck board and host
session state; a passing file-copy check is not enough.


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

## 2026-10-04: descriptors read the same in Python and the shell

Candidates
: isabelle-formal-modeling-tooling `6dc3820`, this commit's parent: both
  descriptor parsers split lines at LF alone, take only spaces and tabs as
  blank, and refuse a carriage return or a NUL byte by name, and the
  shell's `..` check no longer expands path values as globs. A Codex
  review of the theory projects found the disagreement; the theory plan's
  History has the review. The fixtures ran at `84f0ffc`, which differs
  from it only in that History. AutoCorrode `dbd474f`, as before.
: agent-board `b215a93`, the validation record of `8378248`, whose shared
  module has the same parser.

Hosts
: None: no host session ran, because nothing a host loads changed.
: Isabelle2025-2, Git 2.43, Python 3.12.3, on Linux.

Setup
: As in the previous record, with the board checkout under test named by
  `AGENT_BOARD_ROOT`.

Passed
: `make validate`, including descriptors with CRLF line ends, a lone
  carriage return, NUL bytes, other separators inside a value, lines of a
  form feed or a no-break space, and a glob path value, each read the
  same, values included, by both parsers; and install tests of a CRLF
  descriptor in every verb and doctor, of switching kinds through
  `update` and in link mode, and of an explicit `model_kind=code` at a
  revision from before kinds.
: Installers, doctors and the command interface: 76 checks on the bare
  repository and 75 on the stellar-core clone, all but the check of
  `init` at the previous `stable`, whose doctors fail while the runtimes
  are at the candidates.
: The shared module is byte-identical in both repositories.

Not rerun
: The behavioural scenarios, link mode on a host, the worker smoke proof
  and `make check-isabelle`: no skill, instruction block, worker profile,
  template or theory changed.

Observations
: A descriptor saved with CRLF line endings used to pass `sync` and fail
  doctor with `unsupported format_version: 1`; now every verb and doctor
  refuse it, naming the carriage return.

## 2026-10-08: the proving skill's search and statement sections

Candidates
: isabelle-formal-modeling-tooling `9896af6`, this commit's parent: two
  sections in `isabelle-proving`. "Searching and closing goals" covers
  `try0` before sledgehammer, backing diagnostic REPL steps out,
  `find_theorems` and `find_consts` through I/Q and ic2 with their
  pattern pitfalls, and rule attributes. "Abstract definitions and
  statements", for specifications and theory projects, covers searching
  the libraries before defining, statements before proofs, structured
  statements, and basic rules after a definition, used instead of
  unfolding it. AutoCorrode `dbd474f`, as before.
: agent-board `b215a93`, as before.

Hosts
: Claude Code 2.1.295 with claude-opus-5-5, in auto permission mode.
: Codex CLI 0.161.0 with gpt-6-astra at medium reasoning effort, in the
  workspace-write sandbox with automatic review.
: Isabelle2025-2, Git 2.43, Python 3.12.3, on Linux.

Setup
: As in the previous record. The theory host fixture of 2026-10-03, with
  a third task in a fresh session: a predicate `majority x xs`, for an
  element occurring in more than half of the positions of a list, and the
  lemma that a list has at most one majority element. HOL already counts
  occurrences with `count_list`, and the proof needs one supporting lemma.

Passed
: `make validate` and `make check-isabelle`.
: Installers, doctors and the command interface: 76 checks on the bare
  repository and 75 on the stellar-core clone, all but the check of
  `init` at the previous `stable`, whose doctors fail while the runtimes
  are at the candidates.
: On both hosts, in the theory fixture: discovery of exactly the two
  project skills and the worker profile; the recursive function, and the
  locale with its model lemma, as in the 2026-10-03 record; and the
  majority task. Both hosts read `isabelle-proving`, defined `majority`
  over HOL's `count_list` instead of a counting function of their own
  (Codex after grepping `List.thy` for it), proved `majorityI` and
  `majorityD` right after the definition and used `majorityD`, not the
  definition, in the uniqueness proof, stated the supporting bound on two
  distinct counts as a lemma of its own, wrote both lemmas with named
  assumptions, ran `quickcheck` and `nitpick` in a REPL, and left no
  diagnostic command or `sorry` in the theory. Every session built,
  committed and stopped its server, and doctor passed.

Not rerun
: The behavioural scenarios, link mode on a host, the worker smoke proof
  and the code-project host fixture: the worker profiles, the board
  skill, the instruction block and the link code did not change, and the
  only code-level text the skill changed is the scope of the
  unfold-and-split rule.

Observations
: Every proof in the three tasks closed with the first method tried, so
  no host ran `try0` or sledgehammer, and none called `find_theorems` or
  `find_consts`; the search section was exercised only by the reuse of
  `count_list`.
: No run at the previous `stable` served as a baseline, so the record
  does not attribute the basic rules to the new section.
: The four sessions cost $1.25 on Claude Code; on Codex they read 1.45M
  input tokens, 92% of them cached, and wrote 8.9k.
