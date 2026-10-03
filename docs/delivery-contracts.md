# Contracts: project delivery for the Isabelle tooling and agent-board

Step 1 of [the delivery plan](new-project-delivery-plan.md), drafted and
design-reviewed on 2026-09-28 (the plan's History has the review). The plan
says what is built and why; this document fixes the interfaces that the two
installers, the two doctors, the Isabelle adapter and the fixtures must
agree on. Where the two disagree, this document wins and the plan is
corrected. Step 2 copies the shared rules and the agent-board part into
`docs/project-integration.md` in the new board repository, which then owns
them; each repository keeps its own copy of the shared rules, and a change
to them is made in both.

Step 2 moved the agent-board part to that repository, which owns it now;
only a pointer remains below. Step 2 implemented the ic2 notifier in "Board
adapter", and step 3 the rest: the shared rules in `scripts/project_files.py`
(an identical copy of agent-board's `src/project_files.py`), the Isabelle
project files, `bin/isabelle-tooling`, the doctor additions and the board
adapter. Where the implementation settles a detail left open,
"Decisions made in implementation" at the end records it.

## Shared rules

**Terms.** The *checkout root* is `git rev-parse --show-toplevel` of the
checkout a command runs in, or of `--project-root DIR`. A *component* is
`isabelle-tooling` or `agent-board`. Its *runtime checkout* is the clone
that runs its code: the directory `ISABELLE_TOOLING_ROOT` names, or the
checkout containing the resolved `agent-board` executable. A *managed
path* is one a component's inventory records.

**Descriptors.** One per component at the checkout root:
`isabelle-tooling.conf` (its existing format, `format_version=1`, with the
keys the Isabelle tooling defines) and `agent-board.conf`:

```text
# agent-board project descriptor. Data only: key=value, never sourced.
format_version=1
board_revision=<40-hex commit>
```

Both are data only: one `key=value` per line, `#` comment lines and blank
lines allowed, never sourced. The revision is always a full 40-hex commit,
never a ref. `agent-board.conf` rejects unknown keys. A descriptor's
presence is what "this project uses the component" means: nothing else,
such as a board directory or a skill, turns a component on.

**Inventory.** `.isabelle-tooling/inventory.json` and
`.agent-board/inventory.json`, written with `json.dumps(indent=2,
sort_keys=True)` and a final newline:

```json
{
  "format": 1,
  "component": "agent-board",
  "revision": "<40-hex commit>",
  "mode": "copy",
  "link_source": null,
  "claude_skills": "aliases",
  "directories": [".agents/skills/agent-coordination"],
  "files": {
    ".agent-board/claude-hook.sh":
      {"sha256": "<hex>", "executable": true},
    ".agents/skills/agent-coordination/SKILL.md":
      {"sha256": "<hex>", "executable": false}
  },
  "symlinks": {
    ".claude/skills/agent-coordination":
      "../../.agents/skills/agent-coordination"
  },
  "json_entries": [
    {"file": ".claude/settings.json", "pointer": "/hooks/SessionStart",
     "element": true, "sha256": "<hex>"}
  ],
  "blocks": [
    {"file": "AGENTS.md", "syntax": "markdown", "sha256": "<hex>"}
  ]
}
```

- `mode` is `copy` or `link`; `link_source` is the absolute source checkout
  in link mode and `null` otherwise.
- `claude_skills` is `aliases` (per-skill symlinks under `.claude/skills/`)
  or `shared` (see "Skill directories").
- `directories` are wholly owned: any entry inside one that `files` does
  not list is drift.
- Paths are relative to the checkout root, with `/` separators.
- The inventory never records itself or the descriptor.

**Owned JSON entries.** An entry is either an object member, recorded by
the JSON Pointer of the member (`/mcpServers/iq`), or one element of an
array, recorded by the array's pointer with `"element": true`. The hash is
SHA-256 of `json.dumps(value, sort_keys=True, separators=(",", ":"),
ensure_ascii=False)` encoded as UTF-8.

- Array elements are identified by content, not index: each component
  names a marker string that appears in its element (the board's hook
  elements contain `.agent-board/claude-hook.sh`). Exactly one element per
  recorded array may contain the marker; its hash must match.
- Writes load the file with the standard library, change only the owned
  entry, keep member and array order, and write `json.dumps(indent=2,
  ensure_ascii=False)` plus a newline. Adding a new member or element
  appends it.
- `remove` deletes the owned member or element, then prunes containers left
  empty along its pointer, and deletes the file when `{}` remains.
- An unmanaged member with the owned name, or an unmanaged element carrying
  the marker, is a collision: install refuses.

**Owned TOML block.** Only `.codex/config.toml`, owned by
`isabelle-tooling`. The block is the text between the whole lines
`# BEGIN isabelle-tooling` and `# END isabelle-tooling`, both included; the
file may contain exactly one of each, in that order. The first install
appends the block at the end of the file (creating the file when absent,
separated from existing text by one blank line); later writes replace it in
place, and all text outside it is kept byte for byte. `check` parses the
whole file with `tomllib` (Python 3.11 or later) and requires the parsed
`mcp_servers.iq` to equal the block parsed alone. That catches
duplicate tables, and bare keys after `# END` that TOML would attach to the
block's last table. An `[mcp_servers.iq]` table outside the block is a
collision.

**Owned Markdown blocks.** In root instruction files, the text between the
whole lines `<!-- BEGIN NAME -->` and `<!-- END NAME -->` (`NAME` is the
component), at most one pair per component per file. The first install
appends the block, separated by one blank line; later writes replace it in
place. The hash covers the lines strictly between the markers. The block's
first line is a comment naming the command that changes it.

**Root instruction files.** Only `AGENTS.md` and `CLAUDE.md` at the checkout
root. Before writing, resolve each existing one through symlinks; a target
that is not a regular file inside the checkout is refused. The block goes
into the set of resolved files:

- neither exists: create `AGENTS.md`, and `CLAUDE.md` as the relative
  symlink `CLAUDE.md -> AGENTS.md`; the set is `{AGENTS.md}`;
- both resolve to the same file: that file, recorded once;
- only `AGENTS.md` exists: it, and create the `CLAUDE.md` symlink;
- only `CLAUDE.md` exists: its target, and create `AGENTS.md` as a regular
  file holding only the block;
- both exist and resolve differently: both.

A file or symlink an installer creates here belongs to the project, not
the component: the inventory records only blocks, and `remove` leaves the
files in place, even empty.

**Skill directories.** Skill content lives in `.agents/skills/NAME/`, which
Codex discovers; Claude Code sees it through a relative symlink
`.claude/skills/NAME -> ../../.agents/skills/NAME`. When `.claude/skills`
itself resolves to the same directory as `.agents/skills` (a project-wide
alias), no per-skill symlinks are made and the inventory records
`claude_skills: shared`. When `.agents`, `.claude`, `.agents/skills` or
`.claude/skills` is a symlink resolving outside the checkout, install
refuses. `isabelle-tooling` owns the `isabelle-*` names its manifest
lists and `agent-board` owns `agent-coordination`; any other directory
there is the project's and untouched. An existing unmanaged `NAME` is a
collision.

**Project kinds.** A component may divide its projects into kinds, named
in its descriptor; the Isabelle tooling does, agent-board does not. A
manifest's top-level `"kinds"` lists the kinds its revision supports. A
skill entry may carry `"kinds"`, the kinds it is installed for; a skill
entry without it is installed for every kind, and no other entry may carry
it. A project that names no kind gets every skill, whatever the lists say.
For a project that names a kind, `init`, `sync`, `update` and `check`
refuse a revision whose top-level list lacks it, including every revision
from before kinds, and install only the skills for that kind. In
`project_files.py` the kind comes from the spec's optional `kind(values)`
hook, given the parsed descriptor.

**Link mode.** `sync --link [--source DIR]` replaces each managed skill
directory in `.agents/skills/` with an absolute symlink to
`DIR/<source skill path>`, records `mode: link` and `link_source`, and
leaves the Claude aliases, which still resolve through `.agents/skills`.
`DIR` defaults to the runtime checkout, but is normally a development
worktree, so the runtime checkout stays clean at its pin. Only skills are
linked; configuration entries and worker profiles stay copies. Link mode
is development state: the working tree is dirty on purpose, `check`
reports it, and doctor fails on it unless given `--allow-dirty`. Plain
`sync` restores the copies. Nothing in link mode may be committed.

**Installer lock.** Every writing verb of either component (`init`,
`sync`, `update`, `remove`) holds an exclusive `flock` on
`$(git rev-parse --git-path project-files.lock)` from preflight until the
descriptor is written. The lock is per worktree, like the files, and lies
outside the working tree. It serializes the two installers, which share
the root instruction files and the skill parents. `check` and `doctor` take
no lock, and report whatever state they see.

**Preflight: the index is the checkpoint.** Before writing, an installer
lists every path it would create, modify or delete, and refuses if any of
them has unstaged changes (the working tree differs from the index),
exists untracked, or is ignored by Git. The one exception: in link mode,
`sync` may replace the symlinks and the inventory that `link` wrote. Staged
changes are accepted. So a new repository runs `init` for one component,
`git add` of the paths it printed, then `init` for the other, with no
commit in between. Every successful install prints its touched paths and
the `git add -- …` command. An installer never stages or commits.

**Writing and failure.** The complete result is first built in a
temporary directory and validated: JSON and TOML parse, block markers are
unique, and the inventory and descriptor agree. Each destination is then
rechecked against its preflight state and published by writing a
temporary file in the destination's own directory, `fsync`ing it and
renaming it over the destination, so no rename crosses filesystems. The
order is managed files, then shared entries and blocks, then the
inventory, then the descriptor last. A descriptor write changes only its
revision line, keeping the other keys and comments byte for byte.

If any write fails, the installer stops. It prints the leaf paths it
touched, each shell-quoted, with the commands that restore them:
`git restore -- PATHS` for paths the index knows, `rm -f -- PATHS` for new
files and symlinks, then `rmdir` for the directories it created, deepest
first. It then exits 2. Until the tree is restored, `check` reports the
disagreement between files, inventory and descriptor, and doctor fails.

**Project operations.** Both components offer the same verbs, run inside
the project:

`init [--revision REV]`
: Refuse if the descriptor exists. Resolve `REV` (default `stable`) in the
  runtime checkout to a full commit, and install exactly that revision:
  files, entries, the root instruction block, inventory, then the
  descriptor. `isabelle-tooling init` also renders the session scaffold
  that `new-project.sh` writes today, from the same Git object, and
  publishes it with the integration under the same rules, descriptor last.
  `new-project.sh` becomes that renderer, taking the resolved commit and
  reading its templates with `git show`; its options pass through `init`.

`sync`
: Install exactly the descriptor's revision in copy mode, reading every
  file from that Git object (`git show REV:PATH`), never a working tree.
  Idempotent. Refuses drift in managed content rather than overwriting it.
  Without an inventory it refuses and names `update`.

`sync --link [--source DIR]`, `sync --check`
: Link mode, above; and the read-only check, which exits 0 when files,
  inventory and descriptor agree with the pinned object and 1 otherwise.

`update REV`
: The only verb that changes the pin. Stage the target revision's files,
  merge the owned entries and blocks into the staged copies, validate,
  install, write the descriptor last. `update stable` moves to the current
  validated commit. Without an inventory, `update` is the adoption path
  for a project whose descriptor predates project delivery, such as the
  offer-exchange checkout. It validates the descriptor, requires every
  managed target to be absent (anything present, including an existing
  block, is a collision), and installs; the inventory is written, and then
  the new revision line last.

`remove`
: Delete the component's unchanged managed files, entries and blocks, its
  inventory directory and its descriptor. Refuse and list anything edited.
  Project content is never removed: not the Isabelle session under
  `formal_rel`, not the root instruction files, and not the board's runtime
  data or Git guards, which `remove` reports when present.

`doctor [--allow-dirty] [--json]`
: The component's full read-only check. See each component below.

All of these exit 0 on success, 1 when they refuse or a check finds a
problem, and 2 on a usage error, a missing prerequisite or a failed write.
The installable set is read from a manifest at the target revision
(`extension/project/manifest.json` for the tooling,
`integrations/project/manifest.json` for the board); a revision without
one cannot be installed.

**`stable` refs and the validation record.** Each repository keeps a local
branch `stable`. It moves only by fast-forward, and only to a validation
record commit: a commit whose parent is the validated commit, and whose
only change appends an entry to `docs/validation.md`. The entry records
the date, the validated commit, the other repository's revision when both
were exercised, the host versions, and the new-project fixture outcomes,
including the behavioural observations, and names the candidate commits
exercised in both repositories. The record commit is made on `main`, the
mechanical checks are rerun at exactly that commit (the repository's
tests, the installer tests, and doctor on a fixture project pinned to it),
and only then does `stable` fast-forward to it. `init` and `update stable`
pin that record commit. The runtime checkout has `stable` checked out, and
development happens on `main` in a linked worktree. The runtime moves with
`git -C RUNTIME merge --ff-only COMMIT`, followed for the tooling by
`git submodule update` and, if the AutoCorrode pin changed, the ic2 build
and I/Q plugin installation.

**Machine paths.** No committed file contains an absolute path or
credential. Machine paths come from the environment (`ISABELLE_TOOLING_ROOT`,
`AGENT_BOARD_COMMAND`, `PATH`) or from host-local configuration. Link-mode
symlinks and Git hooks are the only files that record absolute paths, and
neither is committed.

## agent-board

Moved in step 2, on 2026-09-28, to `docs/project-integration.md` in the
agent-board repository, which owns it and says what of it is implemented.
The Isabelle part below relies on its executable resolution, `version
--json`, `doctor --json` and its check ids, and the handle `ic2` reserved
for tool notes; a change to those is made there first.

## Isabelle tooling

**Entry point.** `bin/isabelle-tooling` in the tooling repository, with
`skills list`, `skills show NAME`, and the project verbs. Its skill
inspection follows the plan's "Instruction revision selection". It needs
Python 3.11 or later for `tomllib`.

**Manifest.** `extension/project/manifest.json` at each revision lists what
that revision installs: the skill names, the wholly managed files with
their source paths, the JSON entries, and the block templates. The
synchronizer reads the target revision's manifest, so a revision that adds
or drops a skill installs or removes it without code changes.

**Project files.**

- `isabelle-tooling.conf`, whose `tooling_revision` is the pin.
- `.isabelle-tooling/inventory.json`.
- `.agents/skills/isabelle-{setup,modeling,proving,differential,assurance}/`,
  each copied whole from `extension/skills/` at the pin, with their Claude
  aliases.
- `.claude/agents/ic2-prover.md`, from `extension/agents/ic2-prover.md`.
- `.codex/agents/ic2_prover.toml`, from `extension/agents/ic2_prover.toml`.
- In `.mcp.json`, the member `/mcpServers/iq`:

  ```json
  {"command": "${ISABELLE_TOOLING_ROOT}/extension/bin/iq-bridge.sh",
   "args": [], "env": {"IQ_MCP_BRIDGE_PORT": "8765"}}
  ```

- In `.codex/config.toml`, the block. Codex CLI 0.155.1 parsed this form in
  a user-level configuration on 2026-09-28, and exposed `env_vars`; the
  project-level layering is still a fixture check:

  ```toml
  # BEGIN isabelle-tooling
  # Managed by isabelle-tooling; change it with `isabelle-tooling update`.
  [mcp_servers.iq]
  command = "bash"
  args = ["-c", "exec \"$ISABELLE_TOOLING_ROOT/extension/bin/iq-bridge.sh\""]
  env_vars = ["ISABELLE_TOOLING_ROOT"]

  [mcp_servers.iq.env]
  IQ_MCP_BRIDGE_PORT = "8765"
  # END isabelle-tooling
  ```

- The `isabelle-tooling` block in the root instruction files, with
  `FORMAL_REL` substituted from the descriptor:

  ```markdown
  <!-- BEGIN isabelle-tooling -->
  <!-- Managed by isabelle-tooling; change it with `isabelle-tooling update`. -->
  ## Isabelle formal model

  This repository has an Isabelle model under `FORMAL_REL/`; read
  `FORMAL_REL/AGENTS.md` before working on it. The workflow is in the
  `isabelle-setup`, `isabelle-modeling`, `isabelle-proving`,
  `isabelle-differential` and `isabelle-assurance` skills. Start with
  `isabelle-setup` until `"$ISABELLE_TOOLING_ROOT/bin/isabelle-tooling"
  doctor` passes.
  <!-- END isabelle-tooling -->
  ```

The server name `iq` is fixed. The Claude worker profile's
`disallowedTools: mcp__iq` matches exactly the tools of a server named
`iq`. It would not have matched the retired plugin's server, whose tools
were named `mcp__plugin_<plugin>_iq__*`; with the project server, the
step-4 fixtures found that a Claude Code worker sees no I/Q tools.
The Codex profile disables `iq` by the same name, but Codex CLI 0.155 does
not honour that for a spawned agent: the step-4 fixtures found the main
session's I/Q tools listed to the worker, spawned with or without the
parent's conversation. There the worker's instructions, which forbid every
I/Q call, are the only barrier.

**Board adapter.** Coordination is configured when `agent-board.conf`
exists at the checkout root. The adapter never reads `board_revision`.

- `scripts/common.sh` records `AGENT_BOARD_INTERFACE=1`, the interface the
  adapter supports.
- The ic2 notifier runs only when coordination is configured and the
  executable resolves:
  `timeout 5 "$cmd" --project-root ROOT --if-board --as ic2 post --kind
  note …`, with stderr discarded and the exit status ignored. `post` waits
  on the board's lock, so the timeout is what bounds it. It never masks an
  ic2 result or delays one by more than five seconds, which a test checks
  with the board lock held. The handle `ic2` is reserved for these tool
  notes.
- Isabelle doctor, when coordination is configured, fails if the
  executable is unresolved. It also fails if `version --json` reports an
  interface other than 1, or lacks the `doctor` or `project` capability.
  The adapter never reads board storage, so it does not check
  `state_format`. Doctor then runs `doctor --json --project-root ROOT`,
  passing `--allow-dirty` through, and reports each board check as
  `board: ID: MESSAGE` with its status. Exit 2 or unparsable output is a
  failure. Without `agent-board.conf` it makes no board check and needs no
  executable.
- Proof-specific resources, named in the Isabelle skills and profiles:
  theory files, `refs/heads/BRANCH` for proof branches, and `token:jedit`
  for the human's main-worktree jEdit session.

**Doctor additions.** Besides today's checks, Isabelle doctor fails on:

- the Isabelle formal-modeling host plugin, or its marketplace, in either
  host's configuration;
- an `iq` MCP declaration at user level for either host (the project's is
  the one allowed);
- a user-level `ic2_prover` or `ic2-prover` profile, since it would
  duplicate the project's;
- any `sync --check` finding (link mode under `--allow-dirty` is a note);
- a runtime checkout, ic2 registration or jEdit I/Q plugin that does not
  match the pin.

It reads host configuration from `CLAUDE_CONFIG_DIR` and `CODEX_HOME` when
set, else `~/.claude`, `~/.claude.json` and `~/.codex`, so the fixtures can
isolate them. It is strictly read-only, like board doctor: today's
`doctor.sh` writes `.doctor-resolve.err` into the tooling clone, and that
goes. Isabelle doctor output stays human-readable only, since nothing
consumes it by machine.

## Delegation modes

A delegation brief states its mode on its first line, exactly one of:

```text
Mode: independent. Handle: HANDLE.
Mode: supervised by HANDLE.
```

An independent brief also gives the repository, the worktree and the
board to use, and requires reading
`.agents/skills/agent-coordination/SKILL.md` first.

A supervised brief gives:

- the assigned checkout;
- the allowed paths and resources;
- the permitted actions;
- the report or check-in boundary;
- the sentence "Stay within this scope; ask the coordinator before
  expanding it."

A worker in a project with `agent-board.conf` whose brief has no mode line
follows the independent protocol. Being a subagent never implies
supervision.

Both rendered proof-worker profiles carry the same two-mode section. A
supervised worker makes no board calls, commits, ref or index changes or
further delegations, and reports its edits and validation results. An
independent worker registers, claims its theories and branch, commits
under its own handle when the brief authorizes commits, and hands off
before `bye`. The ic2 notes are permitted in either mode.

A coordinator committing in a supervised worker's worktree names itself:
`AGENT_BOARD_AGENT=HANDLE git -C WORKTREE commit …`. The coordinator never
releases a claim while its worker may still write.

## Decisions made in implementation

Recorded on 2026-09-28 with step 3. The first list is the same in both
repositories' copies of the shared rules.

- `sync --check` exits 1 in link mode, since the files are not the pinned
  ones; `sync --check --allow-dirty` makes link mode a note, which is what
  both doctors use under `--allow-dirty`. It also fails when the runtime
  checkout is not at the pin, as "the running scripts come from that
  revision" requires; board doctor reports that as `executable.revision`
  and folds only the file findings into `files`.
- The inventory records a `marker` with each array-element entry, so an
  entry that a later manifest drops can still be found and removed.
- Installed files get Git's checkout modes, 0777 or 0666 less the umask, so
  a `git restore` after a failure gives the same modes.
- Restore commands are printed as `rm -f`, then `rmdir`, then `git
  restore`, run from the checkout root, so that `git restore` never writes
  through a symlink an install created. A link-mode symlink removed by a
  failed install is not recreated by them; the message says to rerun
  `sync --link`.
- `update` refuses in link mode; `sync` first restores the copies.
- `remove` without an inventory refuses, and `remove` also refuses when
  the inventory directory holds files it did not install.
- An emptied JSON file is deleted, and so is a TOML file left empty by
  removing its block; directories left empty by deletions are removed,
  never the checkout root.
- There is no gitignored local state yet, so neither inventory directory
  has its own `.gitignore`.

For the Isabelle tooling only:

- The synchronizer the plan calls `scripts/sync-extension.sh` is
  `scripts/isabelle_tooling.py` with the shared `project_files.py`;
  `bin/isabelle-tooling` sends `doctor` to `doctor.sh` and the rest there.
- `new-project.sh` takes `--revision COMMIT --stage DIR` and renders into an
  empty directory; it no longer writes into a checkout itself. The
  session README no longer embeds the revision, which `update` would make
  stale; it points at `tooling_revision`.
- `skills list` prints its revision on its first stdout line; `skills
  show` keeps stdout to the file's bytes. Inside a project means below the
  nearest `isabelle-tooling.conf`, as `ic2.sh` resolves it.
- Doctor also fails when `ISABELLE_TOOLING_ROOT` is unset or names another
  checkout, and on a local-scope `iq` server that `~/.claude.json` records
  for the project. The extension `REVISION` comparison is gone already,
  since an installed plugin now fails doctor.
- The proof-worker instructions, rendered into both profiles, carry the
  two-mode section; the proving skill says how to brief each mode.
