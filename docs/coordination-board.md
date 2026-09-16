# Coordination board for concurrent agents

Design and plan for `scripts/board.sh`, the `isabelle-coordination` skill,
and the pieces around them. Written 2026-09-16 on branch
`coordination-board`; the *Plan* section records what is done. Status:
all six phases implemented on that branch, `make validate` passes, awaiting
review against the checklist below.

## Problem

A project using this tooling had several agents, Claude Code and Codex CLI
sessions, working at once on one repository: one in the main checkout that
jEdit owns (the I/Q workflow), others in linked worktrees with their own ic2
servers. In one afternoon:

- One agent's commit of a shared planning file swept in another agent's
  uncommitted edits to the same file, because both edit the same working
  tree and neither knew the other was in it. The history had to be split
  afterwards.
- A branch moved under an agent in the middle of a history rewrite. Only a
  guarded `update-ref` caught it.
- Nobody could see which worktrees were active, which ic2 servers were
  live, who was editing theories through I/Q, or which branch was about to
  be merged.
- The planning file served as the de facto message board: agents read each
  other's handoffs there and re-planned. It is a decision log, not a live
  board, and it is the file that collided.

The skills already state the rule ("agree who owns a passage before editing
it"; "the coordinator does not edit the delegated worktree concurrently")
but give no mechanism for reaching or recording the agreement.

## Goals and non-goals

Goals:

- One place, shared by every worktree of a repository, where agents post
  presence, claims, handoffs and notes, and where a human can read them.
- Claims on files, refs and the jEdit worktree that a `pre-commit` hook
  enforces, so the sweep above cannot happen silently again.
- Host neutrality: a shell script and files; Claude Code and Codex agents
  use it the same way, by instruction from a shared skill. Host-specific
  delivery (Claude Code hooks) is an add-on, never the only path.
- No daemon, no lock files that survive a crash, nothing under `$HOME`.

Non-goals:

- Real-time messaging. Agents read the board at defined moments (start,
  before editing a shared file, before moving a ref, before merging, on
  handoff), plus whatever their host can push.
- Replacing the project's decision log. The board is ephemeral
  coordination; decisions still go to the project's plan file.
- Cross-machine use. The board lives in the local Git common directory. A
  Git-branch backed variant could follow if agents ever run remotely.

## Design

### Location

The board directory is `<git common dir>/isabelle-tooling/board`. The Git
common directory (`git rev-parse --git-common-dir`) is the same for the main
checkout and every linked worktree, is not part of any working tree, needs
no ignore rule, and survives worktree removal. An agent in a worktree reaches
it without leaving the worktree. `ISABELLE_BOARD_DIR` overrides the location
(tests; unusual layouts). Outside a Git repository the script fails and names
the variable.

Resources that are paths are recorded relative to the worktree root, so the
same claim means the same file in every worktree.

### Identity

Every writing action carries a handle: `--as HANDLE`, or the environment
variable `ISABELLE_BOARD_AGENT`. Handles are short lowercase names
(`^[a-z0-9][a-z0-9._-]*$`), by convention the worktree or the topic:
`main`, `tx-layer`, `env-repair`. Read-only actions need no handle.

The `pre-commit` guard has no handle argument. It uses
`ISABELLE_BOARD_AGENT` when set; otherwise it infers the committer as the one
active agent whose presence names the current worktree. When two agents
share a worktree the inference is ambiguous and every active claim counts as
foreign, so agents sharing a worktree pass the variable on their commits.

### Presence

`hello --task TEXT` writes `agents/<handle>` with the worktree, branch, task
and start time. Every later action by that handle refreshes the file's
modification time, which is the agent's last activity. `bye` releases the
agent's claims and removes the file. `who` lists agents with their last
activity.

### Posts

One file per post under `posts/`, named
`<UTC time>-<handle>-<random>.md`, written to a temporary name and moved
into place. No locking, no conflicts, and directory order is time order.
A post is a few `key=value` header lines (`time`, `from`, `kind`, `re`), a
blank line, and the body. Kinds: `note` (default), `handoff`, `request`,
`done`, `server`, plus the automatic `hello`, `bye`, `claim`, `release`.
`show` renders the board; `digest` prints only what is new since a named
cursor and stays silent when nothing is new, which is what a host hook
needs.

### Claims

`claim RESOURCE... --reason TEXT` records a lease under
`claims/<sanitized resource>-<8 hex of sha256>/` as `resource`, `owner`,
`reason` and `since`. The directory is created with `mkdir`, which is atomic,
so two agents cannot both win. A resource is:

- a path relative to the worktree root (`PLAN.md`, `formal/`); an existing
  directory is recorded with a trailing slash and covers everything below it;
- a ref (`refs/heads/main`), meaning "I am about to move or rewrite it";
- a token such as `jedit` for the I/Q editing session, or `path#fragment`
  for a passage of a file. Fragment claims are advisory: shown, not
  enforced, so two agents can hold different passages of one theory and
  both commit.

A claim is *stale* when its owner has shown no board activity for
`ISABELLE_BOARD_STALE_MINUTES` (default 180) or the owner's presence is
gone. Stale claims are shown as such, do not block, and can be taken over;
`claim --force` takes over an active claim and posts the takeover with its
reason. `release RESOURCE...` or `release --all` ends a lease; the guard
never releases anything on its own.

### Guard and pre-commit hook

`guard --staged` lists the staged paths (old and new names, no rename
detection) and the current branch ref, and fails when any of them is
covered by an active claim of another agent, naming the owner, the reason
and the time. Explicit paths can be checked too (`guard PATH...`) before an
edit. `install-hook` writes a `pre-commit` hook into the repository's hooks
directory, which every worktree shares, calling `board.sh guard --staged`
by the tooling clone's absolute path. An existing foreign hook is kept and
chained with `--force`, which renames it to `pre-commit.pre-board`. The hook
is silent and passes when the repository has no board yet, so installing it
in a repository nobody coordinates on costs nothing. `git commit --no-verify`
bypasses it; the skill asks agents to post why when they do.

### Digest and host delivery

Claude Code: the extension declares `SessionStart` and `UserPromptSubmit`
hooks running `bin/board-hook.sh`, which resolves the tooling clone from
`ISABELLE_TOOLING_ROOT` like `bin/iq-bridge.sh` does and runs
`board.sh digest --cursor session-<id> --mark`, with `--full` on
`SessionStart` because a starting, resumed or compacted session has no
memory of earlier posts. Its output enters the session as context; it
prints nothing when the repository has no board or nothing is new, and
always exits 0 so it can never block a prompt. The declaration lives in
`hooks/board-hooks.json`, named from the manifest's `hooks` field rather
than at the default `hooks/hooks.json`, so the file is registered exactly
once whichever discovery rule the host applies.

Codex CLI: no hook is assumed. The skill instructs agents to run `digest`
at the start of a task, before editing a shared file, before a merge or a
ref move, and before returning; the Git hook is host-neutral.

### ic2 and doctor

`ic2.sh start` and `stop` post a `server` note from the system handle `ic2`
when the repository already has a board, so live servers are visible next
to the agents that own them. Nothing is posted when there is no board.
`doctor.sh` reports the board when one exists: agents, stale claims, and
whether the shared hook is installed and points at this clone.

### What goes where

Board: who is active where, what they hold, what is ready for whom, what
they need from others, when they leave. Project plan file: decisions and
milestones, copied over at handoff by whoever posts "ready to merge".

## Plan

- [x] P1 `scripts/board.sh`: resolution, identity, `hello`, `bye`, `who`,
  `post`, `show`, `digest`, `claim`, `release`, `claims`, `path`; tests in
  `tests/board_test.sh` on a temporary repository with a linked worktree.
- [x] P2 `guard`, `install-hook`, `uninstall-hook`; tests that a real
  `git commit` is refused for a foreign claim, allowed for the owner and for
  stale claims, and that identity inference by worktree works.
- [x] P3 `extension/skills/isabelle-coordination/SKILL.md`; board section in
  `agents/ic2-prover.instructions.md`, re-rendered; cross-reference from
  `isabelle-proving`'s delegation section.
- [x] P4 Claude Code hooks: `extension/hooks/board-hooks.json`,
  `extension/bin/board-hook.sh`, manifest entry, JSON validated by
  `make validate`.
- [x] P5 `ic2.sh` server notes; `doctor.sh` board section.
- [x] P6 README (tree listing, a Coordination section), architecture note,
  this document's status.

## Review checklist

- Two agents claiming the same resource at once: exactly one wins
  (`mkdir`).
- The guard blocks a foreign active claim, passes the owner, passes a stale
  claim with a warning, and blocks when identity is ambiguous and a claim
  matches.
- Prefix claims (`formal/`) cover nested paths; fragment claims never block.
- A repository without a board: every read-only action and the hook are
  silent successes; `post`, `claim` and `hello` create the board.
- Nothing is written under `$HOME`; nothing is written into a working tree.
- ShellCheck clean; `make validate` passes; rendered agent profiles current.
- The skill tells a Codex agent everything it needs without hooks.

## Open questions

- Should `ic2.sh` also refuse `start` when another agent's presence names
  the same worktree? Left out: one server per worktree is already enforced
  by the server name.
- Should `digest` be injected on every prompt or only at session start?
  Both are declared; the per-prompt hook is silent unless something is new,
  so the cost is one process per prompt.
- A `PreToolUse` hook on `git commit` would duplicate the Git hook with less
  precision; not added.
