# Validation records

`stable` names the commit that appended the newest entry below. Each entry
is a validation record commit: the commit at which the fixtures below
passed, plus the entry itself. The mechanical checks are rerun at exactly
that commit before `stable` moves to it.

The records from 2026-09-29 to 2026-10-29 ran earlier fixtures and are in
Git history: `git show f5460ce:docs/validation.md`.

## Fixtures

Run the acceptance fixtures in a fresh Git repository and a small existing
codebase. Use isolated host configurations on Claude Code and Codex CLI
and start sessions from the checkout root and a subdirectory. Run Codex
fixtures at medium reasoning effort in the background with stdin closed.

Confirm skill, agent and I/Q discovery, including the root `.mcp.json` and
symlinked skill aliases from a subdirectory. In link mode, make a skill edit
in the development worktree and confirm a fresh host session sees it. Run
`sync` to restore the copies and confirm the tree is clean. Connect through
I/Q and delegate one smoke proof to the worker.

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
with unstaged or untracked managed paths, concurrent installer runs,
destinations on another filesystem than the temporary directory, and an
injected failure after each publication step, including during Isabelle
`init`'s session scaffold: the printed commands restore the tree, `check`
and doctor fail until they do, and a retry then succeeds. Adoption runs
`update` against a snapshot of the offer-exchange checkout (a linked
worktree at its current commit), with its own `.claude/skills/`, root
`AGENTS.md` and `CLAUDE.md` symlink. Confirm that doctor is read-only by
checking Git status and listing files in the project and runtime checkouts
before and after.

In fresh sessions started at the root and in a subdirectory, list the
worker profiles and tools each host offers, and have the proof worker
attempt an I/Q call, which must be unavailable to it. Exactly one worker
definition and one main-session `iq` server may be visible, so that a
passing smoke proof cannot hide a user-level or plugin duplicate.

## 2026-11-25: Isabelle2026 with PIDE AI, and no agent-board

Candidates
: isabelle-formal-modeling-tooling `4df9533`, this commit's parent. The
  fixtures ran at `c9e0372`, which differs from it only in this file's
  opening paragraph. The candidate adds the opt-in Isabelle2026 release
  with the PIDE AI MCP server (`306d28c`, `25771f7`), removes the
  agent-board integration, and fixes the review findings (`d13a255`).
: AutoCorrode `9c06706`, unchanged. PIDE AI `6618654`, the tooling's pin of
  kappelmann/isabelle-pide-ai.

Hosts
: Claude Code 2.1.332 with claude-opus-5-5, in auto permission mode.
: Codex CLI 0.172.0 with gpt-6.2-astra at medium reasoning effort, with
  automatic review in the workspace-write sandbox.
: Isabelle2025-2 (`89701cf1768e`) and Isabelle2026 (`096842708b28`),
  Git 2.43.0, Python 3.12.3, on Linux.

Setup
: The runtime was the tooling checkout at the candidate. The fixtures used
  their own Isabelle user home (`USER_HOME`), holding the ic2 registration,
  the I/Q plugin and the PIDE AI registration for both releases.
: The hosts ran with the user's own configuration, which holds no Isabelle
  skill, worker profile, `iq` or PIDE server: fresh configuration roots
  would have needed copies of the hosts' login credentials.
: Fixtures: fresh `git init` repositories, a shallow clone of stellar-core,
  and clones of the three offer-exchange projects at their commits pinned
  to `43cb769`.

Passed
: `make validate` (44 Python tests, the shell tests and the rendered
  profiles) and `make check-isabelle` on Isabelle2025-2 and on
  Isabelle2026: export-check fixtures, the model runner including a
  resident-mode input failure, and both template kinds including FSet. Run
  at the candidate and again at this record commit.
: `setup-pide-ai.sh` in the fixtures' user home: it fetched the pin,
  registered it and built its JARs.
: 90 mechanical checks, at the candidate and again at this record commit:
  - On Isabelle2025-2: `init` of a code project in a fresh repository and
    in stellar-core, and of a theory project; the installed skills, worker
    profiles, `iq` server and blocks, with no agent-board text;
    `sync --check`, `sync` keeping the pin, read-only doctors and session
    builds.
  - On Isabelle2026: `init` of a theory and a code project, with
    `isabelle-pide-ai` and neither `isabelle-proving` nor `isabelle-setup`,
    the PIDE server and its Codex timeouts, and no ic2 worker or `iq`;
    read-only doctors and session builds. Doctor fails without the PIDE AI
    registration and, given Isabelle2025-2 as Isabelle2026, names
    `ISABELLE_TOOLING_ISABELLE2026`.
  - Switching a project to Isabelle2026, where `ic2.sh` still runs `name`
    but refuses `start`, and back, which restores the original files.
  - `update` of the three offer-exchange projects from `43cb769`, after
    which their installed files no longer mention agent-board and their
    doctors pass.
  - The command interface: `skills show` matching the pinned Git object
    from a subdirectory, `skills list` naming the pin, `--project-root`,
    unknown skills, a skill of the other release, a malformed descriptor and
    a missing pinned commit.
: Claude Code discovery from the root and from `formal/`. An Isabelle2025-2
  project showed one copy of each of its five skills, one `ic2-prover` and
  one `iq` server. An Isabelle2026 project showed only `isabelle-pide-ai`
  and `isabelle-pide-mcp`, with its 14 tools.
: Codex discovery of the project's skills from the root and from
  `formal/`, for both releases.
: The worker smoke proof on both hosts: the coordinator created the ic2
  worktree with `ic2.sh worktree add`, the worker passed `preflight`, had no
  I/Q tool on Claude Code, proved the lemma through ic2, built the session,
  committed and stopped its server, and the coordinator reviewed the diff.
  On Codex the worker role and `iq` server came from the overrides below;
  no session there had an I/Q tool, since the `iq` server cannot start
  without a jEdit, so that probe shows nothing about the profile.
: The PIDE AI smoke proof on both hosts, in the main session: doctor,
  `list_sessions`, `get_session_state`, `read`, `edit_get_state` and
  `get_state` proved the lemma with Isabelle symbols kept escaped on disk;
  the Isabelle2026 session build passed and the change was committed.

Not rerun
: Codex's loading of a trusted project's `.codex/config.toml`. Trusting the
  fixtures would have changed the user's Codex configuration, so the Codex
  sessions received the managed block's MCP server and the worker role as
  one-off `-c` overrides with the same values.
: An I/Q connection, the jEdit fixture, link mode on a host and the
  behavioural scenarios. No jEdit ran, so Claude Code listed the `iq`
  server as failed. The bridge, the link code and the jEdit worktree guard
  are unchanged. `launch_jedit.sh` only gained a refusal for Isabelle2026
  projects, which no test covers; a dry run refused an Isabelle2026 fixture
  and printed the command for an Isabelle2025-2 one.
: The phase 4 modeling fixture: the modeling skill changed only in naming
  each release's proof skill, and the setup skill only in dropping its
  board section.

Observations
: Without trust, Codex discovered the project's skills but not its MCP
  server or worker role, and warned that untrusted project-local
  configuration is disabled.
: `ic2.sh start` refuses in an Isabelle2026 project with exit status 2,
  like its other refusals.
: On Codex, the coordinator's first `ic2.sh worktree add` failed in the
  sandbox and passed when retried with approval.
: The six Claude Code sessions cost $2.31. The two Codex smoke proofs'
  coordinators read 0.93M input tokens, 94% of them cached, and wrote 3.1k.
